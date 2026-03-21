local config = require("md-view.config")

describe("preview hub integration", function()
  local fake_hub
  local orig_notify

  before_each(function()
    orig_notify = vim.notify
    vim.notify = function() end

    -- Reset module cache so preview.lua picks up mocked dependencies
    package.loaded["md-view.preview"] = nil
    package.loaded["md-view.server.handlers.hub"] = nil

    fake_hub = {
      registry = {},
      clients = {},
      last = {},
      server = "mock",
      port = 4999,
      _events = {},
      register = function(self, bufnr, path, _)
        local filename = vim.fn.fnamemodify(path, ":t")
        self.registry[bufnr] = { title = filename, label = filename }
      end,
      unregister = function(self, bufnr)
        self.registry[bufnr] = nil
        self.last[bufnr] = nil
      end,
      push = function(self, et, data)
        table.insert(self._events, { event_type = et, data = data })
      end,
      close_all = function() end,
      add_client = function() end,
    }
    package.loaded["md-view.server.handlers.hub"] = {
      new = function()
        return fake_hub
      end,
      routes = {},
    }

    -- Mock TCP, buffer watcher, browser open, router to avoid real side-effects
    package.loaded["md-view.server.tcp"] = {
      start = function()
        local srv = {
          is_closing = function()
            return false
          end,
          close = function() end,
        }
        return srv, 8000
      end,
      stop = function() end,
    }
    package.loaded["md-view.buffer"] = {
      watch = function()
        return { stop = function() end }
      end,
    }
    package.loaded["md-view.util"] = {
      open_browser = function() end,
      notify = function() end,
      table_len = function(t)
        local n = 0
        for _ in pairs(t) do
          n = n + 1
        end
        return n
      end,
    }
    package.loaded["md-view.server.router"] = {
      new = function()
        return function() end
      end,
    }
    package.loaded["md-view.server.handlers.direct"] = { routes = {} }
    package.loaded["md-view.server.template"] = {
      render = function()
        return ""
      end,
    }
    package.loaded["md-view.theme"] = {
      css = function()
        return ""
      end,
      palette_css = function()
        return ""
      end,
      resolve = function()
        return { theme = "dark", highlight_theme = "vs2015", mermaid_theme = "default" }
      end,
    }

    config.setup({
      filetypes = { "markdown" },
      single_page = { enable = true, tab_label = "filename" },
    })
    vim.g.md_view_mux_vimleave_registered = nil
    vim.g.md_view_vimleave_registered = nil
  end)

  after_each(function()
    vim.notify = orig_notify
    package.loaded["md-view.preview"] = nil
    package.loaded["md-view.server.handlers.hub"] = nil
    package.loaded["md-view.server.tcp"] = nil
    package.loaded["md-view.buffer"] = nil
    package.loaded["md-view.util"] = nil
    package.loaded["md-view.server.router"] = nil
    package.loaded["md-view.server.handlers.direct"] = nil
    package.loaded["md-view.server.template"] = nil
    package.loaded["md-view.theme"] = nil
    -- Do not clear md-view.config: destroy() requires it, and before_each resets it via setup()
    vim.g.md_view_mux_vimleave_registered = nil
    vim.g.md_view_vimleave_registered = nil
  end)

  it("pushes preview_added to hub when a preview is created", function()
    local preview = require("md-view.preview")
    -- Use the actual current buf so preview.create's nvim_get_current_buf() matches
    local bufnr = vim.api.nvim_get_current_buf()

    preview.create(config.options)

    local found = false
    for _, ev in ipairs(fake_hub._events) do
      if ev.event_type == "preview_added" and ev.data.id == bufnr then
        found = true
      end
    end
    assert.is_true(found, "preview_added not pushed")

    preview.destroy(bufnr)
  end)

  it("pushes preview_removed and does NOT push close when auto_close is false", function()
    config.setup({
      single_page = { enable = true, tab_label = "filename" },
      auto_close = false,
    })
    local preview = require("md-view.preview")
    local bufnr = vim.api.nvim_get_current_buf()

    preview.create(config.options)
    fake_hub._events = {} -- clear after create

    preview.destroy(bufnr)

    local has_removed, has_close = false, false
    for _, ev in ipairs(fake_hub._events) do
      if ev.event_type == "preview_removed" then
        has_removed = true
      end
      if ev.event_type == "close" then
        has_close = true
      end
    end
    assert.is_true(has_removed, "preview_removed not pushed")
    assert.is_false(has_close, "close must not be pushed when auto_close = false")
  end)

  it("pushes close when last preview is destroyed and auto_close is true", function()
    config.setup({
      single_page = { enable = true, tab_label = "filename" },
      auto_close = true,
    })
    local preview = require("md-view.preview")
    local bufnr = vim.api.nvim_get_current_buf()

    preview.create(config.options)
    fake_hub._events = {} -- clear after create

    preview.destroy(bufnr)

    local has_close = false
    for _, ev in ipairs(fake_hub._events) do
      if ev.event_type == "close" then
        has_close = true
      end
    end
    assert.is_true(has_close, "close must be pushed when auto_close = true and last preview is gone")
  end)

  it("single_page.close_by = 'tab' suppresses close even when auto_close = true", function()
    config.setup({
      single_page = { enable = true, tab_label = "filename", close_by = "tab" },
      auto_close = true,
    })
    local preview = require("md-view.preview")
    local bufnr = vim.api.nvim_get_current_buf()

    preview.create(config.options)
    fake_hub._events = {}

    preview.destroy(bufnr)

    local has_close = false
    for _, ev in ipairs(fake_hub._events) do
      if ev.event_type == "close" then
        has_close = true
      end
    end
    assert.is_false(has_close, "single_page.close_by='tab' must suppress window close")
  end)

  it("single_page.close_by = 'page' pushes close even when top-level auto_close = false", function()
    config.setup({
      single_page = { enable = true, tab_label = "filename", close_by = "page" },
      auto_close = false,
    })
    local preview = require("md-view.preview")
    local bufnr = vim.api.nvim_get_current_buf()

    preview.create(config.options)
    fake_hub._events = {}

    preview.destroy(bufnr)

    local has_close = false
    for _, ev in ipairs(fake_hub._events) do
      if ev.event_type == "close" then
        has_close = true
      end
    end
    assert.is_true(has_close, "single_page.close_by='page' must push close regardless of top-level auto_close")
  end)

  it("single_page.close_by = false suppresses close even when auto_close = true", function()
    config.setup({
      single_page = { enable = true, tab_label = "filename", close_by = false },
      auto_close = true,
    })
    local preview = require("md-view.preview")
    local bufnr = vim.api.nvim_get_current_buf()

    preview.create(config.options)
    fake_hub._events = {}

    preview.destroy(bufnr)

    local has_close = false
    for _, ev in ipairs(fake_hub._events) do
      if ev.event_type == "close" then
        has_close = true
      end
    end
    assert.is_false(has_close, "single_page.close_by=false must suppress window close")
  end)

  it("single_page follow_focus=false: does not push focus or reopen browser when hub has clients", function()
    local open_calls = {}
    package.loaded["md-view.util"] = {
      open_browser = function(url)
        table.insert(open_calls, url)
      end,
      notify = function() end,
      table_len = function(t)
        local n = 0
        for _ in pairs(t) do
          n = n + 1
        end
        return n
      end,
    }
    config.setup({
      single_page = { enable = true, tab_label = "filename" },
      follow_focus = false,
    })
    local preview = require("md-view.preview")
    local bufnr = vim.api.nvim_get_current_buf()

    preview.create(config.options)
    assert.are.equal(1, #open_calls, "browser should open once on first create")

    -- Simulate a connected client
    fake_hub.clients = { "fake_client" }
    fake_hub._events = {}
    open_calls = {}

    -- Second open: hub has clients, follow_focus=false — should not push focus or reopen browser
    preview.create(config.options)

    assert.are.equal(0, #open_calls, "browser must not reopen when follow_focus=false and hub has clients")

    local has_focus = false
    for _, ev in ipairs(fake_hub._events) do
      if ev.event_type == "focus" and ev.data.id == bufnr then
        has_focus = true
      end
    end
    assert.is_false(has_focus, "focus event must not be pushed when follow_focus=false")

    preview.destroy(bufnr)
  end)

  it("single_page follow_focus=true: pushes focus event without reopening browser when hub has clients", function()
    local open_calls = {}
    package.loaded["md-view.util"] = {
      open_browser = function(url)
        table.insert(open_calls, url)
      end,
      notify = function() end,
      table_len = function(t)
        local n = 0
        for _ in pairs(t) do
          n = n + 1
        end
        return n
      end,
    }
    config.setup({
      single_page = { enable = true, tab_label = "filename" },
      follow_focus = true,
    })
    local preview = require("md-view.preview")
    local bufnr = vim.api.nvim_get_current_buf()

    preview.create(config.options)
    assert.are.equal(1, #open_calls, "browser should open once on first create")

    -- Simulate a connected client
    fake_hub.clients = { "fake_client" }
    fake_hub._events = {}
    open_calls = {}

    -- Second open: hub has clients, follow_focus=true — should push focus but NOT open new browser tab
    preview.create(config.options)

    assert.are.equal(0, #open_calls, "browser must not reopen when follow_focus=true and hub already has clients")

    local has_focus = false
    for _, ev in ipairs(fake_hub._events) do
      if ev.event_type == "focus" and ev.data.id == bufnr then
        has_focus = true
      end
    end
    assert.is_true(has_focus, "focus event must be pushed when follow_focus=true and hub has clients")

    preview.destroy(bufnr)
  end)

  it("does not open per-preview URL when preview already active in single_page mode", function()
    local open_calls = {}
    -- Must replace before requiring preview so preview.lua captures the tracking mock
    package.loaded["md-view.util"] = {
      open_browser = function(url)
        table.insert(open_calls, url)
      end,
      notify = function() end,
      table_len = function(t)
        local n = 0
        for _ in pairs(t) do
          n = n + 1
        end
        return n
      end,
    }
    local preview = require("md-view.preview")
    local bufnr = vim.api.nvim_get_current_buf()

    -- First create: hub already "running" (server="mock"), opens hub URL once
    preview.create(config.options)
    assert.are.equal(1, #open_calls, "browser should open once for first create")
    assert.truthy(open_calls[1]:find(":" .. fake_hub.port), "should open hub URL, not per-preview URL")

    -- Second create for same bufnr: hub has no SSE clients yet (headless), should open hub URL again
    preview.create(config.options)
    assert.are.equal(2, #open_calls, "browser should open again when hub has no clients")
    assert.truthy(open_calls[2]:find(":" .. fake_hub.port), "second open should still be hub URL")

    preview.destroy(bufnr)
  end)

  it("registers hub entry before pushing preview_added", function()
    local preview = require("md-view.preview")
    local bufnr = vim.api.nvim_get_current_buf()

    -- Intercept push to verify registry is populated at push time
    local registry_at_push = nil
    local orig_push = fake_hub.push
    fake_hub.push = function(self, et, data)
      if et == "preview_added" then
        registry_at_push = vim.deepcopy(self.registry)
      end
      orig_push(self, et, data)
    end

    preview.create(config.options)
    assert.is_not_nil(
      registry_at_push and registry_at_push[bufnr],
      "registry entry must exist before preview_added is pushed"
    )

    preview.destroy(bufnr)
  end)

  it("server.start is called exactly once per create in hub mode", function()
    local start_calls = 0
    package.loaded["md-view.server.tcp"] = {
      start = function()
        start_calls = start_calls + 1
        local srv = {
          is_closing = function()
            return false
          end,
          close = function() end,
        }
        return srv, 8000
      end,
      stop = function() end,
    }

    -- before_each pre-populates fake_hub.server = "mock", which causes init_hub to
    -- skip server.start entirely. Clear it so init_hub calls server.start this test.
    fake_hub.server = nil

    local preview = require("md-view.preview")
    local bufnr = vim.api.nvim_get_current_buf()

    preview.create(config.options)

    assert.are.equal(1, start_calls, "server.start must be called exactly once in hub mode (hub server only)")

    preview.destroy(bufnr)
  end)

  it("watcher on_content and on_scroll do not crash in hub mode (nil sse)", function()
    local captured_callbacks = {}

    package.loaded["md-view.buffer"] = {
      watch = function(_, callbacks)
        captured_callbacks = callbacks
        return { stop = function() end }
      end,
    }

    local preview = require("md-view.preview")
    local bufnr = vim.api.nvim_get_current_buf()

    preview.create(config.options)

    assert.has_no.errors(function()
      captured_callbacks.on_content({ "# Hello" })
    end)

    assert.has_no.errors(function()
      captured_callbacks.on_scroll({ top = 0, bufnr = bufnr })
    end)

    preview.destroy(bufnr)
  end)
end)
