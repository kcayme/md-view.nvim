local M = {}

M.defaults = {
  port = 0,
  host = "127.0.0.1",
  browser = nil,
  debounce_ms = 300,
  css = nil,
  highlight_theme = nil,
  auto_close = true,
  scroll_sync = "percentage",
  theme = "auto",
  theme_sync = false,
  highlights = {},
  mermaid = {
    theme = nil,
  },
}

M.options = nil

local LOOPBACK = { ["127.0.0.1"] = true, ["::1"] = true, ["localhost"] = true }

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
  if not LOOPBACK[M.options.host] then
    vim.notify(
      "[md-view] WARNING: host '" .. M.options.host .. "' is not loopback — preview server will be exposed to the network",
      vim.log.levels.WARN
    )
  end
end

return M
