vim.api.nvim_create_user_command("MdView", function()
  require("md-view").open()
end, { desc = "Open markdown preview in browser" })

vim.api.nvim_create_user_command("MdViewStop", function()
  require("md-view").stop()
end, { desc = "Stop markdown preview" })

vim.api.nvim_create_user_command("MdViewToggle", function()
  require("md-view").toggle()
end, { desc = "Toggle markdown preview" })
