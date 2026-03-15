local M = {}

local util = require("md-view.util")

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

  ids[#ids + 1] = vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      content_debounced()
    end,
  })

  ids[#ids + 1] = vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      scroll_debounced()
    end,
  })

  return {
    autocmd_ids = ids,
    group = group,
    stop = function()
      content_debounced.stop()
      scroll_debounced.stop()
      vim.api.nvim_del_augroup_by_id(group)
    end,
  }
end

return M
