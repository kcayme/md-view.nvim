local M = {}
M.__index = M

local server = require("md-view.server.tcp")

local REPLAY_EVENTS = { palette = true, theme = true }

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

function M.new()
  return setmetatable({
    registry = {}, -- bufnr -> { title, label }
    clients = {}, -- SSE client list (shared across all previews)
    last = {}, -- last[bufnr][event_type] = data (per-preview replay state)
    server = nil,
    port = nil,
  }, M)
end

-- Resolve a tab label for the given ctx and tab_label config value.
-- ctx = { bufnr, filename, path }
function M:resolve_label(ctx, tab_label)
  if type(tab_label) == "function" then
    return tab_label(ctx)
  elseif tab_label == "filename" then
    return vim.fn.fnamemodify(ctx.path, ":t")
  elseif tab_label == "relative" then
    return vim.fn.fnamemodify(ctx.path, ":~:.")
  elseif tab_label == "parent" then
    local parent = vim.fn.fnamemodify(ctx.path, ":h:t")
    return parent .. "/" .. ctx.filename
  else
    return ctx.filename
  end
end

-- Register a preview. Registry entry is inserted synchronously so that
-- /content?id= is valid before preview_added is pushed.
-- Caller must push preview_added after calling register.
function M:register(bufnr, path, tab_label_cfg)
  local filename = vim.fn.fnamemodify(path, ":t")
  local ctx = { bufnr = bufnr, filename = filename, path = path }
  local label = self:resolve_label(ctx, tab_label_cfg)
  self.registry[bufnr] = { title = filename, label = label }
end

-- Unregister a preview. Evicts per-preview replay state.
-- Caller must push preview_removed before calling unregister.
function M:unregister(bufnr)
  self.registry[bufnr] = nil
  self.last[bufnr] = nil
end

function M:add_client(client)
  table.insert(self.clients, client)
  -- Replay last palette+theme per registered preview
  for bufnr, _ in pairs(self.registry) do
    local per_preview = self.last[bufnr]
    if per_preview then
      for event_type, data in pairs(per_preview) do
        if REPLAY_EVENTS[event_type] then
          local payload = "event: " .. event_type .. "\ndata: " .. vim.json.encode(data) .. "\n\n"
          pcall(function()
            client:write(payload)
          end)
        end
      end
    end
  end
end

function M:push(event_type, data)
  -- Store per-preview replay state for allowlisted event types
  if REPLAY_EVENTS[event_type] and data.id then
    local bufnr = data.id
    if self.registry[bufnr] then
      if not self.last[bufnr] then
        self.last[bufnr] = {}
      end
      self.last[bufnr][event_type] = data
    end
  end
  local payload = "event: " .. event_type .. "\ndata: " .. vim.json.encode(data) .. "\n\n"
  local dead = {}
  for i, client in ipairs(self.clients) do
    local ok = pcall(function()
      client:write(payload)
    end)
    if not ok then
      dead[#dead + 1] = i
    end
  end
  for i = #dead, 1, -1 do
    local client = self.clients[dead[i]]
    table.remove(self.clients, dead[i])
    if not client:is_closing() then
      client:close()
    end
  end
end

-- Close all SSE clients. Called only on full hub shutdown.
function M:close_all()
  for _, client in ipairs(self.clients) do
    if not client:is_closing() then
      client:close()
    end
  end
  self.clients = {}
end

function M:handle(client, data)
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
    local template = require("md-view.server.template")
    local config = require("md-view.config")
    local html = template.render_hub(config.options)
    respond(client, "200 OK", "text/html", html)
  elseif path == "/sse" then
    respond_sse(client)
    self:add_client(client)
    -- Detect disconnection; remove from client list without closing all clients
    client:read_start(function(read_err, _chunk)
      if read_err or not _chunk then
        vim.schedule(function()
          for i, c in ipairs(self.clients) do
            if c == client then
              table.remove(self.clients, i)
              if not client:is_closing() then
                client:close()
              end
              return
            end
          end
        end)
      end
    end)
  elseif path:match("^/content") then
    local qs = path:match("%?(.*)$") or ""
    local id_str = qs:match("^id=([^&]*)") or qs:match("[&]id=([^&]*)")
    local bufnr = id_str and tonumber(id_str)
    if not bufnr or not self.registry[bufnr] then
      respond(client, "400 Bad Request", "text/plain", "Bad Request")
      return
    end
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, "\n")
    respond(client, "200 OK", "application/json", vim.json.encode({ content = content }))
  else
    respond(client, "404 Not Found", "text/plain", "Not Found")
  end
end

-- Start the hub TCP server. Returns true on success, false on bind failure.
function M:start(host, port)
  local srv, p = server.start(host, port, function(client, data)
    self:handle(client, data)
  end)
  if not srv then
    return false
  end
  self.server = srv
  self.port = p
  return true
end

-- Idempotent stop: closes TCP server and all SSE clients.
function M:stop()
  if self.server then
    server.stop(self.server)
    self.server = nil
    self.port = nil
  end
  self:close_all()
end

return M
