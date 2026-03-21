local M = {}
M.__index = M

---@class MdViewSse
---@field clients table[]
---@field last table<string, table>

-- Event types whose last value is replayed to newly-connected clients.
-- content: delivered fresh via on_client_added on every connect — replay would be redundant.
-- scroll: ephemeral position — replaying on reconnect causes a jarring viewport jump.
-- close: one-shot signal — must never be replayed to reconnecting clients.
local REPLAY_EVENTS = {
  palette = true,
  theme = true,
}

---@return MdViewSse
M.new = function()
  return setmetatable({ clients = {}, last = {}, on_client_added = nil }, M)
end

---@param client table
function M:add_client(client)
  table.insert(self.clients, client)

  for event_type, data in pairs(self.last) do
    local payload = "event: " .. event_type .. "\ndata: " .. vim.json.encode(data) .. "\n\n"

    pcall(function()
      client:write(payload)
    end)
  end

  if self.on_client_added then
    self.on_client_added(client)
  end
end

---@param client table
function M:remove_client(client)
  for idx, val in ipairs(self.clients) do
    if val == client then
      table.remove(self.clients, idx)

      if not client:is_closing() then
        client:close()
      end

      return
    end
  end
end

---@param event_type string
---@param data table
function M:push(event_type, data)
  local payload = "event: " .. event_type .. "\ndata: " .. vim.json.encode(data) .. "\n\n"
  local dead = {}

  if REPLAY_EVENTS[event_type] then
    self.last[event_type] = data
  end

  for i, client in ipairs(self.clients) do
    local ok = pcall(function()
      client:write(payload)
    end)

    if not ok then
      dead[#dead + 1] = i
    end
  end

  -- cleanup dead connections
  for i = #dead, 1, -1 do
    local client = self.clients[dead[i]]

    table.remove(self.clients, dead[i])

    if not client:is_closing() then
      client:close()
    end
  end
end

function M:close_all()
  for _, client in ipairs(self.clients) do
    if not client:is_closing() then
      client:close()
    end
  end

  self.clients = {}
  self.last = {}
end

return M
