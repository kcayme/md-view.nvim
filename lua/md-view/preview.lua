local M = {}

---@class MdViewPreview
---@field server userdata TCP server handle
---@field port integer
---@field sse MdViewSse
---@field watcher table

local server = require("md-view.server.tcp")
local router = require("md-view.server.router")
local direct = require("md-view.server.handlers.direct")
local sse = require("md-view.server.sse")
local buffer = require("md-view.buffer")
local theme = require("md-view.theme")
local util = require("md-view.util")
local mux_mod = require("md-view.server.mux")

local active_previews = {}
local _mux = nil

local function get_mux()
  return _mux
end

-- Start hub if not already running. Returns hub instance or nil on failure.
local function ensure_mux(opts)
  if not _mux then
    _mux = mux_mod.new()
  end
  if not _mux.server then
    local ok = _mux:start(opts.host, opts.port)
    if not ok then
      -- tcp.lua already called vim.notify on bind failure
      _mux = nil
      return nil
    end
    local hub_url = "http://" .. opts.host .. ":" .. _mux.port
    vim.notify("[md-view] Hub serving at " .. hub_url)
    -- VimLeavePre safety net (registered once)
    if not vim.g.md_view_mux_vimleave_registered then
      vim.g.md_view_mux_vimleave_registered = true
      vim.api.nvim_create_autocmd("VimLeavePre", {
        group = vim.api.nvim_create_augroup("md_view_mux_global", { clear = true }),
        callback = function()
          if _mux then
            _mux:stop()
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
    end
  end
  vim.notify("[md-view] Serving at " .. url)
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
          h:push("hub_palette", { css = theme.palette_css(vim.o.background == "light" and "light" or "dark") })
        end
      end,
    })
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
      _mux:stop()
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

---@return MdViewMux|nil
function M.get_mux()
  return _mux
end

return M
