local M = {}

local template = require("md-view.server.template")
local vendor = require("md-view.vendor")
local uv = vim.uv or vim.loop

local MEDIA_TYPES = {
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

-- Normalize an absolute path by resolving . and .. segments.
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
-- Returns the normalized absolute path, or nil for empty/nil input.
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

local function serve_static_file(client, filepath, content_type)
  uv.fs_open(filepath, "r", 438, function(err, fd)
    if err or not fd then
      vim.schedule(function()
        respond(client, "404 Not Found", "text/plain", "Not Found")
      end)
      return
    end
    uv.fs_fstat(fd, function(err2, stat)
      if err2 or not stat then
        uv.fs_close(fd, function() end)
        vim.schedule(function()
          respond(client, "404 Not Found", "text/plain", "Not Found")
        end)
        return
      end
      uv.fs_read(fd, stat.size, 0, function(err3, data)
        uv.fs_close(fd, function() end)
        vim.schedule(function()
          if err3 or not data then
            respond(client, "404 Not Found", "text/plain", "Not Found")
          else
            respond(client, "200 OK", content_type, data)
          end
        end)
      end)
    end)
  end)
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
  elseif path:match("^/vendor/[%w%.%-_]+$") then
    local filename = path:sub(9)
    local ext = filename:match("%.([^%.]+)$")
    local content_type = ext == "css" and "text/css" or "application/javascript"
    serve_static_file(client, vendor.vendor_dir() .. "/" .. filename, content_type)
  elseif path:match("^/file%?") then
    local qs = path:match("%?(.*)$") or ""
    local encoded = qs:match("^path=(.*)") or qs:match("[&]path=([^&]*)")
    local raw = encoded and url_decode(encoded) or nil
    local bufname = vim.api.nvim_buf_get_name(ctx.bufnr)
    local bufdir = vim.fn.fnamemodify(bufname, ":p:h")
    local abs = M.resolve_media_path(bufdir, raw)
    if not abs then
      respond(client, "400 Bad Request", "text/plain", "Bad Request")
      return
    end
    local ext = (abs:match("%.([^%.]+)$") or ""):lower()
    local content_type = MEDIA_TYPES[ext] or "application/octet-stream"
    serve_static_file(client, abs, content_type)
  else
    respond(client, "404 Not Found", "text/plain", "Not Found")
  end
end

return M
