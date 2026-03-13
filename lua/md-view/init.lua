local M = {}

local config = require("md-view.config")
local server = require("md-view.server")
local router = require("md-view.router")
local sse = require("md-view.sse")
local buffer = require("md-view.buffer")
local util = require("md-view.util")

local active_previews = {}

function M.setup(opts)
  config.setup(opts)
end

function M.open()
  if not config.options then
    config.setup({})
  end

  local opts = config.options
  local bufnr = vim.api.nvim_get_current_buf()

  if active_previews[bufnr] then
    vim.notify("[md-view] Preview already active for this buffer", vim.log.levels.WARN)
    return
  end

  local sse_instance = sse.new()

  local ctx = {
    bufnr = bufnr,
    config = opts,
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
    on_scroll = function(line)
      sse_instance:push("scroll", { line = line })
    end,
  }, opts.debounce_ms)

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

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = cleanup_group,
    buffer = bufnr,
    callback = function()
      M.stop(bufnr)
    end,
  })

  if not vim.g.md_view_vimleave_registered then
    vim.g.md_view_vimleave_registered = true
    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = vim.api.nvim_create_augroup("md_view_global", { clear = true }),
      callback = function()
        for buf, _ in pairs(active_previews) do
          M.stop(buf)
        end
      end,
    })
  end
end

function M.stop(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local preview = active_previews[bufnr]
  if not preview then
    return
  end

  preview.sse:close_all()
  preview.watcher.stop()
  server.stop(preview.server)

  pcall(vim.api.nvim_del_augroup_by_name, "md_view_cleanup_" .. bufnr)

  active_previews[bufnr] = nil
end

function M.toggle()
  local bufnr = vim.api.nvim_get_current_buf()
  if active_previews[bufnr] then
    M.stop(bufnr)
  else
    M.open()
  end
end

return M
