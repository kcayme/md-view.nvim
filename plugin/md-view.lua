vim.api.nvim_create_user_command("MdView", function(cmd_opts)
  local opts = { follow_focus = true }
  if cmd_opts.args ~= "" then
    opts.browser = cmd_opts.args
  end
  require("md-view").open(opts)
end, { desc = "Open markdown preview in browser", nargs = "?" })

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

vim.api.nvim_create_user_command("MdViewTheme", function(cmd_opts)
  require("md-view").set_theme(cmd_opts.args)
end, { desc = "Switch live preview theme (dark/light/auto/sync); no arg cycles", nargs = "?" })

vim.api.nvim_create_user_command("MdViewFetchAssets", function(cmd_opts)
  local opts = {}
  local theme = cmd_opts.args:match("highlight_theme=(%S+)")
  if theme then
    opts.highlight_theme = theme
  end
  require("md-view.vendor").fetch(opts)
end, { desc = "Re-fetch vendor assets for offline use", nargs = "?" })
