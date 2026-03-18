local config = require("md-view.config")

describe("preview mux integration", function()
  local fake_mux
  local orig_notify

  before_each(function()
    orig_notify = vim.notify
    vim.notify = function() end

    -- Reset module cache so preview.lua picks up mocked dependencies
    package.loaded["md-view.preview"] = nil
    package.loaded["md-view.server.mux"] = nil

    fake_mux = {
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
      start = function()
        return true
      end,
      stop = function(self)
        self.server = nil
      end,
      close_all = function() end,
      add_client = function() end,
    }
    package.loaded["md-view.server.mux"] = {
      new = function()
        return fake_mux
      end,
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
    package.loaded["md-view.util"] = { open_browser = function() end }
    package.loaded["md-view.server.router"] = { handle = function() end }
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
    package.loaded["md-view.server.mux"] = nil
    package.loaded["md-view.server.tcp"] = nil
    package.loaded["md-view.buffer"] = nil
    package.loaded["md-view.util"] = nil
    package.loaded["md-view.server.router"] = nil
    package.loaded["md-view.server.template"] = nil
    package.loaded["md-view.theme"] = nil
    -- Do not clear md-view.config: destroy() requires it, and before_each resets it via setup()
    vim.g.md_view_mux_vimleave_registered = nil
    vim.g.md_view_vimleave_registered = nil
  end)

  it("pushes preview_added to mux when a preview is created", function()
    local preview = require("md-view.preview")
    -- Use the actual current buf so preview.create's nvim_get_current_buf() matches
    local bufnr = vim.api.nvim_get_current_buf()

    preview.create(config.options)

    local found = false
    for _, ev in ipairs(fake_mux._events) do
      if ev.event_type == "preview_added" and ev.data.id == bufnr then
        found = true
      end
    end
    assert.is_true(found, "preview_added not pushed")

    preview.destroy(bufnr)
  end)

  it("pushes preview_removed and does NOT push close on destroy", function()
    local preview = require("md-view.preview")
    local bufnr = vim.api.nvim_get_current_buf()

    preview.create(config.options)
    fake_mux._events = {} -- clear after create

    preview.destroy(bufnr)

    local has_removed, has_close = false, false
    for _, ev in ipairs(fake_mux._events) do
      if ev.event_type == "preview_removed" then
        has_removed = true
      end
      if ev.event_type == "close" then
        has_close = true
      end
    end
    assert.is_true(has_removed, "preview_removed not pushed")
    assert.is_false(has_close, "close event must be suppressed in mux mode")
  end)

  it("registers mux entry before pushing preview_added", function()
    local preview = require("md-view.preview")
    local bufnr = vim.api.nvim_get_current_buf()

    -- Intercept push to verify registry is populated at push time
    local registry_at_push = nil
    local orig_push = fake_mux.push
    fake_mux.push = function(self, et, data)
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
end)
