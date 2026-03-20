local M = {}

local uv = vim.uv or vim.loop

M.open_browser = function(url, browser)
  if browser then
    vim.fn.jobstart({ browser, url }, { detach = true })
    return
  end

  local cmd
  if vim.fn.has("mac") == 1 then
    cmd = { "open", url }
  elseif vim.fn.has("wsl") == 1 then
    cmd = { "wslview", url }
  elseif vim.fn.has("unix") == 1 then
    cmd = { "xdg-open", url }
  elseif vim.fn.has("win32") == 1 then
    cmd = { "cmd", "/c", "start", "", url }
  end

  if cmd then
    vim.fn.jobstart(cmd, { detach = true })
  else
    vim.notify("[md-view] Could not detect browser", vim.log.levels.ERROR)
  end
end

M.debounce = function(fn, ms)
  local timer = uv.new_timer()
  local wrapped = setmetatable({}, {
    __call = function(_, ...)
      local args = { ... }
      timer:stop()
      timer:start(ms, 0, function()
        timer:stop()
        vim.schedule(function()
          fn(unpack(args))
        end)
      end)
    end,
  })
  function wrapped.stop()
    timer:stop()
    if not timer:is_closing() then
      timer:close()
    end
  end
  return wrapped
end

M.table_len = function(input)
  local length = 0

  for _ in pairs(input) do
    length = length + 1
  end

  return length
end

M.notify = function(opts, msg, level)
  if not opts.silent then
    vim.notify(msg, level)
  end
end

return M
