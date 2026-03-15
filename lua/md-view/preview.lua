local M = {}

local server = require("md-view.server.tcp")
local router = require("md-view.server.router")
local sse = require("md-view.server.sse")
local buffer = require("md-view.buffer")
local theme = require("md-view.theme")
local util = require("md-view.util")

local active_previews = {}

function M.create(opts)
  local bufnr = vim.api.nvim_get_current_buf()

  if active_previews[bufnr] then
    local preview = active_previews[bufnr]
    local url = "http://" .. opts.host .. ":" .. preview.port
    vim.notify("[md-view] Reopening preview at " .. url)
    util.open_browser(url, opts.browser)
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

  local srv, port = server.start(opts.host, opts.port, function(client, data)
    router.handle(client, data, ctx)
  end)

  if not srv then
    return
  end

  local watcher = buffer.watch(bufnr, {
    on_content = function(lines)
      local content = table.concat(lines, "\n")
      sse_instance:push("content", { content = content })
    end,
    on_scroll = function(data)
      sse_instance:push("scroll", data)
    end,
  }, opts.debounce_ms, opts.scroll.method)

  active_previews[bufnr] = {
    server = srv,
    port = port,
    sse = sse_instance,
    watcher = watcher,
  }

  local url = "http://" .. opts.host .. ":" .. port
  vim.notify("[md-view] Serving at " .. url)
  util.open_browser(url, opts.browser)

  local cleanup_group = vim.api.nvim_create_augroup("md_view_cleanup_" .. bufnr, { clear = true })

  if opts.theme.mode == "sync" then
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = cleanup_group,
      callback = function()
        sse_instance:push("theme", { css = theme.css(opts.theme.highlights) })
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

function M.destroy(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local preview = active_previews[bufnr]
  if not preview then
    return
  end

  local config = require("md-view.config")
  if config.options.auto_close then
    preview.sse:push("close", {})
  end
  preview.sse:close_all()
  preview.watcher.stop()
  server.stop(preview.server)

  pcall(vim.api.nvim_del_augroup_by_name, "md_view_cleanup_" .. bufnr)

  active_previews[bufnr] = nil
end

function M.get(bufnr)
  return active_previews[bufnr]
end

function M.get_active()
  return active_previews
end

return M
