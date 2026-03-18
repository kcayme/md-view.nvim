local M = {}

local template = require("md-view.server.template")
local vendor = require("md-view.vendor")
local http = require("md-view.server.http")

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

function M.handle(client, data, ctx)
  local method, path = data:match("^(%u+)%s+(%S+)")
  if not method then
    http.respond(client, "400 Bad Request", "text/plain", "Bad Request")
    return
  end

  if method ~= "GET" then
    http.respond(client, "405 Method Not Allowed", "text/plain", "Method Not Allowed")
    return
  end

  if path == "/favicon.ico" then
    http.respond(client, "204 No Content", "text/plain", "")
  elseif path == "/" then
    local bufname = vim.api.nvim_buf_get_name(ctx.bufnr)
    local filename = vim.fn.fnamemodify(bufname, ":t")
    local html = template.render(ctx.config, filename)
    http.respond(client, "200 OK", "text/html", html)
  elseif path == "/content" then
    local lines = vim.api.nvim_buf_get_lines(ctx.bufnr, 0, -1, false)
    local content = table.concat(lines, "\n")
    local json = vim.json.encode({ content = content })
    http.respond(client, "200 OK", "application/json", json)
  elseif path == "/events" then
    http.respond_sse(client)
    ctx.sse:add_client(client)
    -- tcp.lua calls read_stop() before routing; restart reading so we detect
    -- when the browser tab closes (EOF) and remove the stale SSE client.
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
    local content_type = ext == "css" and "text/css" or "application/javascript"
    http.serve_static_file(client, vendor.vendor_dir() .. "/" .. filename, content_type)
  elseif path:match("^/file%?") then
    local qs = path:match("%?(.*)$") or ""
    local encoded = qs:match("^path=(.*)") or qs:match("[&]path=([^&]*)")
    local raw = encoded and url_decode(encoded) or nil
    local bufname = vim.api.nvim_buf_get_name(ctx.bufnr)
    local bufdir = vim.fn.fnamemodify(bufname, ":p:h")
    local abs = M.resolve_media_path(bufdir, raw)
    if not abs then
      http.respond(client, "400 Bad Request", "text/plain", "Bad Request")
      return
    end
    local ext = (abs:match("%.([^%.]+)$") or ""):lower()
    local content_type = MEDIA_TYPES[ext] or "application/octet-stream"
    http.serve_static_file(client, abs, content_type)
  else
    http.respond(client, "404 Not Found", "text/plain", "Not Found")
  end
end

return M
