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
  mermaid = {
    theme = nil,
  },
}

M.options = nil

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

return M
