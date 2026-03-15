local sse = require("md-view.server.sse")

-- Minimal mock client for testing SSE logic without libuv
local function mock_client()
  local client = {
    _closing = false,
    _writes = {},
  }
  function client:is_closing()
    return self._closing
  end
  function client:close()
    self._closing = true
  end
  function client:write(data)
    if self._closing then
      error("write after close")
    end
    table.insert(self._writes, data)
  end
  return client
end

describe("sse", function()
  describe("new", function()
    it("creates an instance with empty clients", function()
      local s = sse.new()
      assert.is_not_nil(s)
      assert.are.same({}, s.clients)
    end)
  end)

  describe("add_client", function()
    it("adds a client", function()
      local s = sse.new()
      local c = mock_client()
      s:add_client(c)
      assert.are.equal(1, #s.clients)
    end)
  end)

  describe("remove_client", function()
    it("removes and closes a specific client", function()
      local s = sse.new()
      local c1 = mock_client()
      local c2 = mock_client()
      s:add_client(c1)
      s:add_client(c2)
      s:remove_client(c1)
      assert.are.equal(1, #s.clients)
      assert.are.equal(c2, s.clients[1])
      assert.is_true(c1._closing)
    end)

    it("does nothing for unknown client", function()
      local s = sse.new()
      local c1 = mock_client()
      local c2 = mock_client()
      s:add_client(c1)
      s:remove_client(c2)
      assert.are.equal(1, #s.clients)
      assert.is_false(c2._closing)
    end)
  end)

  describe("push", function()
    it("writes SSE-formatted payload to all clients", function()
      local s = sse.new()
      local c1 = mock_client()
      local c2 = mock_client()
      s:add_client(c1)
      s:add_client(c2)
      s:push("content", { content = "hello" })
      assert.are.equal(1, #c1._writes)
      assert.are.equal(1, #c2._writes)
      local payload = c1._writes[1]
      assert.truthy(payload:find("^event: content\n"))
      assert.truthy(payload:find("data: "))
      assert.truthy(payload:find("\n\n$"))
    end)

    it("removes dead clients that error on write", function()
      local s = sse.new()
      local good = mock_client()
      local dead = mock_client()
      -- override write to always error
      function dead:write()
        error("broken pipe")
      end
      s:add_client(dead)
      s:add_client(good)
      s:push("content", { content = "test" })
      assert.are.equal(1, #s.clients)
      assert.are.equal(good, s.clients[1])
      assert.is_true(dead._closing)
    end)

    it("handles push with no clients", function()
      local s = sse.new()
      -- should not error
      s:push("content", { content = "test" })
    end)
  end)

  describe("close_all", function()
    it("closes all clients and empties the list", function()
      local s = sse.new()
      local c1 = mock_client()
      local c2 = mock_client()
      s:add_client(c1)
      s:add_client(c2)
      s:close_all()
      assert.are.equal(0, #s.clients)
      assert.is_true(c1._closing)
      assert.is_true(c2._closing)
    end)

    it("handles already-closing clients gracefully", function()
      local s = sse.new()
      local c = mock_client()
      c._closing = true
      s:add_client(c)
      -- should not error
      s:close_all()
      assert.are.equal(0, #s.clients)
    end)
  end)
end)
