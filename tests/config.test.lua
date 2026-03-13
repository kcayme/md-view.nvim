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
      assert.are.equal("percentage", config.options.scroll_sync)
      assert.are.equal("auto", config.options.theme)
      assert.are.equal(false, config.options.theme_sync)
      assert.is_nil(config.options.browser)
      assert.is_nil(config.options.css)
      assert.is_nil(config.options.highlight_theme)
      assert.is_nil(config.options.mermaid.theme)
    end)

    it("sets options with defaults when called with nil", function()
      config.setup()
      assert.is_not_nil(config.options)
      assert.are.equal("127.0.0.1", config.options.host)
    end)

    it("merges user options over defaults", function()
      config.setup({ port = 8080, browser = "firefox", theme = "dark" })
      assert.are.equal(8080, config.options.port)
      assert.are.equal("firefox", config.options.browser)
      assert.are.equal("dark", config.options.theme)
      -- defaults preserved
      assert.are.equal("127.0.0.1", config.options.host)
      assert.are.equal(300, config.options.debounce_ms)
    end)

    it("deep merges nested options", function()
      config.setup({ mermaid = { theme = "forest" } })
      assert.are.equal("forest", config.options.mermaid.theme)
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
  end)
end)
