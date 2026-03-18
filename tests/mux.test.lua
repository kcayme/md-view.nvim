local mux = require("md-view.server.mux")

describe("mux", function()
  describe("new", function()
    it("creates empty state", function()
      local h = mux.new()
      assert.is_not_nil(h)
      assert.are.same({}, h.registry)
      assert.are.same({}, h.clients)
      assert.are.same({}, h.last)
      assert.is_nil(h.server)
    end)
  end)

  describe("resolve_label", function()
    it("filename preset returns basename", function()
      local h = mux.new()
      local label = h:resolve_label({ bufnr = 1, filename = "README.md", path = "/project/README.md" }, "filename")
      assert.are.equal("README.md", label)
    end)

    it("parent preset returns parent/filename", function()
      local h = mux.new()
      local label = h:resolve_label({ bufnr = 1, filename = "design.md", path = "/project/docs/design.md" }, "parent")
      assert.are.equal("docs/design.md", label)
    end)

    it("function preset is called with ctx and returns its result", function()
      local h = mux.new()
      local received = nil
      local fn = function(ctx)
        received = ctx
        return "custom"
      end
      local label = h:resolve_label({ bufnr = 7, filename = "foo.md", path = "/a/b/foo.md" }, fn)
      assert.are.equal("custom", label)
      assert.are.equal(7, received.bufnr)
      assert.are.equal("foo.md", received.filename)
    end)

    it("unknown string preset falls back to filename", function()
      local h = mux.new()
      local label = h:resolve_label({ bufnr = 1, filename = "foo.md", path = "/a/foo.md" }, "unknown")
      assert.are.equal("foo.md", label)
    end)
  end)

  describe("register / unregister", function()
    it("register adds entry with resolved label", function()
      local h = mux.new()
      h:register(5, "/project/docs/design.md", "filename")
      assert.is_not_nil(h.registry[5])
      assert.are.equal("design.md", h.registry[5].label)
      assert.are.equal("design.md", h.registry[5].title)
    end)

    it("unregister removes entry and evicts last replay state", function()
      local h = mux.new()
      h:register(5, "/project/docs/design.md", "filename")
      h.last[5] = { palette = { id = 5, css = "x" } }
      h:unregister(5)
      assert.is_nil(h.registry[5])
      assert.is_nil(h.last[5])
    end)

    it("unregister on unknown bufnr does not error", function()
      local h = mux.new()
      assert.has_no.errors(function()
        h:unregister(99)
      end)
    end)
  end)
end)

local function mock_client()
  local c = { _closing = false, _writes = {} }
  function c:is_closing()
    return self._closing
  end
  function c:close()
    self._closing = true
  end
  function c:write(data)
    if self._closing then
      error("write after close")
    end
    table.insert(self._writes, data)
  end
  return c
end

