local M = {}

local util = require("md-view.util")

local function default_format(item, max_name_len, cfg)
  local url = "http://" .. (cfg.host or "127.0.0.1") .. ":" .. item.port

  return string.format("%-" .. max_name_len .. "s  %s", item.name, url)
end

M.open = function()
  local previews = require("md-view").get_active_previews()
  local preview_mod = require("md-view.preview")
  local hub = preview_mod.get_mux()
  local config = require("md-view.config").options or {}
  local items = {}
  local picker_config = config.picker or {}
  local max_name_len = 0

  for bufnr, preview in pairs(previews) do
    local item_name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
    local port = preview.port or (hub and hub.port)

    items[#items + 1] = {
      bufnr = bufnr,
      port = port,
      name = item_name,
    }

    if #item_name > max_name_len then
      max_name_len = #item_name
    end
  end

  if #items == 0 then
    util.notify(config, "[md-view] No active previews", vim.log.levels.INFO)
    return
  end

  local select_opts = {
    prompt = picker_config.prompt or "Markdown Previews",
    format_item = picker_config.format_item or function(item)
      return default_format(item, max_name_len, config)
    end,
    kind = (picker_config.kind and picker_config.kind),
  }

  vim.ui.select(items, select_opts, function(item)
    if not item then
      return
    end

    vim.api.nvim_set_current_buf(item.bufnr)

    local url = "http://" .. (config.host or "127.0.0.1") .. ":" .. item.port
    local preview = previews[item.bufnr]
    local has_clients = (preview and preview.sse and #preview.sse.clients > 0) or (hub and #hub.clients > 0)

    if has_clients then
      util.notify(config, "[md-view] Preview already open at " .. url, vim.log.levels.INFO)
    else
      util.open_browser(url, config.browser)
    end
  end)
end

return M
