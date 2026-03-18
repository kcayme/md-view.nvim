local M = {}

local uv = vim.uv or vim.loop

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
function M.resolve_media_path(bufdir, raw)
  if not raw or raw == "" then
    return nil
  end
  if raw:sub(1, 1) == "/" then
    return normalize_abs(raw)
  else
    return normalize_abs(bufdir .. "/" .. raw)
  end
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
function M.build_res(client)
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
function M.parse(buf)
  local method, path_and_query = buf:match("^(%u+)%s+(%S+)")
  if not method then
    return nil
  end

  local path, qs = path_and_query:match("^([^?]+)%?(.*)$")
  if not path then
    path = path_and_query
    qs = ""
  end

  local query = {}
  for key, val in qs:gmatch("([^&=]+)=([^&]*)") do
    query[url_decode(key)] = url_decode(val)
  end

  local headers = {}
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
function M.dispatch(routes, req, res, ctx)
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
function M.new(routes, ctx)
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

-- Compatibility shim: kept until preview.lua is updated in Task 3.
-- Uses the original inline implementation so it has no dependency on
-- handlers/direct.lua, which is not created until Task 2.
-- DO NOT use in new code.
function M.handle(client, data, ctx)
  local template_mod = require("md-view.server.template")
  local vendor_mod = require("md-view.vendor")
  local method, path = data:match("^(%u+)%s+(%S+)")
  if not method then
    raw_respond(client, "400 Bad Request", "text/plain", "Bad Request")
    return
  end
  if method ~= "GET" then
    raw_respond(client, "405 Method Not Allowed", "text/plain", "Method Not Allowed")
    return
  end
  if path == "/" then
    local bufname = vim.api.nvim_buf_get_name(ctx.bufnr)
    local filename = vim.fn.fnamemodify(bufname, ":t")
    raw_respond(client, "200 OK", "text/html", template_mod.render(ctx.config, filename))
  elseif path == "/content" then
    local lines = vim.api.nvim_buf_get_lines(ctx.bufnr, 0, -1, false)
    raw_respond(client, "200 OK", "application/json", vim.json.encode({ content = table.concat(lines, "\n") }))
  elseif path == "/events" then
    local headers = "HTTP/1.1 200 OK\r\n"
      .. "Content-Type: text/event-stream\r\n"
      .. "Cache-Control: no-cache\r\n"
      .. "Connection: keep-alive\r\n\r\n"
    client:write(headers)
    ctx.sse:add_client(client)
    client:read_start(function(read_err, _data)
      if read_err or not _data then
        vim.schedule(function()
          ctx.sse:remove_client(client)
        end)
      end
    end)
  elseif path:match("^/vendor/[%w%.%-_]+$") then
    local filename = path:sub(9)
    local ext = filename:match("%.([^%.]+)$")
    raw_serve_file(
      client,
      vendor_mod.vendor_dir() .. "/" .. filename,
      ext == "css" and "text/css" or "application/javascript"
    )
  elseif path:match("^/file%?") then
    local qs = path:match("%?(.*)$") or ""
    local encoded = qs:match("^path=(.*)") or qs:match("[&]path=([^&]*)")
    local raw = encoded and encoded:gsub("%%(%x%x)", function(h)
      return string.char(tonumber(h, 16))
    end) or nil
    local bufname = vim.api.nvim_buf_get_name(ctx.bufnr)
    local bufdir = vim.fn.fnamemodify(bufname, ":p:h")
    local abs = M.resolve_media_path(bufdir, raw)
    if not abs then
      raw_respond(client, "400 Bad Request", "text/plain", "Bad Request")
      return
    end
    local fext = (abs:match("%.([^%.]+)$") or ""):lower()
    raw_serve_file(client, abs, M.MEDIA_TYPES[fext] or "application/octet-stream")
  else
    raw_respond(client, "404 Not Found", "text/plain", "Not Found")
  end
end

return M