describe("mux SSE", function()
  describe("push", function()
    it("broadcasts payload to all clients", function()
      local h = mux.new()
      local c1, c2 = mock_client(), mock_client()
      h:add_client(c1)
      h:add_client(c2)
      h:push("content", { id = 7, content = "# Hello" })
      assert.are.equal(1, #c1._writes)
      assert.are.equal(1, #c2._writes)
      assert.truthy(c1._writes[1]:find("^event: content\n"))
    end)

    it("stores replay state per bufnr for palette and theme only", function()
      local h = mux.new()
      h:register(7, "/a/foo.md", "filename")
      h:push("palette", { id = 7, css = "body{}" })
      assert.is_not_nil(h.last[7])
      assert.is_not_nil(h.last[7].palette)
      h:push("content", { id = 7, content = "x" })
      h:push("scroll", { id = 7, percent = 0.5 })
      assert.is_nil(h.last[7].content)
      assert.is_nil(h.last[7].scroll)
    end)

    it("removes dead clients on write failure", function()
      local h = mux.new()
      local dead = mock_client()
      function dead:write()
        error("broken pipe")
      end
      local good = mock_client()
      h:add_client(dead)
      h:add_client(good)
      h:push("content", { id = 1, content = "x" })
      assert.are.equal(1, #h.clients)
      assert.are.equal(good, h.clients[1])
      assert.is_true(dead._closing)
    end)
  end)

  describe("add_client replay", function()
    it("replays last palette and theme for each registered preview", function()
      local h = mux.new()
      h:register(3, "/a/a.md", "filename")
      h:register(5, "/b/b.md", "filename")
      h:push("palette", { id = 3, css = "p3" })
      h:push("theme", { id = 5, css = "t5" })
      local c = mock_client()
      h:add_client(c)
      assert.are.equal(2, #c._writes)
    end)

    it("does NOT replay content or scroll", function()
      local h = mux.new()
      h:register(3, "/a/a.md", "filename")
      h:push("content", { id = 3, content = "x" })
      h:push("scroll", { id = 3, percent = 0.5 })
      local c = mock_client()
      h:add_client(c)
      assert.are.equal(0, #c._writes)
    end)

    it("does not replay evicted preview after unregister", function()
      local h = mux.new()
      h:register(3, "/a/a.md", "filename")
      h:push("palette", { id = 3, css = "old" })
      h:unregister(3)
      local c = mock_client()
      h:add_client(c)
      assert.are.equal(0, #c._writes)
    end)
  end)

  describe("close_all", function()
    it("closes all clients and clears list", function()
      local h = mux.new()
      local c1, c2 = mock_client(), mock_client()
      h:add_client(c1)
      h:add_client(c2)
      h:close_all()
      assert.are.equal(0, #h.clients)
      assert.is_true(c1._closing)
      assert.is_true(c2._closing)
    end)

    it("unregister alone does NOT close SSE clients", function()
      local h = mux.new()
      h:register(3, "/a/a.md", "filename")
      local c = mock_client()
      h:add_client(c)
      h:unregister(3)
      assert.is_false(c._closing)
      assert.are.equal(1, #h.clients)
    end)
  end)
end)

describe("mux server routing", function()
  local function fake_client()
    local c = {
      _writes = {},
      _closed = false,
      is_closing = function(self)
        return self._closed
      end,
      write = function(self, data, cb)
        table.insert(self._writes, data)
        if cb then
          cb()
        end
      end,
      shutdown = function(self, cb)
        if cb then
          cb()
        end
      end,
      close = function(self)
        self._closed = true
      end,
      read_start = function() end,
    }
    return c
  end

  it("returns 400 for /content with no id", function()
    local h = mux.new()
    local c = fake_client()
    h:handle(c, "GET /content HTTP/1.1\r\n\r\n")
    assert.truthy(c._writes[1] and c._writes[1]:find("400"))
  end)

  it("returns 400 for /content with non-integer id", function()
    local h = mux.new()
    local c = fake_client()
    h:handle(c, "GET /content?id=notanumber HTTP/1.1\r\n\r\n")
    assert.truthy(c._writes[1] and c._writes[1]:find("400"))
  end)

  it("returns 400 for /content with unregistered bufnr", function()
    local h = mux.new()
    local c = fake_client()
    h:handle(c, "GET /content?id=9999 HTTP/1.1\r\n\r\n")
    assert.truthy(c._writes[1] and c._writes[1]:find("400"))
  end)

  it("returns 405 for non-GET methods", function()
    local h = mux.new()
    local c = fake_client()
    h:handle(c, "POST / HTTP/1.1\r\n\r\n")
    assert.truthy(c._writes[1] and c._writes[1]:find("405"))
  end)

  it("returns 404 for unknown paths", function()
    local h = mux.new()
    local c = fake_client()
    h:handle(c, "GET /unknown HTTP/1.1\r\n\r\n")
    assert.truthy(c._writes[1] and c._writes[1]:find("404"))
  end)
end)
