local M = {}

local template = require("md-view.template")

local function respond(client, status, content_type, body)
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

local function respond_sse(client)
  local headers = "HTTP/1.1 200 OK\r\n"
    .. "Content-Type: text/event-stream\r\n"
    .. "Cache-Control: no-cache\r\n"
    .. "Connection: keep-alive\r\n\r\n"
  client:write(headers)
end

function M.handle(client, data, ctx)
  local method, path = data:match("^(%u+)%s+(%S+)")
  if not method then
    respond(client, "400 Bad Request", "text/plain", "Bad Request")
    return
  end

  if method ~= "GET" then
    respond(client, "405 Method Not Allowed", "text/plain", "Method Not Allowed")
    return
  end

  if path == "/" then
    local bufname = vim.api.nvim_buf_get_name(ctx.bufnr)
    local filename = vim.fn.fnamemodify(bufname, ":t")
    local html = template.render(ctx.config, filename)
    respond(client, "200 OK", "text/html", html)
  elseif path == "/content" then
    local lines = vim.api.nvim_buf_get_lines(ctx.bufnr, 0, -1, false)
    local content = table.concat(lines, "\n")
    local json = vim.json.encode({ content = content })
    respond(client, "200 OK", "application/json", json)
  elseif path == "/events" then
    respond_sse(client)
    ctx.sse:add_client(client)
  else
    respond(client, "404 Not Found", "text/plain", "Not Found")
  end
end

return M
