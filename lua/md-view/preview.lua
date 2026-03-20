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

---@type table<integer, MdViewPreview>
local active_previews = {}
---@type MdViewHub|nil
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
local function init_hub(opts)
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
    local srv, port = server.start(opts.host, opts.port, handle)

    if not srv then
      _mux = nil
      return nil
    end

    _mux.server = srv
    _mux.port = port

    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = vim.api.nvim_create_augroup("md_view_mux_global", { clear = true }),
      callback = function()
        if _mux then
          local cfg = require("md-view.config")
          local sp = cfg.options and cfg.options.single_page
          local close_by = sp and sp.close_by
          local should_close = close_by == "page"
            or (close_by == nil and cfg.options and cfg.options.auto_close == true)

          -- Mirror M.destroy: push preview_removed for each registered preview
          for bufnr, _ in pairs(_mux.registry) do
            _mux:push("preview_removed", { id = bufnr })
          end

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
  return _mux
end

-- Handle an open() call when a preview already exists for bufnr.
local function handle_preview(bufnr, opts, sp)
  local preview = active_previews[bufnr]

  if sp and sp.enable and _mux and _mux.server then
    local url = "http://" .. opts.host .. ":" .. _mux.port

    if #_mux.clients > 0 then
      if opts.follow_focus then
        local entry = _mux.registry[bufnr]

        if entry then
          _mux:push("preview_added", { id = bufnr, title = entry.title, label = entry.label })
          _mux:push("focus", { id = bufnr })
        end

        util.notify(opts, "[md-view] Focused preview in hub at " .. url)
        return
      end

      util.notify(opts, "[md-view] Preview already open in hub at " .. url)

      return
    end

    util.notify(opts, "[md-view] Reopening hub at " .. url)
    util.open_browser(url, opts.browser)

    return
  end

  local url = "http://" .. opts.host .. ":" .. preview.port

  if #preview.sse.clients > 0 and not opts.follow_focus then
    util.notify(opts, "[md-view] Preview already open at " .. url)

    return
  end

  util.notify(opts, "[md-view] Reopening preview at " .. url)
  util.open_browser(url, opts.browser)
end

-- Create and wire up an SSE instance for bufnr.
local function build_sse(bufnr)
  local sse_instance = sse.new()

  sse_instance.on_client_added = function(client)
    read_content_async(bufnr, function(content)
      pcall(function()
        client:write("event: content\ndata: " .. vim.json.encode({ content = content }) .. "\n\n")
      end)
    end)
  end

  return sse_instance
end

-- Resolve theme and build the render context passed to the direct router.
-- Returns ctx, resolved.
local function build_render_ctx(bufnr, opts, sse_instance)
  local theme_css = (opts.theme.mode == "sync" and theme.css(opts.theme.highlights)) or ""
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

  return ctx, resolved
end

-- Start the per-preview TCP server. Returns srv, port or nil on failure.
local function start_preview_server(opts, ctx)
  return server.start(opts.host, opts.port, router.new(direct.routes, ctx))
end

