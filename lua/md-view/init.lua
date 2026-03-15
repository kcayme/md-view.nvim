local M = {}

local config = require("md-view.config")
local preview = require("md-view.preview")

local function register_auto_open_augroup()
  local group = vim.api.nvim_create_augroup("md_view_auto_open", { clear = true })
  vim.api.nvim_create_autocmd(config.options.auto_open.events, {
    group = group,
    pattern = "*",
    callback = function()
      M.open({ silent = true })
    end,
  })
end

function M.setup(opts)
  config.setup(opts)
  pcall(vim.api.nvim_del_augroup_by_name, "md_view_auto_open")
  if config.options.auto_open.enable then
    register_auto_open_augroup()
  end
end

function M.open(opts)
  opts = opts or {}
  if not config.options then
    config.setup({})
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local ft = vim.bo[bufnr].filetype
  local filetypes = config.options.filetypes
  if filetypes and #filetypes > 0 then
    local allowed = false
    for _, v in ipairs(filetypes) do
      if v == ft then
        allowed = true
        break
      end
    end
    if not allowed then
      if not opts.silent then
        vim.notify("[md-view] filetype '" .. ft .. "' is not in filetypes list", vim.log.levels.WARN)
      end
      return
    end
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

function M.toggle_auto_open()
  if not config.options then
    config.setup({})
  end
  local enabled = not config.options.auto_open.enable
  config.options.auto_open.enable = enabled
  pcall(vim.api.nvim_del_augroup_by_name, "md_view_auto_open")
  if enabled then
    vim.notify("[md-view] auto-open enabled")
    register_auto_open_augroup()
  else
    vim.notify("[md-view] auto-open disabled")
  end
end

return M
