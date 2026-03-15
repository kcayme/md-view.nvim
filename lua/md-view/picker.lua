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

  local cfg = require("md-view.config").options or {}
  local pcfg = cfg.picker or {}

  local function default_format(item)
    local url = "http://" .. (cfg.host or "127.0.0.1") .. ":" .. item.port
    return item.name .. "  " .. url
  end

  local select_opts = {
    prompt = pcfg.prompt or "Markdown Previews",
    format_item = pcfg.format_item or default_format,
  }
  if pcfg.kind then
    select_opts.kind = pcfg.kind
  end

  vim.ui.select(items, select_opts, function(item)
    if not item then
      return
    end
    vim.api.nvim_set_current_buf(item.bufnr)
    local url = "http://" .. (cfg.host or "127.0.0.1") .. ":" .. item.port
    require("md-view.util").open_browser(url, cfg.browser)
  end)
end

return M
