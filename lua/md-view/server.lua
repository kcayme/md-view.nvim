local M = {}

local uv = vim.uv or vim.loop

function M.start(host, port, on_request)
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

    local buf = ""
    client:read_start(function(read_err, data)
      if read_err or not data then
        if not client:is_closing() then
          client:close()
        end
        return
      end

      buf = buf .. data
      if buf:find("\r\n\r\n") then
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

function M.stop(server)
  if server and not server:is_closing() then
    server:close()
  end
end

return M
