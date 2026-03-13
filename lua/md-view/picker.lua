local M = {}

function M.open()
  local previews = require("md-view").get_active_previews()
  local items = {}

  for bufnr, preview in pairs(previews) do
    items[#items + 1] = {
      bufnr = bufnr,
      port = preview.port,
      name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t"),
    }
  end

  if #items == 0 then
    vim.notify("[md-view] No active previews", vim.log.levels.INFO)
    return
  end

  vim.ui.select(items, {
    prompt = "Markdown Previews",
    format_item = function(item)
      local opts = require("md-view.config").options or {}
      local url = "http://" .. (opts.host or "127.0.0.1") .. ":" .. item.port
      return item.name .. "  " .. url
    end,
  }, function(item)
    if not item then
      return
    end
    vim.api.nvim_set_current_buf(item.bufnr)
    local opts = require("md-view.config").options or {}
    local url = "http://" .. (opts.host or "127.0.0.1") .. ":" .. item.port
    require("md-view.util").open_browser(url, opts.browser)
  end)
end

return M
