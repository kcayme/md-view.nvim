local M = {}

local util = require("md-view.util")
local uv = vim.uv or vim.loop

function M.watch(bufnr, callbacks, debounce_ms, scroll_method)
  local content_debounced = util.debounce(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    callbacks.on_content(lines)
  end, debounce_ms)

  local scroll_debounced = util.debounce(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    local win = vim.fn.bufwinid(bufnr)
    if win == -1 then
      return
    end
    local cursor = vim.api.nvim_win_get_cursor(win)
    if scroll_method == "cursor" then
      callbacks.on_scroll({ line = cursor[1] - 1 })
    else
      local total = vim.api.nvim_buf_line_count(bufnr)
      callbacks.on_scroll({ percent = (cursor[1] - 1) / math.max(total - 1, 1) })
    end
  end, 50)

  local group = vim.api.nvim_create_augroup("md_view_" .. bufnr, { clear = true })

  local ids = {}

  ids[#ids + 1] = vim.api.nvim_create_autocmd(
    { "TextChanged", "TextChangedI", "BufWritePost", "BufReadPost", "FileChangedShellPost" },
    {
      group = group,
      buffer = bufnr,
      callback = function()
        content_debounced()
      end,
    }
  )

  ids[#ids + 1] = vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      scroll_debounced()
    end,
  })

  -- Watch the file on disk for external changes (e.g. an AI agent editing while Neovim is
  -- unfocused). Reads content directly from disk so the preview stays live without requiring
  -- a checktime or buffer reload.
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local fs_watcher = nil
  local file_content_debounced = nil

  if filepath and filepath ~= "" then
    file_content_debounced = util.debounce(function()
      uv.fs_open(filepath, "r", 292, function(err, fd)
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
            vim.schedule(function()
              if vim.api.nvim_buf_is_valid(bufnr) then
                callbacks.on_content(vim.split(data, "\n", { plain = true }))
              end
            end)
          end)
        end)
      end)
    end, debounce_ms)

    local handle = uv.new_fs_event()
    local ok = pcall(function()
      handle:start(filepath, {}, function(ferr, _name, _events)
        if ferr then
          return
        end
        file_content_debounced()
      end)
    end)
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
      content_debounced.stop()
      scroll_debounced.stop()
      vim.api.nvim_del_augroup_by_id(group)
      if file_content_debounced then
        file_content_debounced.stop()
      end
      if fs_watcher and not fs_watcher:is_closing() then
        fs_watcher:close()
      end
    end,
  }
end

return M
