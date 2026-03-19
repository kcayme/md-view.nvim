local M = {}

local util = require("md-view.util")

---@class MdViewBufferDeps
---@field uv? table
---@field vim_api? table
---@field debounce? fun(fn: function, ms: integer): table

---@class MdViewBufferInstance
---@field watch fun(bufnr: integer, callbacks: table, debounce_ms: integer, scroll_method?: string): table

---@param deps? MdViewBufferDeps
---@return MdViewBufferInstance
function M.new(deps)
  deps = deps or {}

  local uv = deps.uv or (vim.uv or vim.loop)

  local vim_api
  if deps.vim_api then
    vim_api = deps.vim_api
  else
    -- vim.api is the base; bufwinid and schedule are injected on top.
    -- Neither key exists in vim.api today so there is no collision.
    -- "keep" means our custom keys (bufwinid, schedule, split) win if vim.api ever gains
    -- keys with the same names in a future Neovim version.
    vim_api = vim.tbl_extend("keep", {
      bufwinid = vim.fn.bufwinid,
      schedule = vim.schedule,
      split = vim.split,
    }, vim.api)
  end

  local debounce = deps.debounce or util.debounce

  local instance = {}

  function instance.watch(bufnr, callbacks, debounce_ms, scroll_method)
    local content_debounced = debounce(function()
      if not vim_api.nvim_buf_is_valid(bufnr) then
        return
      end
      local lines = vim_api.nvim_buf_get_lines(bufnr, 0, -1, false)
      callbacks.on_content(lines)
    end, debounce_ms)

    local scroll_debounced = debounce(function()
      if not vim_api.nvim_buf_is_valid(bufnr) then
        return
      end
      local win = vim_api.bufwinid(bufnr)
      if win == -1 then
        return
      end
      local cursor = vim_api.nvim_win_get_cursor(win)
      if scroll_method == "cursor" then
        callbacks.on_scroll({ line = cursor[1] - 1 })
      else
        local total = vim_api.nvim_buf_line_count(bufnr)
        callbacks.on_scroll({ percent = (cursor[1] - 1) / math.max(total - 1, 1) })
      end
    end, 50)

    local group = vim_api.nvim_create_augroup("md_view_" .. bufnr, { clear = true })

    local ids = {}

    -- Tracks whether the last on-disk change was written by Neovim itself (BufWritePost).
    -- Used to suppress the redundant fs_watch push that would otherwise double-fire on :w.
    local wrote_from_nvim = false

    ids[#ids + 1] = vim_api.nvim_create_autocmd(
      { "TextChanged", "TextChangedI", "BufWritePost", "BufReadPost", "FileChangedShellPost" },
      {
        group = group,
        buffer = bufnr,
        callback = function(ev)
          if ev.event == "BufWritePost" then
            wrote_from_nvim = true
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

    -- Watch the file on disk for external changes (e.g. an AI agent editing while Neovim is
    -- unfocused). Reads content directly from disk so the preview stays live without requiring
    -- a checktime or buffer reload.
    local filepath = vim_api.nvim_buf_get_name(bufnr)
    local fs_watcher = nil
    local file_content_debounced = nil
    local watcher_stopped = false

    if filepath and filepath ~= "" then
      file_content_debounced = debounce(function()
        if wrote_from_nvim then
          wrote_from_nvim = false
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

      -- Rename-based writers (Claude Code, sed -i, rsync, etc.) atomically replace the
      -- file, which kills the inotify watch on the old inode. Detect the rename event and
      -- restart the watcher on the new file at the same path so live updates keep working.
      local handle = uv.new_fs_event()
      local function start_watching()
        if watcher_stopped then
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
      if ok then
        fs_watcher = handle
      else
        handle:close()
        file_content_debounced.stop()
        file_content_debounced = nil
      end
    end

    return {
      autocmd_ids = ids,
      group = group,
      stop = function()
        watcher_stopped = true
        content_debounced.stop()
        scroll_debounced.stop()
        vim_api.nvim_del_augroup_by_id(group)
        if file_content_debounced then
          file_content_debounced.stop()
        end
        if fs_watcher and not fs_watcher:is_closing() then
          fs_watcher:close()
        end
      end,
    }
  end

  return instance
end

-- Convenience alias: forwards to a fresh M.new() instance with production defaults.
-- Each call is independent — no shared state across invocations.
-- Creates a fresh M.new() instance per call; the instance itself has no state,
-- only the returned watcher does.
function M.watch(bufnr, callbacks, debounce_ms, scroll_method)
  return M.new().watch(bufnr, callbacks, debounce_ms, scroll_method)
end

return M
