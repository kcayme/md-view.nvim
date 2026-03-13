local M = {}

local config = require("md-view.config")
local preview = require("md-view.preview")

function M.setup(opts)
  config.setup(opts)
end

function M.open()
  if not config.options then
    config.setup({})
  end
  preview.create(config.options)
end

function M.stop(bufnr)
  preview.destroy(bufnr)
end

function M.toggle()
  local bufnr = vim.api.nvim_get_current_buf()
  if preview.get(bufnr) then
    M.stop(bufnr)
  else
    M.open()
  end
end

function M.get_active_previews()
  return preview.get_active()
end

function M.list()
  require("md-view.picker").open()
end

return M
