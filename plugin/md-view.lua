vim.api.nvim_create_user_command("MdView", function()
  require("md-view").open()
end, { desc = "Open markdown preview in browser" })

vim.api.nvim_create_user_command("MdViewStop", function()
  require("md-view").stop()
end, { desc = "Stop markdown preview" })

vim.api.nvim_create_user_command("MdViewToggle", function()
  require("md-view").toggle()
end, { desc = "Toggle markdown preview" })

vim.api.nvim_create_user_command("MdViewList", function()
  require("md-view").list()
end, { desc = "List active markdown previews" })

vim.api.nvim_create_user_command("MdViewAutoOpen", function()
  require("md-view").toggle_auto_open()
end, { desc = "Toggle md-view auto-open preview on buffer enter" })

vim.api.nvim_create_user_command("MdViewFetchAssets", function(cmd_opts)
  local opts = {}
  local theme = cmd_opts.args:match("highlight_theme=(%S+)")
  if theme then
    opts.highlight_theme = theme
  end
  require("md-view.vendor").fetch(opts)
end, { desc = "Download vendor assets for offline use", nargs = "?" })
