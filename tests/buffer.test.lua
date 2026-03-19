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
end)
