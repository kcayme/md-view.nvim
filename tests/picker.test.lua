local config = require("md-view.config")
local picker = require("md-view.picker")

describe("picker", function()
  local orig_ui_select
  local orig_notify
  local orig_get_active_previews
  local orig_set_current_buf
  local orig_open_browser

  local captured_items
  local captured_opts
  local captured_callback

  before_each(function()
    orig_ui_select = vim.ui.select
    orig_notify = vim.notify
    orig_set_current_buf = vim.api.nvim_set_current_buf
    orig_open_browser = package.loaded["md-view.util"] and package.loaded["md-view.util"].open_browser

    vim.ui.select = function(items, opts, callback)
      captured_items = items
      captured_opts = opts
      captured_callback = callback
    end

    vim.api.nvim_set_current_buf = function() end

    -- Stub open_browser to avoid actual browser launch
    if not package.loaded["md-view.util"] then
      package.loaded["md-view.util"] = {}
    end
    package.loaded["md-view.util"].open_browser = function() end

    config.options = nil
  end)

  after_each(function()
    vim.ui.select = orig_ui_select
    vim.notify = orig_notify
    vim.api.nvim_set_current_buf = orig_set_current_buf
    if orig_open_browser then
      package.loaded["md-view.util"].open_browser = orig_open_browser
    end
    captured_items = nil
    captured_opts = nil
    captured_callback = nil
    config.options = nil
  end)

  local function stub_previews(previews)
    local md_view = require("md-view")
    orig_get_active_previews = md_view.get_active_previews
    md_view.get_active_previews = function()
      return previews
    end
  end

  local function restore_previews()
    local md_view = require("md-view")
    if orig_get_active_previews then
      md_view.get_active_previews = orig_get_active_previews
    end
  end

  describe("open", function()
    it("notifies and returns early when no active previews", function()
      stub_previews({})
      config.setup({ verbose = true })
      local notified = false
      vim.notify = function(_, level)
        if level == vim.log.levels.INFO then
          notified = true
        end
      end
      picker.open()
      assert.is_true(notified)
      assert.is_nil(captured_opts)
      restore_previews()
    end)

    it("uses default prompt 'Markdown Previews' when no config", function()
      stub_previews({ [1] = { port = 8080 } })
      vim.api.nvim_buf_get_name = function()
        return "/home/user/notes.md"
      end
      config.setup({})
      picker.open()
      assert.are.equal("Markdown Previews", captured_opts.prompt)
      restore_previews()
    end)

    it("uses custom prompt from config", function()
      stub_previews({ [1] = { port = 8080 } })
      vim.api.nvim_buf_get_name = function()
        return "/home/user/notes.md"
      end
      config.setup({ picker = { prompt = "My Previews" } })
      picker.open()
      assert.are.equal("My Previews", captured_opts.prompt)
      restore_previews()
    end)

    it("default format_item produces 'name  http://host:port'", function()
      stub_previews({ [1] = { port = 9000 } })
      vim.api.nvim_buf_get_name = function()
        return "/path/to/readme.md"
      end
      vim.fn.fnamemodify = function(_, _)
        return "readme.md"
      end
      config.setup({ host = "127.0.0.1" })
      picker.open()
      local result = captured_opts.format_item({ name = "readme.md", port = 9000, bufnr = 1 })
      assert.are.equal("readme.md  http://127.0.0.1:9000", result)
      restore_previews()
    end)

    it("custom format_item from config is called instead of built-in", function()
      stub_previews({ [1] = { port = 8080 } })
      vim.api.nvim_buf_get_name = function()
        return "/path/to/doc.md"
      end
      local called_with = nil
      config.setup({
        picker = {
          format_item = function(item)
            called_with = item
            return item.name
          end,
        },
      })
      picker.open()
      local item = { name = "doc.md", port = 8080, bufnr = 1 }
      local result = captured_opts.format_item(item)
      assert.are.equal("doc.md", result)
      assert.are.equal(item, called_with)
      restore_previews()
    end)

    it("kind is absent from opts when nil", function()
      stub_previews({ [1] = { port = 8080 } })
      vim.api.nvim_buf_get_name = function()
        return "/path/to/doc.md"
      end
      config.setup({})
      picker.open()
      assert.is_nil(captured_opts.kind)
      restore_previews()
    end)

    it("kind is present in opts when configured", function()
      stub_previews({ [1] = { port = 8080 } })
      vim.api.nvim_buf_get_name = function()
        return "/path/to/doc.md"
      end
      config.setup({ picker = { kind = "mdview" } })
      picker.open()
      assert.are.equal("mdview", captured_opts.kind)
      restore_previews()
    end)

    it("does not crash when preview has nil port and nil sse (hub mode)", function()
      -- Simulate a hub-mode preview entry
      stub_previews({
        [1] = { port = nil, sse = nil },
      })
      vim.api.nvim_buf_get_name = function()
        return "/path/to/doc.md"
      end
      vim.fn.fnamemodify = function(_, _)
        return "doc.md"
      end

      -- Stub get_mux to return a hub with a port
      local preview_mod = require("md-view.preview")
      local orig_get_mux = preview_mod.get_mux
      preview_mod.get_mux = function()
        return { port = 4999, clients = {} }
      end

      config.setup({ host = "127.0.0.1" })

      assert.has_no.errors(function()
        picker.open()
      end)

      preview_mod.get_mux = orig_get_mux
      restore_previews()
    end)

    it("uses hub port in collated item when preview.port is nil", function()
      stub_previews({
        [1] = { port = nil, sse = nil },
      })
      vim.api.nvim_buf_get_name = function()
        return "/path/to/doc.md"
      end
      vim.fn.fnamemodify = function(_, _)
        return "doc.md"
      end

      local preview_mod = require("md-view.preview")
      local orig_get_mux = preview_mod.get_mux
      preview_mod.get_mux = function()
        return { port = 4999, clients = {} }
      end

      config.setup({ host = "127.0.0.1" })

      picker.open()

      -- captured_items is populated by the vim.ui.select stub — verify collation used hub port
      assert.is_not_nil(captured_items, "vim.ui.select should have been called")
      assert.are.equal(4999, captured_items[1].port, "collated item port must come from hub when preview.port is nil")

      preview_mod.get_mux = orig_get_mux
      restore_previews()
    end)
  end)
end)
