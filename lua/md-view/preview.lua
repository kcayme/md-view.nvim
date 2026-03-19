local M = {}

---@class MdViewPreview
---@field server userdata TCP server handle
---@field port integer
---@field sse MdViewSse
---@field watcher table

local uv = vim.uv or vim.loop
local server = require("md-view.server.tcp")
local router = require("md-view.server.router")
local direct = require("md-view.server.handlers.direct")
local sse = require("md-view.server.sse")
local buffer = require("md-view.buffer")
local theme = require("md-view.theme")
local util = require("md-view.util")
local hub_mod = require("md-view.server.handlers.hub")

local active_previews = {}
local _mux = nil

local function get_mux()
  return _mux
end

-- Read current content for bufnr: from buffer if it has unsaved edits, from disk otherwise.
-- callback(content_string) is always called from the main Neovim thread.
local function read_content_async(bufnr, callback)
  local modified = vim.api.nvim_get_option_value("modified", { buf = bufnr })
  if modified then
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    callback(table.concat(lines, "\n"))
    return
  end
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == "" then
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    callback(table.concat(lines, "\n"))
    return
  end
  uv.fs_open(filepath, "r", 438, function(err, fd)
    if err or not fd then
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          callback(table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n"))
        end
      end)
      return
    end
    uv.fs_fstat(fd, function(ferr, stat)
      if ferr or not stat then
        uv.fs_close(fd, function() end)
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(bufnr) then
            callback(table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n"))
          end
        end)
        return
      end
      uv.fs_read(fd, stat.size, 0, function(rerr, data)
        uv.fs_close(fd, function() end)
        vim.schedule(function()
          if rerr or not data then
            if vim.api.nvim_buf_is_valid(bufnr) then
              callback(table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n"))
            end
          else
            callback(data)
          end
        end)
      end)
    end)
  end)
end

-- Start hub if not already running. Returns hub instance or nil on failure.
local function ensure_mux(opts)
  if not _mux then
    _mux = hub_mod.new()
    _mux.on_client_added = function(client)
      for buf, _ in pairs(active_previews) do
        if _mux.registry[buf] then
          read_content_async(buf, function(content)
            pcall(function()
              client:write("event: content\ndata: " .. vim.json.encode({ id = buf, content = content }) .. "\n\n")
            end)
          end)
        end
      end
    end
  end
  if not _mux.server then
    local handle = router.new(hub_mod.routes, { hub = _mux })
    local srv, p = server.start(opts.host, opts.port, handle)

    if not srv then
      _mux = nil
      return nil
    end

    _mux.server = srv
    _mux.port = p

    -- VimLeavePre safety net (registered once)
    if not vim.g.md_view_mux_vimleave_registered then
      vim.g.md_view_mux_vimleave_registered = true
      vim.api.nvim_create_autocmd("VimLeavePre", {
        group = vim.api.nvim_create_augroup("md_view_mux_global", { clear = true }),
        callback = function()
          if _mux then
            local cfg = require("md-view.config")
            local sp = cfg.options and cfg.options.single_page
            local close_by = sp and sp.close_by
            -- Mirror M.destroy: push preview_removed for each registered preview
            for bufnr, _ in pairs(_mux.registry) do
              _mux:push("preview_removed", { id = bufnr })
            end
            local should_close = close_by == "page"
              or (close_by == nil and cfg.options and cfg.options.auto_close == true)
            if should_close then
              _mux:push("close", {})
            end
            server.stop(_mux.server)
            _mux.server = nil
            _mux.port = nil
            _mux:close_all()
          end
        end,
      })
    end
  end
  return _mux
end

---@param opts MdViewOptions
function M.create(opts)
  local bufnr = vim.api.nvim_get_current_buf()

  if active_previews[bufnr] then
    local sp = opts.single_page
    if sp and sp.enable and _mux and _mux.server then
      -- Single-page mode: route to the mux, not the per-preview server
      local mux_url = "http://" .. opts.host .. ":" .. _mux.port
      if #_mux.clients > 0 and not opts.follow_focus then
        -- Hub tab is open: re-push preview_added so the panel is recreated if the
        -- user closed it via the hub close button, then focus it.
        local entry = _mux.registry[bufnr]
        if entry then
          _mux:push("preview_added", { id = bufnr, title = entry.title, label = entry.label })
          _mux:push("focus", { id = bufnr })
        end
        if not opts.silent then
          vim.notify("[md-view] Preview already open in hub at " .. mux_url)
        end
      else
        if not opts.silent then
          vim.notify("[md-view] Reopening hub at " .. mux_url)
        end
        util.open_browser(mux_url, opts.browser)
      end
      return
    end
    local preview = active_previews[bufnr]
    local url = "http://" .. opts.host .. ":" .. preview.port
    if #preview.sse.clients > 0 and not opts.follow_focus then
      -- Tab is open: do not open a new tab. Opening a new tab would trigger the
      -- BroadcastChannel "takeover" and close the existing tab, breaking any
      -- split-tab arrangement in the browser.
      if not opts.silent then
        vim.notify("[md-view] Preview already open at " .. url)
      end
      return
    else
      if not opts.silent then
        vim.notify("[md-view] Reopening preview at " .. url)
      end
      util.open_browser(url, opts.browser)
    end
    return
  end

  local sse_instance = sse.new()
  sse_instance.on_client_added = function(client)
    read_content_async(bufnr, function(content)
      pcall(function()
        client:write("event: content\ndata: " .. vim.json.encode({ content = content }) .. "\n\n")
      end)
    end)
  end

  local theme_css = ""
  if opts.theme.mode == "sync" then
    theme_css = theme.css(opts.theme.highlights)
  end

  local resolved = theme.resolve(opts)

  local ctx = {
    bufnr = bufnr,
    config = vim.tbl_extend("force", opts, {
      theme_css = theme_css,
      palette_css = theme.palette_css(resolved.theme),
      theme = resolved.theme,
      highlight_theme = resolved.highlight_theme,
      mermaid = { theme = resolved.mermaid_theme },
    }),
    sse = sse_instance,
  }

  local srv, port = server.start(opts.host, opts.port, router.new(direct.routes, ctx))

  if not srv then
    return
  end

  local watcher = buffer.watch(bufnr, {
    on_content = function(lines)
      local content = table.concat(lines, "\n")
      sse_instance:push("content", { content = content })
      local h = get_mux()
      if h and h.server then
        h:push("content", { id = bufnr, content = content })
      end
    end,
    on_scroll = function(data)
      sse_instance:push("scroll", data)
      local h = get_mux()
      if h and h.server then
        h:push("scroll", vim.tbl_extend("force", data, { id = bufnr }))
      end
    end,
  }, opts.debounce_ms, opts.scroll.method)

  active_previews[bufnr] = {
    server = srv,
    port = port,
    sse = sse_instance,
    watcher = watcher,
  }

  local sp = opts.single_page
  if sp and sp.enable then
    local h = ensure_mux(opts)
    if h then
      local bufname = vim.api.nvim_buf_get_name(bufnr)
      h:register(bufnr, bufname, sp.tab_label)
      local entry = h.registry[bufnr]
      h:push("preview_added", { id = bufnr, title = entry.title, label = entry.label })
      local hub_pal_css = opts.theme.mode == "sync" and theme.css(opts.theme.highlights)
        or theme.palette_css(resolved.theme)
      h:push("hub_palette", { css = hub_pal_css })
    end
  end

  local url = "http://" .. opts.host .. ":" .. port
  if sp and sp.enable and _mux and _mux.server then
    -- In single_page mode, open hub URL; don't open individual preview URL
    url = "http://" .. opts.host .. ":" .. _mux.port
    -- Only open browser if hub tab is not already connected
    if #_mux.clients > 0 then
      -- Hub tab already open — focus event handled by BufEnter autocmd
      vim.notify("[md-view] Preview added to hub at " .. url)
      return
    else
      vim.notify("[md-view] Hub serving at " .. url)
    end
  else
    vim.notify("[md-view] Serving at " .. url)
  end
  util.open_browser(url, opts.browser)

  local cleanup_group = vim.api.nvim_create_augroup("md_view_cleanup_" .. bufnr, { clear = true })

  if opts.theme.mode == "sync" then
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = cleanup_group,
      callback = function()
        local css = theme.css(opts.theme.highlights)
        sse_instance:push("theme", { css = css })
        local h = get_mux()
        if h and h.server then
          h:push("theme", { id = bufnr, css = css })
          h:push("hub_palette", { css = css })
        end
      end,
    })
  elseif opts.theme.mode == "auto" then
    if sp and sp.enable then
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = cleanup_group,
        callback = function()
          local h = get_mux()
          if h and h.server then
            h:push("hub_palette", { css = theme.palette_css(vim.o.background == "light" and "light" or "dark") })
          end
        end,
      })
    end
  end

  if sp and sp.enable then
    vim.api.nvim_create_autocmd("BufEnter", {
      group = cleanup_group,
      buffer = bufnr,
      callback = function()
        local h = get_mux()
        if h and h.server then
          h:push("focus", { id = bufnr })
        end
      end,
    })
  end

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = cleanup_group,
    buffer = bufnr,
    callback = function()
      M.destroy(bufnr)
    end,
  })

  if not vim.g.md_view_vimleave_registered then
    vim.g.md_view_vimleave_registered = true
    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = vim.api.nvim_create_augroup("md_view_global", { clear = true }),
      callback = function()
        for buf, _ in pairs(active_previews) do
          M.destroy(buf)
        end
      end,
    })
  end
