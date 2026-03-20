local theme = require("md-view.theme")

local M
local notify_calls
local orig_notify
local orig_background
local sse_events
local active_previews

local function make_mock_sse()
  return {
    push = function(self, event_type, data)
      table.insert(sse_events, { event = event_type, data = data })
    end,
  }
end

local function make_preview()
  return { sse = make_mock_sse() }
end

local function load_module(config_opts)
  package.loaded["md-view"] = nil
  package.loaded["md-view.config"] = nil
  package.loaded["md-view.preview"] = {
    create = function() end,
    get = function()
      return nil
    end,
    get_by_buffer = function()
      return nil
    end,
    destroy = function() end,
    get_active_previews = function()
      return active_previews
    end,
  }
  M = require("md-view")
  if config_opts ~= false then
    M.setup(config_opts or {})
  end
  notify_calls = {}
end

describe("theme_switch", function()
  before_each(function()
    orig_notify = vim.notify
    orig_background = vim.o.background
    notify_calls = {}
    sse_events = {}
    active_previews = {}
    vim.notify = function(msg, level)
      table.insert(notify_calls, { msg = msg, level = level })
    end
    load_module({ verbose = true })
  end)

  after_each(function()
    vim.notify = orig_notify
    vim.o.background = orig_background
    package.loaded["md-view"] = nil
    package.loaded["md-view.config"] = nil
    package.loaded["md-view.preview"] = nil
    package.loaded["md-view.vendor"] = nil
  end)

  describe("cycle logic", function()
    it("should cycle dark → light → auto → sync → dark with active previews", function()
      active_previews = { make_preview() }
      M.setup({ theme = { mode = "dark" } })
      notify_calls = {}

      M.set_theme("")
      assert.are.equal("light", notify_calls[#notify_calls].msg:match("theme: (%S+)"))

      M.set_theme("")
      assert.are.equal("auto", notify_calls[#notify_calls].msg:match("theme: (%S+)"))

      M.set_theme("")
      assert.are.equal("sync", notify_calls[#notify_calls].msg:match("theme: (%S+)"))

      M.set_theme("")
      assert.are.equal("dark", notify_calls[#notify_calls].msg:match("theme: (%S+)"))
    end)

    it("should initialize from sync config and first no-arg applies dark", function()
      active_previews = { make_preview() }
      M.setup({ theme = { mode = "sync" } })
      notify_calls = {}

      M.set_theme("")
      assert.are.equal("dark", notify_calls[1].msg:match("theme: (%S+)"))
    end)

    it("should initialize from resolved auto config (dark background) and first no-arg applies light", function()
      vim.o.background = "dark"
      active_previews = { make_preview() }
      M.setup({ theme = { mode = "auto" } })
      notify_calls = {}

      M.set_theme("")
      assert.are.equal("light", notify_calls[1].msg:match("theme: (%S+)"))
    end)

    it("should initialize from resolved auto config (light background) and first no-arg applies auto", function()
      vim.o.background = "light"
      active_previews = { make_preview() }
      M.setup({ theme = { mode = "auto" } })
      notify_calls = {}

      -- auto config, light bg → resolves to "light" → advance → "auto"
      M.set_theme("")
      assert.are.equal("auto", notify_calls[1].msg:match("theme: (%S+)"))
    end)

    it("should default to dark init when config.options is nil (first no-arg applies light)", function()
      -- Load without calling setup so config.options is nil
      active_previews = { make_preview() }
      load_module(false)
      package.loaded["md-view.config"] = { options = nil }
      M = require("md-view")
      notify_calls = {}

      M.set_theme("")
      assert.are.equal("light", notify_calls[1].msg:match("theme: (%S+)"))
    end)
  end)

  describe("explicit then cycle", function()
    it("should advance from explicit mode on subsequent no-arg call", function()
      active_previews = { make_preview() }
      M.setup({})
      notify_calls = {}

      M.set_theme("dark")
      assert.are.equal("dark", notify_calls[#notify_calls].msg:match("theme: (%S+)"))

      M.set_theme("")
      assert.are.equal("light", notify_calls[#notify_calls].msg:match("theme: (%S+)"))
    end)
  end)

  describe("setup reset", function()
    it("should reset cycle state on re-setup and re-initialize from new config", function()
      active_previews = { make_preview() }

      -- First: set to dark explicitly
      M.set_theme("dark")
      notify_calls = {}

      -- Re-setup with light mode
      M.setup({ theme = { mode = "light" } })
      notify_calls = {}

      -- First no-arg should re-initialize from light config and advance to auto
      M.set_theme("")
      assert.are.equal("auto", notify_calls[1].msg:match("theme: (%S+)"))
    end)
  end)

  describe("explicit modes push palette SSE event", function()
    it("should push palette event with non-empty css for dark", function()
      active_previews = { make_preview() }
      M.set_theme("dark")
      assert.are.equal(1, #sse_events)
      assert.are.equal("palette", sse_events[1].event)
      assert.truthy(sse_events[1].data.css and sse_events[1].data.css ~= "")
    end)

    it("should push palette event with non-empty css for light", function()
      active_previews = { make_preview() }
      M.set_theme("light")
      assert.are.equal(1, #sse_events)
      assert.are.equal("palette", sse_events[1].event)
      assert.truthy(sse_events[1].data.css and sse_events[1].data.css ~= "")
    end)

    it("should push palette event with non-empty css for auto", function()
      active_previews = { make_preview() }
      M.set_theme("auto")
      assert.are.equal(1, #sse_events)
      assert.are.equal("palette", sse_events[1].event)
      assert.truthy(sse_events[1].data.css and sse_events[1].data.css ~= "")
    end)

    it("should push palette event with non-empty css for sync", function()
      active_previews = { make_preview() }
      M.set_theme("sync")
      assert.are.equal(1, #sse_events)
      assert.are.equal("palette", sse_events[1].event)
      assert.truthy(sse_events[1].data.css and sse_events[1].data.css ~= "")
    end)

    it("should push palette event to all active previews", function()
      local p1, p2 = make_preview(), make_preview()
      active_previews = { p1, p2 }
      M.set_theme("dark")
      assert.are.equal(2, #sse_events)
    end)
  end)

  describe("auto resolution", function()
    it("should resolve auto to light when vim.o.background is light", function()
      vim.o.background = "light"
      active_previews = { make_preview() }
      M.set_theme("auto")
      local expected_css = theme.palette_css("light")
      assert.are.equal(expected_css, sse_events[1].data.css)
    end)

    it("should resolve auto to dark when vim.o.background is dark", function()
      vim.o.background = "dark"
      active_previews = { make_preview() }
      M.set_theme("auto")
      local expected_css = theme.palette_css("dark")
      assert.are.equal(expected_css, sse_events[1].data.css)
    end)

    it("should never pass auto to palette_css (css matches dark or light palette exactly)", function()
      vim.o.background = "light"
      active_previews = { make_preview() }
      M.set_theme("auto")
      local css = sse_events[1].data.css
      -- Must match light palette, not some auto fallback
      assert.are.equal(theme.palette_css("light"), css)
      assert.are_not.equal(theme.palette_css("dark"), css)
    end)
  end)

  describe("sync CSS content", function()
    it("should use theme.css() output for sync mode (contains :root block)", function()
      active_previews = { make_preview() }
      M.setup({ theme = { mode = "sync" } })
      notify_calls = {}
      M.set_theme("sync")
      local css = sse_events[1].data.css
      assert.truthy(css:find(":root {"))
    end)

    it("should use full theme.css output (same as theme.css({}) call)", function()
      active_previews = { make_preview() }
      M.setup({ theme = { mode = "sync" } })
      notify_calls = {}
      M.set_theme("sync")
      local css = sse_events[1].data.css
      local expected = theme.css({})
      assert.are.equal(expected, css)
    end)

    it("should use theme.css with configured highlights for sync", function()
      local highlights = { link = "Special" }
      active_previews = { make_preview() }
      M.setup({ theme = { mode = "sync", highlights = highlights } })
      notify_calls = {}
      M.set_theme("sync")
      local css = sse_events[1].data.css
      local expected = theme.css(highlights)
      assert.are.equal(expected, css)
    end)
  end)

  describe("notify message", function()
    it("should notify pre-resolution mode for explicit dark", function()
      active_previews = { make_preview() }
      M.set_theme("dark")
      assert.are.equal("[md-view] theme: dark", notify_calls[1].msg)
      assert.are.equal(vim.log.levels.INFO, notify_calls[1].level)
    end)

    it("should notify pre-resolution mode for explicit auto (not the resolved dark/light)", function()
      vim.o.background = "dark"
      active_previews = { make_preview() }
      M.set_theme("auto")
      assert.are.equal("[md-view] theme: auto", notify_calls[1].msg)
    end)

    it("should notify pre-resolution mode for explicit sync", function()
      active_previews = { make_preview() }
      M.set_theme("sync")
      assert.are.equal("[md-view] theme: sync", notify_calls[1].msg)
    end)

    it("should notify post-advance value for cycle path", function()
      active_previews = { make_preview() }
      M.setup({ theme = { mode = "dark" } })
      notify_calls = {}
      M.set_theme("")
      assert.are.equal("[md-view] theme: light", notify_calls[1].msg)
    end)
  end)

  describe("invalid mode", function()
    it("should warn on invalid mode arg and not push SSE event", function()
      active_previews = { make_preview() }
      M.set_theme("invalid")
      assert.are.equal(1, #notify_calls)
      assert.are.equal(vim.log.levels.WARN, notify_calls[1].level)
      assert.are.equal(0, #sse_events)
    end)

    it("should not update current_live_theme on invalid mode (cycle is not advanced)", function()
      active_previews = { make_preview() }
      M.setup({ theme = { mode = "dark" } })
      notify_calls = {}
      -- invalid arg should not change cycle state
      M.set_theme("bad")
      -- next no-arg should still advance from dark (dark config init)
      M.set_theme("")
      assert.are.equal("[md-view] theme: light", notify_calls[#notify_calls].msg)
    end)

    it("should warn even when no active previews for invalid arg", function()
      active_previews = {}
      M.set_theme("invalid")
      assert.are.equal(1, #notify_calls)
      assert.are.equal(vim.log.levels.WARN, notify_calls[1].level)
    end)
  end)

  describe("no active previews", function()
    it("should not error and not notify when no active previews", function()
      active_previews = {}
      M.set_theme("dark")
      assert.are.equal(0, #notify_calls)
      assert.are.equal(0, #sse_events)
    end)

    it("should not update current_live_theme when no active previews", function()
      active_previews = {}
      M.setup({ theme = { mode = "dark" } })
      notify_calls = {}

      -- No-arg with no previews: should not advance state
      M.set_theme("")
      assert.are.equal(0, #notify_calls)

      -- Now add preview and call again - should still start from dark init
      active_previews = { make_preview() }
      M.set_theme("")
      assert.are.equal("[md-view] theme: light", notify_calls[1].msg)
    end)

    it("should not notify for no-arg call with no active previews", function()
      active_previews = {}
      M.set_theme("")
      assert.are.equal(0, #notify_calls)
    end)
  end)

  describe("new preview inherits current_live_theme", function()
    local create_opts
    local orig_filetype

    before_each(function()
      create_opts = nil
      orig_filetype = vim.bo.filetype
      vim.bo.filetype = "markdown"
      -- Override mock create to capture opts
      package.loaded["md-view.preview"].create = function(opts)
        create_opts = opts
      end
    end)

    after_each(function()
      vim.bo.filetype = orig_filetype
    end)

    it("should open new preview with current_live_theme mode when set", function()
      active_previews = { make_preview() }
      M.setup({ theme = { mode = "dark" } })
      notify_calls = {}
      M.set_theme("light")

      -- Now open a new preview; it should use light, not configured dark
      active_previews = {}
      M.open()
      assert.are.equal("light", create_opts.theme.mode)
    end)

    it("should open new preview with configured mode when current_live_theme is nil", function()
      M.setup({ theme = { mode = "dark" } })
      M.open()
      assert.are.equal("dark", create_opts.theme.mode)
    end)

    it("should not mutate config.options when overriding for new preview", function()
      active_previews = { make_preview() }
      M.setup({ theme = { mode = "dark" } })
      notify_calls = {}
      M.set_theme("light")

      active_previews = {}
      M.open()
      -- config.options must remain unchanged
      local config = require("md-view.config")
      assert.are.equal("dark", config.options.theme.mode)
    end)

    it("should apply current_live_theme for each subsequent new preview", function()
      active_previews = { make_preview() }
      M.setup({ theme = { mode = "dark" } })
      notify_calls = {}
      M.set_theme("sync")

      active_previews = {}
      M.open()
      assert.are.equal("sync", create_opts.theme.mode)

      -- Open again — same live theme should apply
      create_opts = nil
      M.open()
      assert.are.equal("sync", create_opts.theme.mode)
    end)

    it("should use cycled theme (not config sync) when opening new preview after 2 no-arg cycles", function()
      -- Reproduce: configure sync, cycle twice (sync→dark→light), open new preview
      active_previews = { make_preview() }
      M.setup({ theme = { mode = "sync" } })
      notify_calls = {}

      M.set_theme("") -- sync→dark
      M.set_theme("") -- dark→light
      assert.are.equal("light", notify_calls[#notify_calls].msg:match("theme: (%S+)"))

      -- Open a brand-new preview; should use "light", not the configured "sync"
      active_previews = {}
      M.open()
      assert.are.equal("light", create_opts.theme.mode)
    end)
  end)

  describe("reopen existing preview inherits live theme", function()
    local existing_preview
    local reopen_sse_events
    local orig_filetype

    local function make_existing_preview()
      reopen_sse_events = {}
      return {
        sse = {
          push = function(self, event_type, data)
            table.insert(reopen_sse_events, { event = event_type, data = data })
          end,
        },
        port = 8080,
      }
    end

    before_each(function()
      existing_preview = nil
      reopen_sse_events = {}
      orig_filetype = vim.bo.filetype
      vim.bo.filetype = "markdown"
      package.loaded["md-view.preview"].get_by_buffer = function()
        return existing_preview
      end
      package.loaded["md-view.preview"].create = function() end
    end)

    after_each(function()
      vim.bo.filetype = orig_filetype
    end)

    it("should push palette SSE to existing preview when live theme is set", function()
      existing_preview = make_existing_preview()
      active_previews = { make_preview() }
      M.setup({ theme = { mode = "dark" } })
      notify_calls = {}
      M.set_theme("light")

      M.open()

      assert.are.equal(1, #reopen_sse_events)
      assert.are.equal("palette", reopen_sse_events[1].event)
      assert.are.equal(theme.palette_css("light"), reopen_sse_events[1].data.css)
    end)

    it("should not push palette SSE when no live theme is set", function()
      existing_preview = make_existing_preview()
      M.setup({ theme = { mode = "dark" } })

      M.open()

      assert.are.equal(0, #reopen_sse_events)
    end)

    it("should push correct CSS for auto mode when reopening", function()
      vim.o.background = "light"
      existing_preview = make_existing_preview()
      active_previews = { make_preview() }
      M.setup({ theme = { mode = "dark" } })
      notify_calls = {}
      M.set_theme("auto")

      M.open()

      assert.are.equal(1, #reopen_sse_events)
      assert.are.equal(theme.palette_css("light"), reopen_sse_events[1].data.css)
    end)

    it("should push correct CSS for sync mode when reopening", function()
      existing_preview = make_existing_preview()
      active_previews = { make_preview() }
      M.setup({ theme = { mode = "dark" } })
      notify_calls = {}
      M.set_theme("sync")

      M.open()

      assert.are.equal(1, #reopen_sse_events)
      -- sync CSS contains :root block (from theme.css())
      assert.truthy(reopen_sse_events[1].data.css:find(":root {"))
    end)
  end)
end)