-- Start the buffer watcher for bufnr, forwarding events to SSE and the hub.
local function start_buffer_watcher(bufnr, opts, sse_instance)
  return buffer.watch(bufnr, {
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
end

-- Ensure the hub is running and register this preview with it.
local function register_with_hub(bufnr, opts, resolved)
  local hub = init_hub(opts)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local hub_pal_css = opts.theme.mode == "sync" and theme.css(opts.theme.highlights)
    or theme.palette_css(resolved.theme)

  if not hub then
    return
  end

  hub:register(bufnr, bufname, opts.single_page.tab_label)

  local entry = hub.registry[bufnr]

  hub:push("preview_added", { id = bufnr, title = entry.title, label = entry.label })
  hub:push("hub_palette", { css = hub_pal_css })

  -- on_client_added only fires for new SSE connections; if the hub already has
  -- connected clients, push initial content directly so the new panel is not blank.
  if #hub.clients > 0 then
    read_content_async(bufnr, function(content)
      hub:push("content", { id = bufnr, content = content })
    end)
  end
end

-- Pick the URL to open, notify the user, and launch the browser.
local function open_browser_for_preview(opts, port)
  local url = "http://" .. opts.host .. ":" .. port

  if opts.single_page and opts.single_page.enable and _mux and _mux.server then
    url = "http://" .. opts.host .. ":" .. _mux.port

    if #_mux.clients > 0 then
      util.notify(opts, "[md-view] Preview added to hub at " .. url)
      return
    end
  end

  util.notify(opts, "[md-view] Serving at " .. url)
  util.open_browser(url, opts.browser)
end

-- Register ColorScheme, BufEnter, BufDelete, and VimLeavePre autocmds for bufnr.
local function register_autocmds(bufnr, opts, sse_instance)
  local sp = opts.single_page
  local cleanup_group = vim.api.nvim_create_augroup("md_view_cleanup_" .. bufnr, { clear = true })
  local on_colorscheme_cb = nil

  if opts.theme.mode == "sync" then
    on_colorscheme_cb = function()
      local css = theme.css(opts.theme.highlights)
      local h = get_mux()

      sse_instance:push("theme", { css = css })

      if h and h.server then
        h:push("theme", { id = bufnr, css = css })
        h:push("hub_palette", { css = css })
      end
    end
  elseif opts.theme.mode == "auto" and sp and sp.enable then
    on_colorscheme_cb = function()
      local h = get_mux()

      if h and h.server then
        h:push("hub_palette", {
          css = theme.palette_css(vim.o.background == "light" and "light" or "dark"),
        })
      end
    end
  end

  if on_colorscheme_cb then
    -- needs to be cleaned up when preview is destroyed
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = cleanup_group,
      callback = on_colorscheme_cb,
    })
  end

  if sp and sp.enable and opts.follow_focus then
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
end

local function register_global_autocmds()
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("md_view_global", { clear = true }),
    callback = function()
      for buf, _ in pairs(active_previews) do
        M.destroy(buf)
      end
    end,
  })
end

---@param opts MdViewOptions
M.create = function(opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local sp = opts.single_page

  -- handle existing preview
  if active_previews[bufnr] then
    handle_preview(bufnr, opts, sp)
    return
  end

  local sse_instance = build_sse(bufnr)
  local ctx, resolved = build_render_ctx(bufnr, opts, sse_instance)
  local watcher = start_buffer_watcher(bufnr, opts, sse_instance)
  local srv, port = start_preview_server(opts, ctx)

  if not srv then
    return
  end

  active_previews[bufnr] = {
    server = srv,
    port = port,
    sse = sse_instance,
    watcher = watcher,
  }

  if sp and sp.enable then
    register_with_hub(bufnr, opts, resolved)
  end

  open_browser_for_preview(opts, port)
  register_autocmds(bufnr, opts, sse_instance)
  register_global_autocmds()
end

---@param buffer_id integer|nil
M.destroy = function(buffer_id)
  buffer_id = buffer_id or vim.api.nvim_get_current_buf()

  local preview = active_previews[buffer_id]
  local config = require("md-view.config")
  local sp = config.options and config.options.single_page
  local hub_active = sp and sp.enable and _mux and _mux.server

  if not preview then
    return
  end

  active_previews[buffer_id] = nil

  if hub_active then
    _mux:push("preview_removed", { id = buffer_id })
    _mux:unregister(buffer_id)

    if util.table_len(active_previews) == 0 then
      if sp.close_by == "page" or (sp.close_by == nil and config.options and config.options.auto_close == true) then
        _mux:push("close", {})
      end

      server.stop(_mux.server)
      _mux.server = nil
      _mux.port = nil
      _mux:close_all()
      _mux = nil
    end
  elseif config.options and config.options.auto_close then
    preview.sse:push("close", {})
  end

  preview.sse:close_all()
  preview.watcher.stop()
  server.stop(preview.server)

  pcall(vim.api.nvim_del_augroup_by_name, "md_view_cleanup_" .. buffer_id)
end

---@param bufnr integer
---@return MdViewPreview|nil
M.get_by_buffer = function(bufnr)
  return active_previews[bufnr]
end

---@return table<integer, MdViewPreview>
M.get_active_previews = function()
  return active_previews
end

---@return MdViewHub|nil
M.get_mux = function()
  return _mux
end

return M
