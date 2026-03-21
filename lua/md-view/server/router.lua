local M = {}

local uv = vim.uv or vim.loop

---@class MdViewRequest
---@field method string
---@field path string
---@field query table<string, string>
---@field params table<string, string>
---@field body string
---@field headers table<string, string>

---@class MdViewResponse
---@field send fun(status: string, content_type: string, body: string)
---@field json fun(status: string, data: table)
---@field send_file fun(filepath: string, content_type: string)
---@field sse_upgrade fun(sse_instance: MdViewSse)

---@class MdViewRoute
---@field method string
---@field path string
---@field handler fun(req: MdViewRequest, res: MdViewResponse, ctx: table)

-- Exposed so handlers/direct.lua can look up content types without duplicating.
M.MEDIA_TYPES = {
  png = "image/png",
  jpg = "image/jpeg",
  jpeg = "image/jpeg",
  gif = "image/gif",
  svg = "image/svg+xml",
  webp = "image/webp",
  avif = "image/avif",
  bmp = "image/bmp",
  ico = "image/x-icon",
  mp4 = "video/mp4",
  webm = "video/webm",
  mov = "video/quicktime",
  ogg = "video/ogg",
  ogv = "video/ogg",
  mp3 = "audio/mpeg",
  wav = "audio/wav",
  flac = "audio/flac",
  oga = "audio/ogg",
}

