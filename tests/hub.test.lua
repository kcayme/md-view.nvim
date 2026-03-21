local hub = require("md-view.server.handlers.hub")

describe("hub", function()
  describe("new", function()
    it("creates empty state", function()
      local h = hub.new()
      assert.is_not_nil(h)
      assert.are.same({}, h.registry)
      assert.are.same({}, h.clients)
      assert.are.same({}, h.last)
      assert.is_nil(h.server)
    end)
  end)

  describe("resolve_label", function()
    it("filename preset returns basename", function()
      local h = hub.new()
      local label = h:resolve_label({ bufnr = 1, filename = "README.md", path = "/project/README.md" }, "filename")
      assert.are.equal("README.md", label)
    end)

    it("parent preset returns parent/filename", function()
      local h = hub.new()
      local label = h:resolve_label({ bufnr = 1, filename = "design.md", path = "/project/docs/design.md" }, "parent")
      assert.are.equal("docs/design.md", label)
    end)

    it("function preset is called with ctx and returns its result", function()
      local h = hub.new()
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
      local h = hub.new()
      local label = h:resolve_label({ bufnr = 1, filename = "foo.md", path = "/a/foo.md" }, "unknown")
      assert.are.equal("foo.md", label)
    end)
  end)

  describe("register / unregister", function()
    it("register adds entry with resolved label", function()
      local h = hub.new()
      h:register(5, "/project/docs/design.md", "filename")
      assert.is_not_nil(h.registry[5])
      assert.are.equal("design.md", h.registry[5].label)
      assert.are.equal("design.md", h.registry[5].title)
    end)

    it("unregister removes entry and evicts last replay state", function()
      local h = hub.new()
      h:register(5, "/project/docs/design.md", "filename")
      h.last[5] = { palette = { id = 5, css = "x" } }
      h:unregister(5)
      assert.is_nil(h.registry[5])
      assert.is_nil(h.last[5])
    end)

    it("unregister on unknown bufnr does not error", function()
      local h = hub.new()
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

describe("hub SSE", function()
  describe("push", function()
    it("broadcasts payload to all clients", function()
      local h = hub.new()
      local c1, c2 = mock_client(), mock_client()
      h:add_client(c1)
      h:add_client(c2)
      h:push("content", { id = 7, content = "# Hello" })
      assert.are.equal(1, #c1._writes)
      assert.are.equal(1, #c2._writes)
      assert.truthy(c1._writes[1]:find("^event: content\n"))
    end)

    it("stores replay state per bufnr for preview_added, palette and theme only", function()
      local h = hub.new()
      h:register(7, "/a/foo.md", "filename")
      h:push("preview_added", { id = 7, title = "foo.md", label = "foo.md" })
      h:push("palette", { id = 7, css = "body{}" })
      assert.is_not_nil(h.last[7])
      assert.is_not_nil(h.last[7].preview_added)
      assert.is_not_nil(h.last[7].palette)
      h:push("content", { id = 7, content = "x" })
      h:push("scroll", { id = 7, percent = 0.5 })
      assert.is_nil(h.last[7].content)
      assert.is_nil(h.last[7].scroll)
    end)

    it("removes dead clients on write failure", function()
      local h = hub.new()
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
    it("replays preview_added before palette and theme for each registered preview", function()
      local h = hub.new()
      h:register(3, "/a/a.md", "filename")
      h:push("preview_added", { id = 3, title = "a.md", label = "a.md" })
      h:push("palette", { id = 3, css = "p3" })
      local c = mock_client()
      h:add_client(c)
      assert.are.equal(2, #c._writes)
      assert.truthy(c._writes[1]:find("^event: preview_added\n"), "preview_added must be replayed first")
      assert.truthy(c._writes[2]:find("^event: palette\n"), "palette must follow preview_added")
    end)

    it("does NOT replay content or scroll", function()
      local h = hub.new()
      h:register(3, "/a/a.md", "filename")
      h:push("content", { id = 3, content = "x" })
      h:push("scroll", { id = 3, percent = 0.5 })
      local c = mock_client()
      h:add_client(c)
      assert.are.equal(0, #c._writes)
    end)

    it("does not replay evicted preview after unregister", function()
      local h = hub.new()
      h:register(3, "/a/a.md", "filename")
      h:push("palette", { id = 3, css = "old" })
      h:unregister(3)
      local c = mock_client()
      h:add_client(c)
      assert.are.equal(0, #c._writes)
    end)

    it("removes dead client when hub_palette replay write fails during add_client", function()
      local h = hub.new()
      h.last_hub_palette = { css = "body{}" }

      local good = mock_client()
      h:add_client(good)

      local dead = mock_client()
      function dead:write()
        error("broken pipe")
      end

      h:add_client(dead)

      assert.are.equal(1, #h.clients)
      assert.are.equal(good, h.clients[1])
      assert.is_true(dead._closing)
    end)

    it("removes dead client when per-preview replay write fails during add_client", function()
      local h = hub.new()
      h:register(3, "/a/a.md", "filename")
      h:push("preview_added", { id = 3, title = "a.md", label = "a.md" })

      local good = mock_client()
      h:add_client(good)

      local dead = mock_client()
      function dead:write()
        error("broken pipe")
      end

      h:add_client(dead)

      assert.are.equal(1, #h.clients)
      assert.are.equal(good, h.clients[1])
      assert.is_true(dead._closing)
    end)
  end)

  describe("remove_client", function()
    it("removes the client from the list", function()
      local h = hub.new()
      local c = mock_client()
      h:add_client(c)
      assert.are.equal(1, #h.clients)
      h:remove_client(c)
      assert.are.equal(0, #h.clients)
    end)

    it("closes the removed client if not already closing", function()
      local h = hub.new()
      local c = mock_client()
      h:add_client(c)
      h:remove_client(c)
      assert.is_true(c._closing)
    end)

    it("does not error when client is not in the list", function()
      local h = hub.new()
      local c = mock_client()
      assert.has_no.errors(function()
        h:remove_client(c)
      end)
    end)
  end)

  describe("close_all", function()
    it("closes all clients and clears list", function()
      local h = hub.new()
      local c1, c2 = mock_client(), mock_client()
      h:add_client(c1)
      h:add_client(c2)
      h:close_all()
      assert.are.equal(0, #h.clients)
      assert.is_true(c1._closing)
      assert.is_true(c2._closing)
    end)

    it("unregister alone does NOT close SSE clients", function()
      local h = hub.new()
      h:register(3, "/a/a.md", "filename")
      local c = mock_client()
      h:add_client(c)
      h:unregister(3)
      assert.is_false(c._closing)
      assert.are.equal(1, #h.clients)
    end)
  end)
end)

describe("handlers/hub routing", function()
  local router = require("md-view.server.router")

  local function mock_res()
    local r = {}
    r._status = nil
    r._ct = nil
    r._body = nil
    r._json_status = nil
    r._json_data = nil
    r._sse_instance = nil
    r._send_file_path = nil
    r._send_file_ct = nil
    r.send = function(status, ct, body)
      r._status = status
      r._ct = ct
      r._body = body
    end
    r.json = function(status, data)
      r._json_status = status
      r._json_data = data
    end
    r.sse_upgrade = function(inst)
      r._sse_instance = inst
    end
    r.send_file = function(filepath, ct)
      r._send_file_path = filepath
      r._send_file_ct = ct
    end
    return r
  end

  it("returns 400 for /content with no id", function()
    local h = hub.new()
    local res = mock_res()
    local req = { method = "GET", path = "/content", query = {}, params = {} }
    router.dispatch(hub.routes, req, res, { hub = h })
    assert.equals("400 Bad Request", res._status)
  end)

  it("returns 400 for /content with non-integer id", function()
    local h = hub.new()
    local res = mock_res()
    local req = { method = "GET", path = "/content", query = { id = "notanumber" }, params = {} }
    router.dispatch(hub.routes, req, res, { hub = h })
    assert.equals("400 Bad Request", res._status)
  end)

  it("returns 400 for /content with unregistered bufnr", function()
    local h = hub.new()
    local res = mock_res()
    local req = { method = "GET", path = "/content", query = { id = "9999" }, params = {} }
    router.dispatch(hub.routes, req, res, { hub = h })
    assert.equals("400 Bad Request", res._status)
  end)

  it("returns 404 for unknown paths", function()
    local h = hub.new()
    local res = mock_res()
    local req = { method = "GET", path = "/unknown", query = {}, params = {} }
    router.dispatch(hub.routes, req, res, { hub = h })
    assert.equals("404 Not Found", res._status)
  end)

  it("returns 400 for /file with no id param", function()
    local h = hub.new()
    local res = mock_res()
    local req = { method = "GET", path = "/file", query = { path = "/some/image.png" }, params = {} }
    router.dispatch(hub.routes, req, res, { hub = h })
    assert.equals("400 Bad Request", res._status)
  end)

  it("returns 400 for /file with unregistered bufnr", function()
    local h = hub.new()
    local res = mock_res()
    local req = { method = "GET", path = "/file", query = { id = "9999", path = "/some/image.png" }, params = {} }
    router.dispatch(hub.routes, req, res, { hub = h })
    assert.equals("400 Bad Request", res._status)
  end)

  it("returns 400 for /file with registered id but no path param", function()
    local h = hub.new()
    h:register(5, "/project/docs/notes.md", "filename")
    local res = mock_res()
    local req = { method = "GET", path = "/file", query = { id = "5" }, params = {} }
    router.dispatch(hub.routes, req, res, { hub = h })
    assert.equals("400 Bad Request", res._status)
  end)

  it("serve_sse calls res.sse_upgrade with ctx.hub", function()
    local h = hub.new()
    local res = mock_res()
    hub.serve_sse({}, res, { hub = h })
    assert.equals(h, res._sse_instance)
  end)

  it("exports a routes list with expected paths", function()
    assert.equals("table", type(hub.routes))
    assert.is_true(#hub.routes > 0)
    local paths = {}
    for _, r in ipairs(hub.routes) do
      paths[r.path] = true
    end
    assert.is_true(paths["/"])
    assert.is_true(paths["/sse"])
    assert.is_true(paths["/content"])
    assert.is_true(paths["/vendor/:file"])
    assert.is_true(paths["/file"])
  end)
end)
