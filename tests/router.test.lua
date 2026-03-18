describe("router", function()
  local router = require("md-view.server.router")

  -- ── resolve_media_path (unchanged behaviour) ──────────────────────────
  describe("resolve_media_path", function()
    local bufdir = "/home/user/docs"

    it("resolves a relative path within bufdir", function()
      assert.equals("/home/user/docs/image.png", router.resolve_media_path(bufdir, "image.png"))
    end)

    it("resolves a relative path with ./ prefix", function()
      assert.equals("/home/user/docs/assets/photo.jpg", router.resolve_media_path(bufdir, "./assets/photo.jpg"))
    end)

    it("resolves traversal paths to their normalised absolute path", function()
      assert.equals("/home/docs/demo/image.png", router.resolve_media_path(bufdir, "../../docs/demo/image.png"))
    end)

    it("allows absolute paths as-is", function()
      assert.equals("/tmp/image.png", router.resolve_media_path(bufdir, "/tmp/image.png"))
    end)

    it("returns nil for empty path", function()
      assert.is_nil(router.resolve_media_path(bufdir, ""))
      assert.is_nil(router.resolve_media_path(bufdir, nil))
    end)
  end)

  -- ── M.parse ───────────────────────────────────────────────────────────
  describe("parse", function()
    it("parses method and path from a GET request", function()
      local req = router.parse("GET /content HTTP/1.1\r\n\r\n")
      assert.equals("GET", req.method)
      assert.equals("/content", req.path)
    end)

    it("parses the root path", function()
      local req = router.parse("GET / HTTP/1.1\r\n\r\n")
      assert.equals("/", req.path)
    end)

    it("splits path and query string", function()
      local req = router.parse("GET /file?path=image.png HTTP/1.1\r\n\r\n")
      assert.equals("/file", req.path)
      assert.equals("image.png", req.query.path)
    end)

    it("parses multiple query params", function()
      local req = router.parse("GET /x?a=1&b=2 HTTP/1.1\r\n\r\n")
      assert.equals("1", req.query.a)
      assert.equals("2", req.query.b)
    end)

    it("url-decodes query values", function()
      local req = router.parse("GET /file?path=%2Ftmp%2Fimg.png HTTP/1.1\r\n\r\n")
      assert.equals("/tmp/img.png", req.query.path)
    end)

    it("returns empty query table when no query string", function()
      local req = router.parse("GET /content HTTP/1.1\r\n\r\n")
      assert.are.same({}, req.query)
    end)

    it("initialises params as empty table", function()
      local req = router.parse("GET /vendor/foo.js HTTP/1.1\r\n\r\n")
      assert.are.same({}, req.params)
    end)

    it("parses request headers as lowercase keys", function()
      local req = router.parse("GET / HTTP/1.1\r\nHost: localhost\r\nAccept: */*\r\n\r\n")
      assert.equals("localhost", req.headers["host"])
      assert.equals("*/*", req.headers["accept"])
    end)

    it("returns nil for malformed request line", function()
      assert.is_nil(router.parse("GARBAGE\r\n\r\n"))
    end)
  end)

  -- ── M.dispatch ────────────────────────────────────────────────────────
  describe("dispatch", function()
    local function mock_res()
      local r = { _status = nil, _body = nil }
      r.send = function(status, ct, body)
        r._status = status
        r._body = body
      end
      r.json = function(status, data)
        r._status = status
        r._data = data
      end
      return r
    end

    it("calls the matching handler", function()
      local called = false
      local routes = {
        {
          method = "GET",
          path = "/hello",
          handler = function()
            called = true
          end,
        },
      }
      local req = { method = "GET", path = "/hello", params = {} }
      router.dispatch(routes, req, mock_res(), {})
      assert.is_true(called)
    end)

    it("populates req.params for :param segments", function()
      local captured_params
      local routes = {
        {
          method = "GET",
          path = "/vendor/:file",
          handler = function(req)
            captured_params = req.params
          end,
        },
      }
      local req = { method = "GET", path = "/vendor/mermaid.min.js", params = {} }
      router.dispatch(routes, req, mock_res(), {})
      assert.equals("mermaid.min.js", captured_params.file)
    end)

    it("responds 404 when no route matches", function()
      local res = mock_res()
      router.dispatch({}, { method = "GET", path = "/unknown", params = {} }, res, {})
      assert.equals("404 Not Found", res._status)
    end)

    it("does not match wrong method", function()
      local called = false
      local routes = {
        {
          method = "POST",
          path = "/hello",
          handler = function()
            called = true
          end,
        },
      }
      local res = mock_res()
      router.dispatch(routes, { method = "GET", path = "/hello", params = {} }, res, {})
      assert.is_false(called)
      assert.equals("404 Not Found", res._status)
    end)

    it("matches the root path /", function()
      local called = false
      local routes = {
        {
          method = "GET",
          path = "/",
          handler = function()
            called = true
          end,
        },
      }
      router.dispatch(routes, { method = "GET", path = "/", params = {} }, mock_res(), {})
      assert.is_true(called)
    end)
  end)

  -- ── M.new ─────────────────────────────────────────────────────────────
  describe("new", function()
    local function mock_client()
      local c = { _writes = {}, _closing = false }
      function c:write(data, cb)
        table.insert(self._writes, data)
        if cb then
          cb()
        end
      end
      function c:shutdown(cb)
        if cb then
          cb()
        end
      end
      function c:is_closing()
        return self._closing
      end
      function c:close()
        self._closing = true
      end
      return c
    end

    it("returns a callable closure", function()
      assert.equals("function", type(router.new({}, {})))
    end)

    it("responds 400 for a malformed request", function()
      local c = mock_client()
      local handler = router.new({}, {})
      handler(c, "GARBAGE\r\n\r\n")
      assert.is_true(#c._writes > 0)
      assert.is_not_nil(c._writes[1]:find("400 Bad Request"))
    end)

    it("responds 405 for a non-GET method", function()
      local c = mock_client()
      local handler = router.new({}, {})
      handler(c, "POST /content HTTP/1.1\r\n\r\n")
      assert.is_true(#c._writes > 0)
      assert.is_not_nil(c._writes[1]:find("405 Method Not Allowed"))
    end)
  end)
end)
