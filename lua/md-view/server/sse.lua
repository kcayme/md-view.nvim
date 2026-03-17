local M = {}
M.__index = M

function M.new()
  return setmetatable({ clients = {}, last = {} }, M)
end

function M:add_client(client)
  table.insert(self.clients, client)
  for event_type, data in pairs(self.last) do
    local payload = "event: " .. event_type .. "\ndata: " .. vim.json.encode(data) .. "\n\n"
    pcall(function()
      client:write(payload)
    end)
  end
end

function M:remove_client(client)
  for i, c in ipairs(self.clients) do
    if c == client then
      table.remove(self.clients, i)
      if not client:is_closing() then
        client:close()
      end
      return
    end
  end
end

function M:push(event_type, data)
  if event_type ~= "close" then
    self.last[event_type] = data
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

function M:close_all()
  for _, client in ipairs(self.clients) do
    if not client:is_closing() then
      client:close()
    end
  end
  self.clients = {}
end

return M
