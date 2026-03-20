local M = {}

local uv = vim.uv or vim.loop

local MAX_REQUEST_SIZE = 65536 -- 64KB
local REQUEST_TIMEOUT_MS = 10000 -- 10s

local function close_client(client)
  if not client:is_closing() then
    client:close()
  end
end

M.start = function(host, port, on_request)
  local server = uv.new_tcp()
  local ok, bind_err = server:bind(host, port)
  if not ok then
    vim.notify("[md-view] Failed to bind " .. host .. ":" .. port .. ": " .. tostring(bind_err), vim.log.levels.ERROR)
    return nil, 0
  end

  server:listen(128, function(err)
    if err then
      vim.schedule(function()
        vim.notify("[md-view] Server error: " .. err, vim.log.levels.ERROR)
      end)
      return
    end

    local client = uv.new_tcp()
    server:accept(client)

    local timeout = uv.new_timer()
    timeout:start(REQUEST_TIMEOUT_MS, 0, function()
      timeout:close()
      pcall(function()
        client:read_stop()
      end)
      close_client(client)
    end)

    local function cancel_timeout()
      if not timeout:is_closing() then
        timeout:close()
      end
    end

    local buf = ""
    client:read_start(function(read_err, data)
      if read_err or not data then
        cancel_timeout()
        close_client(client)
        return
      end

      buf = buf .. data

      if #buf > MAX_REQUEST_SIZE then
        cancel_timeout()
        client:read_stop()
        close_client(client)
        return
      end

      if buf:find("\r\n\r\n") then
        cancel_timeout()
        client:read_stop()
        vim.schedule(function()
          on_request(client, buf)
        end)
      end
    end)
  end)

  local addr = server:getsockname()
  return server, addr.port
end

M.stop = function(server)
  if server and not server:is_closing() then
    server:close()
  end
end

return M
