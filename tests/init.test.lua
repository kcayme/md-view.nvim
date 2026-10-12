local M
local create_called
local notify_msg
local orig_notify

describe("md-view init", function()
  before_each(function()
    create_called = false
    notify_msg = nil
    orig_notify = vim.notify
    vim.notify = function(msg, level)
      notify_msg = { msg = msg, level = level }
    end
    package.loaded["md-view"] = nil
    package.loaded["md-view.preview"] = {
      create = function()
        create_called = true
      end,
      get_by_buffer = function()
        return nil
      end,
      destroy = function() end,
      close = function() end,
      get_active_previews = function()
        return {}
      end,
    }
    M = require("md-view")
    M.setup({ filetypes = { "markdown" } })
    notify_msg = nil
  end)

  after_each(function()
    vim.notify = orig_notify
    package.loaded["md-view"] = nil
    package.loaded["md-view.preview"] = nil
    package.loaded["md-view.config"] = nil
    package.loaded["md-view.vendor"] = nil
  end)

  it("blocks preview when filetype is not in filetypes list", function()
    vim.bo.filetype = "lua"
    M.open()
    assert.is_false(create_called)
    assert.is_not_nil(notify_msg)
    assert.are.equal(vim.log.levels.WARN, notify_msg.level)
    assert.truthy(notify_msg.msg:find("lua"))
  end)

  it("allows preview when filetype is in filetypes list", function()
    vim.bo.filetype = "markdown"
    M.open()
    assert.is_true(create_called)
    assert.is_nil(notify_msg)
  end)

  it("allows preview when filetypes is empty (no restriction)", function()
    M.setup({ filetypes = {} })
    vim.bo.filetype = "lua"
    M.open()
    assert.is_true(create_called)
  end)

  it("toggle blocks preview when filetype is not in filetypes list", function()
    vim.bo.filetype = "lua"
    M.toggle()
    assert.is_false(create_called)
  end)

  it("should not notify when curl is absent and vendor is unavailable", function()
    package.loaded["md-view"] = nil
    package.loaded["md-view.preview"] = {
      create = function() end,
      get_by_buffer = function()
        return nil
      end,
      destroy = function() end,
      close = function() end,
      get_active_previews = function()
        return {}
      end,
    }
    package.loaded["md-view.vendor"] = {
      is_available = function()
        return false
      end,
      fetch = function() end,
    }
    local orig_executable = vim.fn.executable
    vim.fn.executable = function(cmd)
      if cmd == "curl" then
        return 0
      end
      return orig_executable(cmd)
    end

    local notify_calls = {}
    local orig_notify_inner = orig_notify
    vim.notify = function(msg, level)
      table.insert(notify_calls, { msg = msg, level = level })
    end

    local m = require("md-view")
    m.setup({})

    vim.fn.executable = orig_executable
    vim.notify = orig_notify_inner
    package.loaded["md-view"] = nil
    package.loaded["md-view.preview"] = nil
    package.loaded["md-view.vendor"] = nil

    assert.are.equal(0, #notify_calls, "expected no notifications when curl is absent")
  end)

  it("close delegates to preview.close for current buffer", function()
    local closed_buf = nil
    package.loaded["md-view.preview"] = {
      create = function() end,
      get_by_buffer = function()
        return nil
      end,
      destroy = function() end,
      close = function(bufnr)
        closed_buf = bufnr
      end,
      get_active_previews = function()
        return {}
      end,
    }
    package.loaded["md-view"] = nil
    local fresh_M = require("md-view")
    fresh_M.setup({ filetypes = { "markdown" } })
    fresh_M.close(42)
    assert.are.equal(42, closed_buf)
  end)

  it("close_all calls preview.close for every active preview", function()
    local closed_bufs = {}
    package.loaded["md-view.preview"] = {
      create = function() end,
      get_by_buffer = function()
        return nil
      end,
      destroy = function() end,
      close = function(bufnr)
        table.insert(closed_bufs, bufnr)
      end,
      get_active_previews = function()
        return { [1] = {}, [7] = {} }
      end,
    }
    -- reload M so it picks up the new preview stub
    package.loaded["md-view"] = nil
    local fresh_M = require("md-view")
    fresh_M.setup({ filetypes = { "markdown" } })
    fresh_M.close_all()
    table.sort(closed_bufs)
    assert.are.same({ 1, 7 }, closed_bufs)
  end)

  it("restart is no-op when no active previews", function()
    local destroyed = {}
    local created = {}
    package.loaded["md-view.preview"] = {
      create = function(opts)
        table.insert(created, opts)
      end,
      get_by_buffer = function()
        return nil
      end,
      destroy = function(bufnr)
        table.insert(destroyed, bufnr)
      end,
      close = function() end,
      get_active_previews = function()
        return {}
      end,
    }
    package.loaded["md-view"] = nil
    local fresh_M = require("md-view")
    fresh_M.setup({})
    fresh_M.restart()
    assert.are.same({}, destroyed)
    assert.are.same({}, created)
  end)

  it("restart destroys all active previews then re-creates each with bufnr", function()
    local event_log = {}
    package.loaded["md-view.preview"] = {
      create = function(opts)
        table.insert(event_log, { kind = "create", bufnr = opts.bufnr })
      end,
      get_by_buffer = function()
        return nil
      end,
      destroy = function(bufnr)
        table.insert(event_log, { kind = "destroy", bufnr = bufnr })
      end,
      close = function() end,
      get_active_previews = function()
        return { [3] = {}, [9] = {} }
      end,
    }
    package.loaded["md-view"] = nil
    local fresh_M = require("md-view")
    fresh_M.setup({})
    fresh_M.restart()

    -- Verify correct buffer IDs were destroyed and re-created
    local destroyed = {}
    local created = {}

    for _, entry in ipairs(event_log) do
      if entry.kind == "destroy" then
        table.insert(destroyed, entry.bufnr)
      else
        table.insert(created, entry.bufnr)
      end
    end

    table.sort(destroyed)
    table.sort(created)
    assert.are.same({ 3, 9 }, destroyed)
    assert.are.same({ 3, 9 }, created)

    -- Verify all destroys happen before any creates
    local last_destroy_idx = 0
    local first_create_idx = math.huge

    for i, entry in ipairs(event_log) do
      if entry.kind == "destroy" then
        last_destroy_idx = i
      elseif entry.kind == "create" and i < first_create_idx then
        first_create_idx = i
      end
    end

    assert.is_true(last_destroy_idx < first_create_idx, "all destroys must complete before any creates")
  end)

  it("restart applies live theme to re-created previews", function()
    local created_opts = {}
    package.loaded["md-view.preview"] = {
      create = function(opts)
        table.insert(created_opts, opts)
      end,
      get_by_buffer = function()
        return nil
      end,
      destroy = function() end,
      close = function() end,
      get_active_previews = function()
        return { [1] = {} }
      end,
    }
    package.loaded["md-view"] = nil
    local fresh_M = require("md-view")
    fresh_M.setup({})
    -- seed a live theme (set_theme requires at least one active preview)
    fresh_M.set_theme("dark")
    fresh_M.restart()
    assert.are.equal(1, #created_opts)
    assert.are.equal("dark", created_opts[1].theme.mode)
  end)

  it("open({ path }) previews the buffer for that file", function()
    local created_bufnr
    package.loaded["md-view.preview"] = {
      create = function(opts)
        created_bufnr = opts.bufnr
      end,
      get_by_buffer = function()
        return nil
      end,
      destroy = function() end,
      close = function() end,
      get_active_previews = function()
        return {}
      end,
    }
    package.loaded["md-view"] = nil
    M = require("md-view")
    M.setup({ filetypes = { "markdown" } })

    local path = vim.fn.fnamemodify("tests/previews/headings.md", ":p")
    M.open({ path = path })

    local expected = vim.fn.bufnr(path)
    assert.is_true(expected ~= -1)
    assert.are.equal(expected, created_bufnr)
  end)

  it("open({ path }) rejects a non-markdown file", function()
    local create_called = false
    package.loaded["md-view.preview"] = {
      create = function()
        create_called = true
      end,
      get_by_buffer = function()
        return nil
      end,
      destroy = function() end,
      close = function() end,
      get_active_previews = function()
        return {}
      end,
    }
    package.loaded["md-view"] = nil
    M = require("md-view")
    M.setup({ filetypes = { "markdown" } })

    local path = vim.fn.fnamemodify("lua/md-view/init.lua", ":p")
    M.open({ path = path, verbose = false })

    assert.is_false(create_called)
  end)

  it("forwards palette to hub SSE when set_theme is called in hub mode", function()
    local hub_pushed = {}
    local fake_mux = {
      server = "mock",
      push = function(self, et, data)
        table.insert(hub_pushed, { event_type = et, data = data })
      end,
    }
    -- Re-inject preview mock with hub support (must clear md-view first)
    package.loaded["md-view"] = nil
    package.loaded["md-view.preview"] = {
      create = function() end,
      get_by_buffer = function()
        return nil
      end,
      destroy = function() end,
      get_active_previews = function()
        return { [1] = { sse = { push = function() end } } }
      end,
      get_mux = function()
        return fake_mux
      end,
    }
    M = require("md-view")
    M.setup({ single_page = { enable = true } })
    -- Seed a live theme so set_theme has state to push
    M.set_theme("dark")
    local found = false
    for _, ev in ipairs(hub_pushed) do
      if ev.event_type == "palette" and ev.data.id == 1 then
        found = true
      end
    end
    assert.is_true(found, "palette not forwarded to hub")
  end)

  describe("preview target", function()
    local terminal_calls
    local created_opts

    before_each(function()
      terminal_calls = {}
      created_opts = nil
      package.loaded["md-view.terminal"] = {
        open = function(target, bufnr, start_server)
          table.insert(terminal_calls, { target = target, bufnr = bufnr, start_server = start_server })
        end,
      }
      package.loaded["md-view.preview"].create = function(opts)
        create_called = true
        created_opts = opts
      end
      vim.bo.filetype = "markdown"
    end)

    after_each(function()
      package.loaded["md-view.terminal"] = nil
    end)

    it("should open the browser preview by default", function()
      M.open()

      assert.is_true(create_called)
      assert.are.equal("browser", created_opts.target)
      assert.are.same({}, terminal_calls)
    end)

    it("should hand split to the terminal preview without starting a server yet", function()
      M.open({ target = "split" })

      assert.is_false(create_called)
      assert.are.equal(1, #terminal_calls)
      assert.are.equal("split", terminal_calls[1].target)
      assert.are.equal(vim.api.nvim_get_current_buf(), terminal_calls[1].bufnr)
    end)

    it("should use preview.target from config when no target is given", function()
      M.setup({ preview = { target = "tmux" } })
      M.open()

      assert.are.equal("tmux", terminal_calls[1].target)
    end)

    it("should let an explicit browser target override a terminal config", function()
      M.setup({ preview = { target = "split" } })
      M.open({ target = "browser" })

      assert.is_true(create_called)
      assert.are.same({}, terminal_calls)
    end)

    it("should start the server with the terminal target when the terminal preview asks", function()
      M.setup({ single_page = { tab_label = "parent" } })
      M.open({ target = "split" })
      terminal_calls[1].start_server()

      assert.is_true(create_called)
      assert.are.equal("split", created_opts.target)
      -- the full config reaches preview.create, not just the per-call options
      assert.are.equal("127.0.0.1", created_opts.host)
      assert.is_not_nil(created_opts.theme)
      -- forcing the hub keeps the rest of single_page
      assert.are.equal("parent", created_opts.single_page.tab_label)
    end)

    it("should put the terminal preview's server in the hub even when single_page is off", function()
      M.setup({ single_page = { enable = false } })
      M.open({ target = "split" })
      terminal_calls[1].start_server()

      assert.is_true(created_opts.single_page.enable)
      assert.is_false(require("md-view.config").options.single_page.enable)
    end)

    it("should apply every terminal override to the terminal preview's server", function()
      M.setup({ table_of_contents = { enable = true }, toast = { enable = true } })
      M.open({ target = "split" })
      terminal_calls[1].start_server()

      assert.is_false(created_opts.table_of_contents.enable)
      assert.is_false(created_opts.toast.enable)
    end)
  end)
end)
