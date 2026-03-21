local M = {}

local util = require("md-view.util")

---@class MdViewBufferOpts
---@field bufnr integer
---@field callbacks MdViewBufferCallbacks
---@field debounce_ms integer
---@field scroll_method? string
---@field uv? table
---@field vim_api? table
---@field debounce? fun(fn: function, ms: integer): MdViewDebounced

---@class MdViewBufferCallbacks
---@field on_content fun(lines: string[])
---@field on_scroll fun(data: table)

---@class MdViewDebounced
---@field stop fun()

---@class MdViewBufferState
---@field wrote_from_nvim boolean
---@field stopped boolean

---@class MdViewFsWatcher
---@field watcher table
---@field debounced MdViewDebounced

---@param vim_api table
---@param debounce fun(fn: function, ms: integer): MdViewDebounced
---@param bufnr integer
---@param callbacks MdViewBufferCallbacks
---@param debounce_ms integer
---@return MdViewDebounced
local function create_content_debounced(vim_api, debounce, bufnr, callbacks, debounce_ms)
  return debounce(function()
    if not vim_api.nvim_buf_is_valid(bufnr) then
      return
    end

    local lines = vim_api.nvim_buf_get_lines(bufnr, 0, -1, false)

    callbacks.on_content(lines)
  end, debounce_ms)
end

---@param vim_api table
---@param debounce fun(fn: function, ms: integer): MdViewDebounced
---@param bufnr integer
---@param callbacks MdViewBufferCallbacks
---@param scroll_method? string
---@return MdViewDebounced
local function create_scroll_debounced(vim_api, debounce, bufnr, callbacks, scroll_method)
  return debounce(function()
    local win = vim_api.bufwinid(bufnr)
    if not vim_api.nvim_buf_is_valid(bufnr) or win == -1 then
      return
    end

    local cursor = vim_api.nvim_win_get_cursor(win)
    local scroll_opts = {}

    if scroll_method == "cursor" then
      scroll_opts.line = cursor[1] - 1
    else
      local total = vim_api.nvim_buf_line_count(bufnr)

      scroll_opts.percent = (cursor[1] - 1) / math.max(total - 1, 1)
    end

    callbacks.on_scroll(scroll_opts)
  end, 50)
end

---@param vim_api table
---@param bufnr integer
---@param group integer
---@param content_debounced MdViewDebounced
---@param scroll_debounced MdViewDebounced
---@param state MdViewBufferState
---@return integer[]
local function register_autocmds(vim_api, bufnr, group, content_debounced, scroll_debounced, state)
  local ids = {}

  ids[#ids + 1] = vim_api.nvim_create_autocmd(
    { "TextChanged", "TextChangedI", "BufWritePost", "BufReadPost", "FileChangedShellPost" },
    {
      group = group,
      buffer = bufnr,
      callback = function(ev)
        if ev.event == "BufWritePost" then
          state.wrote_from_nvim = true
        end
        content_debounced()
      end,
    }
  )

  ids[#ids + 1] = vim_api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      scroll_debounced()
    end,
  })

  return ids
end

-- Watch the file on disk for external changes (e.g. an AI agent editing while Neovim is
-- unfocused). Reads content directly from disk so the preview stays live without requiring
-- a checktime or buffer reload.
-- Rename-based writers (Claude Code, sed -i, rsync, etc.) atomically replace the
-- file, which kills the inotify watch on the old inode. Detect the rename event and
-- restart the watcher on the new file at the same path so live updates keep working.
-- Returns { watcher, debounced } on success, or nil if filepath is empty or start fails.
---@param uv table
---@param vim_api table
---@param debounce fun(fn: function, ms: integer): MdViewDebounced
---@param bufnr integer
---@param callbacks MdViewBufferCallbacks
---@param debounce_ms integer
---@param state MdViewBufferState
---@return MdViewFsWatcher?
local function start_fs_watcher(uv, vim_api, debounce, bufnr, callbacks, debounce_ms, state)
  local filepath = vim_api.nvim_buf_get_name(bufnr)

  if not filepath or filepath == "" then
    return nil
  end

  local handle = uv.new_fs_event()

  -- Tracks whether the last on-disk change was written by Neovim itself (BufWritePost).
  -- Used to suppress the redundant fs_watch push that would otherwise double-fire on :w.
  local file_content_debounced = debounce(function()
    if state.wrote_from_nvim then
      state.wrote_from_nvim = false
      return
    end

    uv.fs_open(filepath, "r", 438, function(err, fd)
      if err or not fd then
        return
      end

      uv.fs_fstat(fd, function(serr, stat)
        if serr or not stat then
          uv.fs_close(fd, function() end)
          return
        end

        uv.fs_read(fd, stat.size, 0, function(rerr, data)
          uv.fs_close(fd, function() end)
          if rerr or not data then
            return
          end

          vim_api.schedule(function()
            if vim_api.nvim_buf_is_valid(bufnr) then
              callbacks.on_content(vim_api.split(data, "\n", { plain = true }))
            end
          end)
        end)
      end)
    end)
  end, debounce_ms)

  local start_watching = function()
    if state.stopped then
      return
    end

    handle:start(filepath, {}, function(ferr, _name, events)
      if ferr then
        return
      end

      if events and events.rename then
        handle:stop()
        vim_api.schedule(function()
          pcall(start_watching)
        end)
      end

      file_content_debounced()
    end)
  end

  local ok = pcall(start_watching)

  if not ok then
    handle:close()
    file_content_debounced.stop()
    return nil
  end

  return {
    watcher = handle,
    debounced = file_content_debounced,
  }
end

---@param opts MdViewBufferOpts
---@return table
function M.new(opts)
  opts = opts or {}

  local bufnr = opts.bufnr
  local callbacks = opts.callbacks
  local debounce_ms = opts.debounce_ms
  local scroll_method = opts.scroll_method
  local uv = opts.uv or (vim.uv or vim.loop)
  local debounce = opts.debounce or util.debounce
  local vim_api = opts.vim_api
    -- vim.api is the base; bufwinid and schedule are injected on top.
    -- Neither key exists in vim.api today so there is no collision.
    -- "keep" means our custom keys (bufwinid, schedule, split) win if vim.api ever gains
    -- keys with the same names in a future Neovim version.
    or vim.tbl_extend("keep", {
      bufwinid = vim.fn.bufwinid,
      schedule = vim.schedule,
      split = vim.split,
    }, vim.api)

  local state = { wrote_from_nvim = false, stopped = false }
  local group = vim_api.nvim_create_augroup("md_view_" .. bufnr, { clear = true })
  local content_debounced = create_content_debounced(vim_api, debounce, bufnr, callbacks, debounce_ms)
  local scroll_debounced = create_scroll_debounced(vim_api, debounce, bufnr, callbacks, scroll_method)
  local ids = register_autocmds(vim_api, bufnr, group, content_debounced, scroll_debounced, state)
  local fs = start_fs_watcher(uv, vim_api, debounce, bufnr, callbacks, debounce_ms, state)

  return {
    autocmd_ids = ids,
    group = group,
    stop = function()
      state.stopped = true
      content_debounced.stop()
      scroll_debounced.stop()
      vim_api.nvim_del_augroup_by_id(group)
      if fs then
        fs.debounced.stop()
        if not fs.watcher:is_closing() then
          fs.watcher:close()
        end
      end
    end,
  }
end

function M.watch(bufnr, callbacks, debounce_ms, scroll_method)
  return M.new({ bufnr = bufnr, callbacks = callbacks, debounce_ms = debounce_ms, scroll_method = scroll_method })
end

return M
