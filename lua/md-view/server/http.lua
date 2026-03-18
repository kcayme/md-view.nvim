local M = {}

local uv = vim.uv or vim.loop

function M.respond(client, status, content_type, body)
  local res = "HTTP/1.1 "
    .. status
    .. "\r\nContent-Type: "
    .. content_type
    .. "\r\nContent-Length: "
    .. #body
    .. "\r\nConnection: close\r\n\r\n"
    .. body
  client:write(res, function()
    if not client:is_closing() then
      client:shutdown(function()
        if not client:is_closing() then
          client:close()
        end
      end)
    end
  end)
end

function M.respond_sse(client)
  local headers = "HTTP/1.1 200 OK\r\n"
    .. "Content-Type: text/event-stream\r\n"
    .. "Cache-Control: no-cache\r\n"
    .. "Connection: keep-alive\r\n\r\n"
  client:write(headers)
end

function M.serve_static_file(client, filepath, content_type)
  uv.fs_open(filepath, "r", 438, function(err, fd)
    if err or not fd then
      vim.schedule(function()
        M.respond(client, "404 Not Found", "text/plain", "Not Found")
      end)
      return
    end
    uv.fs_fstat(fd, function(err2, stat)
      if err2 or not stat then
        uv.fs_close(fd, function() end)
        vim.schedule(function()
          M.respond(client, "404 Not Found", "text/plain", "Not Found")
        end)
        return
      end
      uv.fs_read(fd, stat.size, 0, function(err3, data)
        uv.fs_close(fd, function() end)
        vim.schedule(function()
          if err3 or not data then
            M.respond(client, "500 Internal Server Error", "text/plain", "Read error")
            return
          end
          local res = "HTTP/1.1 200 OK\r\nContent-Type: "
            .. content_type
            .. "\r\nContent-Length: "
            .. #data
            .. "\r\nConnection: close\r\n\r\n"
            .. data
          client:write(res, function()
            if not client:is_closing() then
              client:shutdown(function()
                if not client:is_closing() then
                  client:close()
                end
              end)
            end
          end)
        end)
      end)
    end)
  end)
end

return M
