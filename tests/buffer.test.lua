local buffer = require("md-view.buffer")

-- ---------------------------------------------------------------------------
-- Mock factories
-- ---------------------------------------------------------------------------

--- Creates a mock debounce function.
--- Calling the returned object immediately invokes fn synchronously (no timer).
--- .stop() is a spy: sets a flag and prevents future invocations.
--- All created debouncers are appended to the returned registry table.
local function make_debounce_factory(registry)
  return function(fn, _ms)
    local stopped = false
    local stop_called = false
    local obj = setmetatable({}, {
      __call = function(_, ...)
        if not stopped then
          fn(...)
        end
      end,
    })
    function obj.stop()
      stopped = true
      stop_called = true
    end
    obj._stop_called = function()
      return stop_called
    end
    table.insert(registry, obj)
    return obj
  end
end

--- Creates a mock uv table with synchronous callbacks.
--- Captures the last fs_event handle so tests can fire fs events.
local function make_uv(overrides)
  local last_handle = nil
  local uv = {
    new_fs_event = function()
      local h = {
        _started = false,
        _closing = false,
        _callback = nil,
        start = function(self, _path, _opts, cb)
          self._started = true
          self._callback = cb
        end,
        close = function(self)
          self._closing = true
        end,
        is_closing = function(self)
          return self._closing
        end,
      }
      last_handle = h
      return h
    end,
    fs_open = function(_path, _flags, _mode, cb)
      cb(nil, 42)
    end,
    fs_fstat = function(_fd, cb)
      cb(nil, { size = 11 })
    end,
    fs_read = function(_fd, _size, _off, cb)
      cb(nil, "line1\nline2")
    end,
    fs_close = function(_fd, cb)
      if cb then
        cb()
      end
    end,
  }
  for k, v in pairs(overrides or {}) do
    uv[k] = v
  end
  uv.get_handle = function()
    return last_handle
  end
  return uv
end

--- Creates a mock vim_api flat table.
--- Defaults produce a valid two-line buffer at window id 1, augroup id 99.
--- Pass key/value overrides to change specific behaviors.
--- Captures registered autocmds so tests can fire them:
---   autocmds[1] = content autocmd (TextChanged / BufWritePost / …)
---   autocmds[2] = cursor autocmd  (CursorMoved / CursorMovedI)
local function make_vim_api(autocmds, overrides)
  local api = {
    nvim_buf_is_valid = function(_b)
      return true
    end,
    nvim_buf_get_lines = function(_b, _s, _e, _strict)
      return { "hello", "world" }
    end,
    nvim_buf_line_count = function(_b)
      return 2
    end,
    nvim_buf_get_name = function(_b)
      return "/tmp/test.md"
    end,
    nvim_win_get_cursor = function(_w)
      return { 1, 0 }
    end,
    bufwinid = function(_b)
      return 1
    end,
    nvim_create_augroup = function(_name, _opts)
      return 99
    end,
    nvim_create_autocmd = function(events, opts)
      table.insert(autocmds, { events = events, opts = opts })
      return #autocmds
    end,
    nvim_del_augroup_by_id = function(_id) end,
    -- schedule fires synchronously so fs-read callbacks are testable without timers
    schedule = function(fn)
      fn()
    end,
    split = vim.split,
  }
  for k, v in pairs(overrides or {}) do
    api[k] = v
  end
  return api
end

--- Convenience: builds all three mocks in one call.
--- Returns { vim_api, uv, debounce, autocmds, debouncers }
local function make_mocks(vim_api_overrides, uv_overrides)
  local autocmds = {}
  local debouncers = {}
  local uv = make_uv(uv_overrides)
  local vim_api = make_vim_api(autocmds, vim_api_overrides)
  local debounce = make_debounce_factory(debouncers)
  return {
    vim_api = vim_api,
    uv = uv,
    debounce = debounce,
    autocmds = autocmds,
    debouncers = debouncers,
  }
end

--- Fire the content autocmd (index 1) with the given event name.
local function fire_content(autocmds, event_name)
  autocmds[1].opts.callback({ event = event_name or "TextChanged" })
end

--- Fire the cursor autocmd (index 2).
local function fire_cursor(autocmds)
  autocmds[2].opts.callback({ event = "CursorMoved" })
end

-- ---------------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------------