end

---@param bufnr integer|nil
function M.destroy(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local preview = active_previews[bufnr]
  if not preview then
    return
  end

  local config = require("md-view.config")
  local sp = config.options and config.options.single_page
  local hub_active = sp and sp.enable and _mux and _mux.server
  if hub_active then
    -- Push preview_removed BEFORE unregistering
    _mux:push("preview_removed", { id = bufnr })
    _mux:unregister(bufnr)
    -- Stop hub when this is the last preview
    local remaining = 0
    for k, _ in pairs(active_previews) do
      if k ~= bufnr then
        remaining = remaining + 1
      end
    end
    if remaining == 0 then
      local close_by = sp.close_by
      local should_close_page
      if close_by == nil then
        -- Inherit from top-level auto_close
        should_close_page = config.options and config.options.auto_close == true
      else
        -- single_page.close_by = "page" closes the window; "tab" or false keeps it open
        should_close_page = close_by == "page"
      end
      if should_close_page then
        _mux:push("close", {})
      end
      server.stop(_mux.server)
      _mux.server = nil
      _mux.port = nil
      _mux:close_all()
      _mux = nil
    end
    -- Individual `close` event suppressed: hub tab must not close when one preview ends
  elseif config.options and config.options.auto_close then
    preview.sse:push("close", {})
  end
  preview.sse:close_all()
  preview.watcher.stop()
  server.stop(preview.server)

  pcall(vim.api.nvim_del_augroup_by_name, "md_view_cleanup_" .. bufnr)

  active_previews[bufnr] = nil
end

---@param bufnr integer
---@return MdViewPreview|nil
function M.get(bufnr)
  return active_previews[bufnr]
end

---@return table<integer, MdViewPreview>
function M.get_active()
  return active_previews
end

---@return MdViewHub|nil
function M.get_mux()
  return _mux
end

return M
