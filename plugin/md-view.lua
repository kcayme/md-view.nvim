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

vim.api.nvim_create_user_command("MdViewClose", function(cmd_opts)
  util.safe_call("MdViewClose", function()
    if cmd_opts.args == "all" then
      require("md-view").close_all()
    else
      require("md-view").close()
    end
  end)
end, { desc = "Close markdown preview panel(s) without stopping the server", nargs = "?" })

vim.api.nvim_create_user_command("MdViewRestart", function()
  util.safe_call("MdViewRestart", function()
    require("md-view").restart()
  end)
end, { desc = "Restart all active markdown preview servers" })

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
    local theme_arg = cmd_opts.args:match("highlight_theme=(%S+)")

    if theme_arg then
      -- Explicit single theme override: fetch just that theme
      opts.highlight_themes = { theme_arg }
    else
      -- Auto-resolve both light and dark themes from config
      local config = require("md-view.config")
      local theme_mod = require("md-view.theme")
      local copts = config.options or {}
      local theme_tbl = copts.theme or {}
      local light_theme = theme_mod.resolve(
        vim.tbl_extend("force", copts, { theme = vim.tbl_extend("force", theme_tbl, { mode = "light" }) })
      ).highlight_theme
      local dark_theme = theme_mod.resolve(
        vim.tbl_extend("force", copts, { theme = vim.tbl_extend("force", theme_tbl, { mode = "dark" }) })
      ).highlight_theme
      local themes = { light_theme }

      if dark_theme ~= light_theme then
        themes[#themes + 1] = dark_theme
      end

      opts.highlight_themes = themes
    end

    require("md-view.vendor").fetch(opts)
  end)
end, { desc = "Re-fetch vendor assets for offline use", nargs = "?" })