describe("buffer", function()
  describe("M.new", function()
    it("returns an instance with a watch method", function()
      local inst = buffer.new({})
      assert.is_not_nil(inst)
      assert.is_function(inst.watch)
    end)
  end)

  describe("scroll calculation", function()
    local watcher
    after_each(function()
      if watcher then
        watcher.stop()
        watcher = nil
      end
    end)

    it("cursor mode emits line-based position", function()
      local m = make_mocks({
        nvim_win_get_cursor = function(_w)
          return { 3, 0 }
        end,
      })
      local result
      watcher = buffer.new(m).watch(1, {
        on_content = function() end,
        on_scroll = function(p)
          result = p
        end,
      }, 100, "cursor")
      fire_cursor(m.autocmds)
      assert.are.same({ line = 2 }, result)
    end)

    it("percent mode emits fractional position", function()
      local m = make_mocks({
        nvim_win_get_cursor = function(_w)
          return { 2, 0 }
        end,
        nvim_buf_line_count = function(_b)
          return 5
        end,
      })
      local result
      watcher = buffer.new(m).watch(1, {
        on_content = function() end,
        on_scroll = function(p)
          result = p
        end,
      }, 100, "percent")
      fire_cursor(m.autocmds)
      -- (2-1) / (5-1) = 0.25
      assert.are.same({ percent = 0.25 }, result)
    end)

    it("nil scroll_method falls through to percent path", function()
      local m = make_mocks({
        nvim_win_get_cursor = function(_w)
          return { 1, 0 }
        end,
        nvim_buf_line_count = function(_b)
          return 3
        end,
      })
      local result
      watcher = buffer.new(m).watch(1, {
        on_content = function() end,
        on_scroll = function(p)
          result = p
        end,
      }, 100, nil)
      fire_cursor(m.autocmds)
      -- (1-1) / (3-1) = 0
      assert.are.same({ percent = 0 }, result)
    end)

    it("single-line buffer gives percent 0 without division error", function()
      local m = make_mocks({
        nvim_win_get_cursor = function(_w)
          return { 1, 0 }
        end,
        nvim_buf_line_count = function(_b)
          return 1
        end,
      })
      local result
      watcher = buffer.new(m).watch(1, {
        on_content = function() end,
        on_scroll = function(p)
          result = p
        end,
      }, 100, "percent")
      fire_cursor(m.autocmds)
      -- (1-1) / max(1-1, 1) = 0/1 = 0
      assert.are.same({ percent = 0 }, result)
    end)

    it("scroll is no-op when bufwinid returns -1 (buffer not visible)", function()
      local m = make_mocks({
        bufwinid = function(_b)
          return -1
        end,
      })
      local called = false
      watcher = buffer.new(m).watch(1, {
        on_content = function() end,
        on_scroll = function()
          called = true
        end,
      }, 100, "cursor")
      fire_cursor(m.autocmds)
      assert.is_false(called)
    end)
  end)

  describe("content events", function()
    local watcher
    after_each(function()
      if watcher then
        watcher.stop()
        watcher = nil
      end
    end)

    it("TextChanged triggers on_content with buffer lines", function()
      local m = make_mocks({
        nvim_buf_get_lines = function(_b, _s, _e, _strict)
          return { "a", "b" }
        end,
      })
      local got
      watcher = buffer.new(m).watch(1, {
        on_content = function(lines)
          got = lines
        end,
        on_scroll = function() end,
      }, 100, nil)
      fire_content(m.autocmds, "TextChanged")
      assert.are.same({ "a", "b" }, got)
    end)

    it("invalid buffer skips on_content", function()
      local m = make_mocks({
        nvim_buf_is_valid = function(_b)
          return false
        end,
      })
      local called = false
      watcher = buffer.new(m).watch(1, {
        on_content = function()
          called = true
        end,
        on_scroll = function() end,
      }, 100, nil)
      fire_content(m.autocmds, "TextChanged")
      assert.is_false(called)
    end)
  end)

  describe("wrote_from_nvim suppression", function()
    local watcher
    after_each(function()
      if watcher then
        watcher.stop()
        watcher = nil
      end
    end)

    local function setup_suppression()
      local m = make_mocks()
      local calls = 0
      watcher = buffer.new(m).watch(1, {
        on_content = function()
          calls = calls + 1
        end,
        on_scroll = function() end,
      }, 100, nil)
      return m, function()
        return calls
      end
    end

    it("BufWritePost then fs event: on_content called once total (fs path suppressed)", function()
      local m, call_count = setup_suppression()
      -- BufWritePost sets the flag and fires content_debounced (autocmd path) → 1 call
      fire_content(m.autocmds, "BufWritePost")
      assert.are.equal(1, call_count())
      -- fs event fires → file_content_debounced → flag is true → returns early
      m.uv.get_handle()._callback(nil, nil, nil)
      assert.are.equal(1, call_count()) -- still 1
    end)

    it("fs event without BufWritePost calls on_content once via fs path", function()
      local m, call_count = setup_suppression()
      m.uv.get_handle()._callback(nil, nil, nil)
      assert.are.equal(1, call_count())
    end)

    it("flag is one-shot: second fs event after suppression fires normally", function()
      local m, call_count = setup_suppression()
      fire_content(m.autocmds, "BufWritePost")
      m.uv.get_handle()._callback(nil, nil, nil) -- suppressed — flag consumed
      local after_suppress = call_count()
      m.uv.get_handle()._callback(nil, nil, nil) -- second fs event — flag is false → fires
      assert.are.equal(after_suppress + 1, call_count())
    end)
  end)

  describe("stop() teardown", function()
    it("calls stop on all three debouncers when fs watcher was started", function()
      local m = make_mocks()
      local w = buffer.new(m).watch(1, { on_content = function() end, on_scroll = function() end }, 100, nil)
      -- 3 debouncers: content, scroll, file_content
      assert.are.equal(3, #m.debouncers)
      w.stop()
      -- debouncers in creation order: [1]=content, [2]=scroll, [3]=file_content
      assert.is_true(m.debouncers[1]._stop_called())
      assert.is_true(m.debouncers[2]._stop_called())
      assert.is_true(m.debouncers[3]._stop_called())
    end)

    it("calls nvim_del_augroup_by_id with the correct group id", function()
      local deleted_id
      local m = make_mocks({
        nvim_create_augroup = function(_name, _opts)
          return 42
        end,
        nvim_del_augroup_by_id = function(id)
          deleted_id = id
        end,
      })
      local w = buffer.new(m).watch(1, { on_content = function() end, on_scroll = function() end }, 100, nil)
      w.stop()
      assert.are.equal(42, deleted_id)
    end)

    it("closes fs_watcher when not closing", function()
      local m = make_mocks()
      local w = buffer.new(m).watch(1, { on_content = function() end, on_scroll = function() end }, 100, nil)
      w.stop()
      assert.is_true(m.uv.get_handle()._closing)
    end)

    it("skips fs_watcher:close when already closing", function()
      local m = make_mocks()
      local w = buffer.new(m).watch(1, { on_content = function() end, on_scroll = function() end }, 100, nil)
      local close_calls = 0
      local h = m.uv.get_handle()
      h._closing = true
      local orig = h.close
      h.close = function(self)
        close_calls = close_calls + 1
        orig(self)
      end
      w.stop()
      assert.are.equal(0, close_calls)
    end)

    it("does not error when file_content_debounced is nil (empty filepath)", function()
      local m = make_mocks({
        nvim_buf_get_name = function(_b)
          return ""
        end,
      })
      local w = buffer.new(m).watch(1, { on_content = function() end, on_scroll = function() end }, 100, nil)
      assert.are.equal(2, #m.debouncers) -- only content + scroll
      assert.has_no.errors(function()
        w.stop()
      end)
    end)
  end)

  describe("fs watcher path", function()
    local watcher
    after_each(function()
      if watcher then
        watcher.stop()
        watcher = nil
      end
    end)

    it("no watcher created when filepath is empty string", function()
      local m = make_mocks({
        nvim_buf_get_name = function(_b)
          return ""
        end,
      })
      watcher = buffer.new(m).watch(1, { on_content = function() end, on_scroll = function() end }, 100, nil)
      assert.is_nil(m.uv.get_handle())
    end)

    it("no watcher created when filepath is nil", function()
      local m = make_mocks({
        nvim_buf_get_name = function(_b)
          return nil
        end,
      })
      watcher = buffer.new(m).watch(1, { on_content = function() end, on_scroll = function() end }, 100, nil)
      assert.is_nil(m.uv.get_handle())
    end)

    it("pcall failure: closes handle, calls debounce stop, file_content_debounced becomes nil", function()
      local m = make_mocks()
      local handle_closed = false
      -- Wrap new_fs_event to return a handle whose start() always throws
      local orig_new_fs_event = m.uv.new_fs_event
      m.uv.new_fs_event = function()
        local h = orig_new_fs_event()
        function h:start(_path, _opts, _cb)
          error("start failed")
        end
        function h:close()
          handle_closed = true
          self._closing = true
        end
        return h
      end
      -- Should not error at watch time
      assert.has_no.errors(function()
        watcher = buffer.new(m).watch(1, { on_content = function() end, on_scroll = function() end }, 100, nil)
      end)
      -- file_content_debounced (debouncer[3]) was created then immediately stopped
      assert.is_true(handle_closed)
      assert.are.equal(3, #m.debouncers)
      assert.is_true(m.debouncers[3]._stop_called())
      -- stop() should complete without error (fs_watcher is nil in this branch)
      assert.has_no.errors(function()
        watcher.stop()
      end)
      watcher = nil
    end)

    it("fs read result is split on newlines and delivered to on_content", function()
      local got
      local m = make_mocks(nil, {
        fs_read = function(_fd, _size, _off, cb)
          cb(nil, "alpha\nbeta\ngamma")
        end,
      })
      watcher = buffer.new(m).watch(1, {
        on_content = function(lines)
          got = lines
        end,
        on_scroll = function() end,
      }, 100, nil)
      m.uv.get_handle()._callback(nil, nil, nil)
      assert.are.same({ "alpha", "beta", "gamma" }, got)
    end)

    it("fs read error skips on_content", function()
      local called = false
      local m = make_mocks(nil, {
        fs_read = function(_fd, _size, _off, cb)
          cb("read error", nil)
        end,
      })
      watcher = buffer.new(m).watch(1, {
        on_content = function()
          called = true
        end,
        on_scroll = function() end,
      }, 100, nil)
      m.uv.get_handle()._callback(nil, nil, nil)
      assert.is_false(called)
    end)
  end)
end)
