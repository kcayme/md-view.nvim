local util = require("md-view.util")

vim.api.nvim_create_user_command("MdView", function(cmd_opts)
  util.safe_call("MdView", function()
    local opts = { follow_focus = true }
    if cmd_opts.args ~= "" then
      opts.browser = cmd_opts.args
    end
    require("md-view").open(opts)
  end)
end, { desc = "Open markdown preview in browser", nargs = "?" })

vim.api.nvim_create_user_command("MdViewStop", function()
  util.safe_call("MdViewStop", function()
    require("md-view").stop()
  end)
end, { desc = "Stop markdown preview" })

vim.api.nvim_create_user_command("MdViewToggle", function()
  util.safe_call("MdViewToggle", function()
    require("md-view").toggle()
  end)
end, { desc = "Toggle markdown preview" })

vim.api.nvim_create_user_command("MdViewList", function()
  util.safe_call("MdViewList", function()
    require("md-view").list()
  end)
end, { desc = "List active markdown previews" })

vim.api.nvim_create_user_command("MdViewAutoOpen", function()
  util.safe_call("MdViewAutoOpen", function()
    require("md-view").toggle_auto_open()
  end)
end, { desc = "Toggle md-view auto-open preview on buffer enter" })

vim.api.nvim_create_user_command("MdViewTheme", function(cmd_opts)
  util.safe_call("MdViewTheme", function()
    require("md-view").set_theme(cmd_opts.args)
  end)
end, { desc = "Switch live preview theme (dark/light/auto/sync); no arg cycles", nargs = "?" })

vim.api.nvim_create_user_command("MdViewFetchAssets", function(cmd_opts)
  util.safe_call("MdViewFetchAssets", function()
    local opts = {}
    local theme = cmd_opts.args:match("highlight_theme=(%S+)")
    if theme then
      opts.highlight_theme = theme
    end
    require("md-view.vendor").fetch(opts)
  end)
end, { desc = "Re-fetch vendor assets for offline use", nargs = "?" })
