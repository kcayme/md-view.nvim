local config = require("md-view.config")

describe("config", function()
  after_each(function()
    config.options = nil
  end)

  describe("setup", function()
    it("sets options with defaults when called with empty table", function()
      config.setup({})
      assert.is_not_nil(config.options)
      assert.are.equal("127.0.0.1", config.options.host)
      assert.are.equal(0, config.options.port)
      assert.are.equal(300, config.options.debounce_ms)
      assert.are.equal(true, config.options.auto_close)
      assert.are.equal("percentage", config.options.scroll.method)
      assert.is_nil(config.options.scroll_sync)
      assert.are.equal("auto", config.options.theme.mode)
      assert.is_nil(config.options.theme.syntax)
      assert.are.same({}, config.options.theme.highlights)
      assert.is_nil(config.options.theme_sync)
      assert.is_nil(config.options.browser)
      assert.is_nil(config.options.css)
      assert.is_nil(config.options.highlight_theme)
      assert.is_nil(config.options.mermaid)
    end)

    it("sets options with defaults when called with nil", function()
      config.setup()
      assert.is_not_nil(config.options)
      assert.are.equal("127.0.0.1", config.options.host)
    end)

    it("merges user options over defaults", function()
      config.setup({ port = 8080, browser = "firefox", theme = { mode = "dark" } })
      assert.are.equal(8080, config.options.port)
      assert.are.equal("firefox", config.options.browser)
      assert.are.equal("dark", config.options.theme.mode)
      -- defaults preserved
      assert.are.equal("127.0.0.1", config.options.host)
      assert.are.equal(300, config.options.debounce_ms)
    end)

    it("deep merges nested options", function()
      config.setup({ notations = { mermaid = { theme = "forest" } } })
      assert.are.equal("forest", config.options.notations.mermaid.theme)
    end)

    it("does not mutate defaults", function()
      config.setup({ port = 9999 })
      assert.are.equal(0, config.defaults.port)
    end)

    it("warns on non-loopback host", function()
      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.WARN and msg:find("not loopback") then
          warned = true
        end
      end
      config.setup({ host = "0.0.0.0" })
      vim.notify = orig_notify
      assert.is_true(warned)
    end)

    it("does not warn on 127.0.0.1", function()
      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(_, level)
        if level == vim.log.levels.WARN then
          warned = true
        end
      end
      config.setup({ host = "127.0.0.1" })
      vim.notify = orig_notify
      assert.is_false(warned)
    end)

    it("does not warn on ::1", function()
      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(_, level)
        if level == vim.log.levels.WARN then
          warned = true
        end
      end
      config.setup({ host = "::1" })
      vim.notify = orig_notify
      assert.is_false(warned)
    end)

    it("does not warn on localhost", function()
      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(_, level)
        if level == vim.log.levels.WARN then
          warned = true
        end
      end
      config.setup({ host = "localhost" })
      vim.notify = orig_notify
      assert.is_false(warned)
    end)

    it("includes notations defaults", function()
      config.setup({})
      assert.is_true(config.options.notations.mermaid.enable)
      assert.is_nil(config.options.notations.mermaid.theme)
      assert.is_true(config.options.notations.katex.enable)
      assert.is_true(config.options.notations.graphviz.enable)
      assert.is_true(config.options.notations.wavedrom.enable)
      assert.is_true(config.options.notations.nomnoml.enable)
      assert.is_true(config.options.notations.abc.enable)
      assert.is_true(config.options.notations.vegalite.enable)
    end)

    it("allows disabling a notation", function()
      config.setup({ notations = { katex = { enable = false } } })
      assert.is_false(config.options.notations.katex.enable)
      assert.is_true(config.options.notations.graphviz.enable)
    end)

    it("maps deprecated theme_sync=true to theme.mode='sync' and warns", function()
      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.WARN and msg:find("theme_sync") then
          warned = true
        end
      end
      config.setup({ theme_sync = true })
      vim.notify = orig_notify
      assert.is_true(warned)
      assert.are.equal("sync", config.options.theme.mode)
    end)

    it("maps deprecated scroll_sync='percentage' to scroll.method='percentage' and warns", function()
      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.WARN and msg:find("scroll_sync") then
          warned = true
        end
      end
      config.setup({ scroll_sync = "percentage" })
      vim.notify = orig_notify
      assert.is_true(warned)
      assert.are.equal("percentage", config.options.scroll.method)
      assert.is_nil(config.options.scroll_sync)
    end)

    it("maps deprecated scroll_sync (non-percentage) to scroll.method='cursor' and warns", function()
      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.WARN and msg:find("scroll_sync") then
          warned = true
        end
      end
      config.setup({ scroll_sync = "line" })
      vim.notify = orig_notify
      assert.is_true(warned)
      assert.are.equal("cursor", config.options.scroll.method)
      assert.is_nil(config.options.scroll_sync)
    end)

    it("accepts scroll.method directly without deprecation warning", function()
      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(_, level)
        if level == vim.log.levels.WARN then
          warned = true
        end
      end
      config.setup({ scroll = { method = "cursor" } })
      vim.notify = orig_notify
      assert.is_false(warned)
      assert.are.equal("cursor", config.options.scroll.method)
    end)

    it("explicit scroll.method wins over deprecated scroll_sync and warns", function()
      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.WARN and msg:find("scroll_sync") then
          warned = true
        end
      end
      config.setup({ scroll_sync = "percentage", scroll = { method = "cursor" } })
      vim.notify = orig_notify
      assert.is_true(warned)
      assert.are.equal("cursor", config.options.scroll.method)
    end)

    it("remaps scroll_sync when scroll table exists but has no method key", function()
      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.WARN and msg:find("scroll_sync") then
          warned = true
        end
      end
      config.setup({ scroll_sync = "line", scroll = { other_key = true } })
      vim.notify = orig_notify
      assert.is_true(warned)
      assert.are.equal("cursor", config.options.scroll.method)
    end)

    it("maps deprecated theme as string to theme.mode and warns", function()
      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.WARN and msg:find("`theme` as a string") then
          warned = true
        end
      end
      config.setup({ theme = "dark" })
      vim.notify = orig_notify
      assert.is_true(warned)
      assert.are.equal("dark", config.options.theme.mode)
      assert.is_nil(config.options.highlight_theme)
      assert.is_nil(config.options.highlights)
    end)

    it("maps deprecated highlight_theme to theme.syntax and warns", function()
      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.WARN and msg:find("`highlight_theme`") then
          warned = true
        end
      end
      config.setup({ highlight_theme = "monokai" })
      vim.notify = orig_notify
      assert.is_true(warned)
      assert.are.equal("monokai", config.options.theme.syntax)
      assert.is_nil(config.options.highlight_theme)
    end)

    it("maps deprecated highlights to theme.highlights and warns", function()
      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.WARN and msg:find("`highlights`") then
          warned = true
        end
      end
      config.setup({ highlights = { heading = "MyGroup" } })
      vim.notify = orig_notify
      assert.is_true(warned)
      assert.are.same({ heading = "MyGroup" }, config.options.theme.highlights)
      assert.is_nil(config.options.highlights)
    end)

    it("theme = { mode = 'sync' } does not warn, sets theme.mode", function()
      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(_, level)
        if level == vim.log.levels.WARN then
          warned = true
        end
      end
      config.setup({ theme = { mode = "sync" } })
      vim.notify = orig_notify
      assert.is_false(warned)
      assert.are.equal("sync", config.options.theme.mode)
    end)

    it("explicit theme.syntax wins over deprecated highlight_theme", function()
      local orig_notify = vim.notify
      vim.notify = function() end
      config.setup({ theme = { mode = "dark", syntax = "vs2015" }, highlight_theme = "monokai" })
      vim.notify = orig_notify
      assert.are.equal("vs2015", config.options.theme.syntax)
    end)

    it("explicit theme.highlights wins over deprecated highlights", function()
      local orig_notify = vim.notify
      vim.notify = function() end
      config.setup({
        theme = { mode = "sync", highlights = { heading = "ExplicitGroup" } },
        highlights = { heading = "OldGroup" },
      })
      vim.notify = orig_notify
      assert.are.same({ heading = "ExplicitGroup" }, config.options.theme.highlights)
    end)

    it("theme = { mode = 'sync', highlights = {...} } deep-merges correctly with defaults", function()
      config.setup({ theme = { mode = "sync", highlights = { heading = "@markup.heading" } } })
      assert.are.equal("sync", config.options.theme.mode)
      assert.are.same({ heading = "@markup.heading" }, config.options.theme.highlights)
      assert.is_nil(config.options.theme.syntax)
    end)

    it("filetypes defaults to { 'markdown' }", function()
      config.setup({})
      assert.are.same({ "markdown" }, config.options.filetypes)
    end)

    it("filetypes = {} overrides the default (post-merge override)", function()
      config.setup({ filetypes = {} })
      assert.are.same({}, config.options.filetypes)
    end)

    it("auto_open.enable defaults to false", function()
      config.setup({})
      assert.is_false(config.options.auto_open.enable)
    end)

    it("auto_open.events defaults to { 'BufWinEnter' }", function()
      config.setup({})
      assert.are.same({ "BufWinEnter" }, config.options.auto_open.events)
    end)

    it("auto_open.events user array overrides default", function()
      config.setup({ auto_open = { events = { "BufEnter", "WinEnter" } } })
      assert.are.same({ "BufEnter", "WinEnter" }, config.options.auto_open.events)
    end)

    it("auto_open.events = {} overrides the default", function()
      config.setup({ auto_open = { events = {} } })
      assert.are.same({}, config.options.auto_open.events)
    end)

    it("picker.prompt defaults to 'Markdown Previews'", function()
      config.setup({})
      assert.are.equal("Markdown Previews", config.options.picker.prompt)
    end)

    it("picker.format_item defaults to nil", function()
      config.setup({})
      assert.is_nil(config.options.picker.format_item)
    end)

    it("picker.kind defaults to nil", function()
      config.setup({})
      assert.is_nil(config.options.picker.kind)
    end)

    it("picker user-supplied values are preserved after merge", function()
      local custom_fmt = function(item)
        return item.name
      end
      config.setup({ picker = { prompt = "My Previews", format_item = custom_fmt, kind = "mdview" } })
      assert.are.equal("My Previews", config.options.picker.prompt)
      assert.are.equal(custom_fmt, config.options.picker.format_item)
      assert.are.equal("mdview", config.options.picker.kind)
    end)

    it("has single_page defaults", function()
      config.setup({})
      local sp = config.options.single_page
      assert.is_not_nil(sp)
      assert.is_false(sp.enable)
      assert.are.equal(4999, sp.port)
      assert.are.equal("parent", sp.tab_label)
    end)

    it("merges single_page user options over defaults", function()
      config.setup({ single_page = { enable = true, port = 5000 } })
      local sp = config.options.single_page
      assert.is_true(sp.enable)
      assert.are.equal(5000, sp.port)
      assert.are.equal("parent", sp.tab_label)
    end)

    it("accepts a function as single_page.tab_label", function()
      local fn = function(ctx)
        return ctx.filename
      end
      config.setup({ single_page = { tab_label = fn } })
      assert.are.equal(fn, config.options.single_page.tab_label)
    end)
  end)
end)