local function url_decode(s)
  return (s:gsub("%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end))
end

local function normalize_abs(path)
  local parts = {}

  for seg in path:gmatch("[^/]+") do
    if seg == ".." then
      table.remove(parts)
    elseif seg ~= "." then
      table.insert(parts, seg)
    end
  end

  return "/" .. table.concat(parts, "/")
end

-- Resolve a raw path (from the /file?path= query param) against bufdir.
-- Returns the normalised absolute path, or nil for empty/nil input.
-- No traversal restriction: the server is loopback-only and the user already
-- has full filesystem access; blocking ../ would prevent valid relative paths.
---@param bufdir string
---@param raw string|nil
---@return string|nil
M.resolve_media_path = function(bufdir, raw)
  if not raw or raw == "" then
    return nil
  end

  if raw:sub(1, 1) == "/" then
    return normalize_abs(raw)
  end

  return normalize_abs(bufdir .. "/" .. raw)
end

-- ── Internal write helpers ──────────────────────────────────────────────

local function raw_respond(client, status, content_type, body)
  local msg = "HTTP/1.1 "
    .. status
    .. "\r\nContent-Type: "
    .. content_type
    .. "\r\nContent-Length: "
    .. #body
    .. "\r\nConnection: close\r\n\r\n"
    .. body

  client:write(msg, function()
    if not client:is_closing() then
      client:shutdown(function()
        if not client:is_closing() then
          client:close()
        end
      end)
    end
  end)
end

local function raw_serve_file(client, filepath, content_type)
  uv.fs_open(filepath, "r", 438, function(err, fd)
    if err or not fd then
      vim.schedule(function()
        raw_respond(client, "404 Not Found", "text/plain", "Not Found")
      end)
      return
    end
    uv.fs_fstat(fd, function(err2, stat)
      if err2 or not stat then
        uv.fs_close(fd, function() end)
        vim.schedule(function()
          raw_respond(client, "404 Not Found", "text/plain", "Not Found")
        end)
        return
      end
      uv.fs_read(fd, stat.size, 0, function(err3, data)
        uv.fs_close(fd, function() end)
        vim.schedule(function()
          if err3 or not data then
            raw_respond(client, "404 Not Found", "text/plain", "Not Found")
          else
            raw_respond(client, "200 OK", content_type, data)
          end
        end)
      end)
    end)
  end)
end

-- ── Public infrastructure ───────────────────────────────────────────────

-- Build a res helper that wraps a raw libuv client.
-- Handlers call res methods; the client handle never leaves router.lua.
---@param client table
---@return MdViewResponse
M.build_res = function(client)
  return {
    -- Send a plain HTTP response and close the connection.
    send = function(status, content_type, body)
      raw_respond(client, status, content_type, body)
    end,
    -- Encode data as JSON, set Content-Type, and close the connection.
    json = function(status, data)
      raw_respond(client, status, "application/json", vim.json.encode(data))
    end,
    -- Serve a file from disk asynchronously.
    send_file = function(filepath, content_type)
      raw_serve_file(client, filepath, content_type)
    end,
    -- Upgrade to SSE: write headers, register client with sse_instance, and
    -- re-enable reads so that a browser disconnect removes the stale client.
    sse_upgrade = function(sse_instance)
      local headers = "HTTP/1.1 200 OK\r\n"
        .. "Content-Type: text/event-stream\r\n"
        .. "Cache-Control: no-cache\r\n"
        .. "Connection: keep-alive\r\n\r\n"

      client:write(headers)
      sse_instance:add_client(client)
      -- tcp.lua calls read_stop() before routing; restart reading so we detect
      -- when the browser tab closes (EOF) and remove the stale SSE client.
      client:read_start(function(read_err, _data)
        if read_err or not _data then
          vim.schedule(function()
            sse_instance:remove_client(client)
          end)
        end
      end)
    end,
  }
end

-- Parse a raw HTTP request buffer into a req table.
-- Populates: method, path, query, params (empty — filled by dispatch), body, headers.
---@param buf string
---@return MdViewRequest|nil
M.parse = function(buf)
  local query = {}
  local headers = {}

  local method, path_and_query = buf:match("^(%u+)%s+(%S+)")
  if not method then
    return nil
  end

  local path, qs = path_and_query:match("^([^?]+)%?(.*)$")
  if not path then
    path = path_and_query
    qs = ""
  end

  for key, val in qs:gmatch("([^&=]+)=([^&]*)") do
    query[url_decode(key)] = url_decode(val)
  end

  local header_section = buf:match("^[^\r\n]+\r\n(.-)\r\n\r\n")
  if header_section then
    for line in header_section:gmatch("[^\r\n]+") do
      local k, v = line:match("^([%w%-]+):%s*(.+)$")
      if k then
        headers[k:lower()] = v
      end
    end
  end

  return {
    method = method,
    path = path,
    query = query,
    params = {},
    body = buf:match("\r\n\r\n(.*)$") or "",
    headers = headers,
  }
end

-- Match a route pattern (supporting :param segments) against a request path.
-- Returns a params table on match, nil otherwise.
local function match_path(pattern, path)
  local params = {}
  local pat_segs, path_segs = {}, {}

  for seg in pattern:gmatch("[^/]+") do
    table.insert(pat_segs, seg)
  end

  for seg in path:gmatch("[^/]+") do
    table.insert(path_segs, seg)
  end

  if #pat_segs ~= #path_segs then
    return nil
  end

  for i, pseg in ipairs(pat_segs) do
    if pseg:sub(1, 1) == ":" then
      params[pseg:sub(2)] = path_segs[i]
    elseif pseg ~= path_segs[i] then
      return nil
    end
  end

  return params
end

-- Dispatch req through a route table, populating req.params on match.
-- Responds 404 if no route matches.
---@param routes MdViewRoute[]
---@param req MdViewRequest
---@param res MdViewResponse
---@param ctx table
M.dispatch = function(routes, req, res, ctx)
  for _, route in ipairs(routes) do
    if route.method == req.method then
      local params = match_path(route.path, req.path)

      if params then
        req.params = params
        route.handler(req, res, ctx)
        return
      end
    end
  end

  res.send("404 Not Found", "text/plain", "Not Found")
end

-- Factory: returns an on_request(client, buf) closure for tcp.start().
-- Binds the route table and context at server creation time.
---@param routes MdViewRoute[]
---@param ctx table
---@return fun(client: table, buf: string)
M.new = function(routes, ctx)
  return function(client, buf)
    local req = M.parse(buf)
    local res = M.build_res(client)

    if not req then
      res.send("400 Bad Request", "text/plain", "Bad Request")

      return
    end

    if req.method ~= "GET" then
      res.send("405 Method Not Allowed", "text/plain", "Method Not Allowed")

      return
    end

    M.dispatch(routes, req, res, ctx)
  end
end

return M
