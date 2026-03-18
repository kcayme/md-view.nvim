describe("handlers/direct", function()
  local direct = require("md-view.server.handlers.direct")
  local router = require("md-view.server.router")

  -- Helper: build a mock res that records calls.
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
    r.sse_upgrade = function(sse_instance)
      r._sse_instance = sse_instance
    end
    r.send_file = function(filepath, ct)
      r._send_file_path = filepath
      r._send_file_ct = ct
    end
    return r
  end

  -- Helper: build a minimal ctx for per-preview handlers.
  local function mock_ctx(bufnr, sse_instance)
    local config = require("md-view.config")
    config.setup({})
    return {
      bufnr = bufnr,
      config = config.options,
      sse = sse_instance or {},
    }
  end

  -- ── M.routes table ────────────────────────────────────────────────────
  describe("routes", function()
    it("exports a routes list", function()
      assert.equals("table", type(direct.routes))
      assert.is_true(#direct.routes > 0)
    end)

    it("has a handler for GET /", function()
      local found = false
      for _, r in ipairs(direct.routes) do
        if r.method == "GET" and r.path == "/" then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("has a handler for GET /events", function()
      local found = false
      for _, r in ipairs(direct.routes) do
        if r.method == "GET" and r.path == "/events" then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("has a handler for GET /vendor/:file", function()
      local found = false
      for _, r in ipairs(direct.routes) do
        if r.method == "GET" and r.path == "/vendor/:file" then
          found = true
        end
      end
      assert.is_true(found)
    end)
  end)

  -- ── serve_content ─────────────────────────────────────────────────────
  describe("serve_content", function()
    local bufnr

    after_each(function()
      if bufnr then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
        bufnr = nil
      end
    end)

    it("returns the buffer content as JSON", function()
      bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "# Hello", "", "World" })
      local res = mock_res()
      local ctx = mock_ctx(bufnr)
      direct.serve_content({}, res, ctx)
      assert.equals("200 OK", res._json_status)
      assert.equals("# Hello\n\nWorld", res._json_data.content)
    end)
  end)

  -- ── serve_sse ─────────────────────────────────────────────────────────
  describe("serve_sse", function()
    it("calls res.sse_upgrade with ctx.sse", function()
      local fake_sse = {}
      local res = mock_res()
      local ctx = { sse = fake_sse, bufnr = 1, config = {} }
      direct.serve_sse({}, res, ctx)
      assert.equals(fake_sse, res._sse_instance)
    end)
  end)

  -- ── serve_vendor ──────────────────────────────────────────────────────
  describe("serve_vendor", function()
    it("calls res.send_file with the vendor path and correct content type for js", function()
      local vendor = require("md-view.vendor")
      local res = mock_res()
      local req = { params = { file = "markdown-it.min.js" }, query = {} }
      direct.serve_vendor(req, res, {})
      assert.equals(vendor.vendor_dir() .. "/markdown-it.min.js", res._send_file_path)
      assert.equals("application/javascript", res._send_file_ct)
    end)

    it("calls res.send_file with text/css for css files", function()
      local vendor = require("md-view.vendor")
      local res = mock_res()
      local req = { params = { file = "highlight.min.css" }, query = {} }
      direct.serve_vendor(req, res, {})
      assert.equals("text/css", res._send_file_ct)
    end)
  end)

  -- ── serve_file ────────────────────────────────────────────────────────
  describe("serve_file", function()
    local bufnr

    after_each(function()
      if bufnr then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
        bufnr = nil
      end
    end)

    it("calls res.send_file with an absolute path resolved from bufdir", function()
      bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, "/home/user/docs/readme.md")
      local res = mock_res()
      local req = { params = {}, query = { path = "image.png" } }
      direct.serve_file(req, res, mock_ctx(bufnr))
      assert.equals("/home/user/docs/image.png", res._send_file_path)
      assert.equals("image/png", res._send_file_ct)
    end)

    it("responds 400 when query.path is missing", function()
      bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, "/home/user/docs/readme.md")
      local res = mock_res()
      local req = { params = {}, query = {} }
      direct.serve_file(req, res, mock_ctx(bufnr))
      assert.equals("400 Bad Request", res._status)
    end)
  end)

  -- ── dispatch integration ──────────────────────────────────────────────
  describe("dispatch integration", function()
    it("routes GET /events to serve_sse via router.dispatch", function()
      local fake_sse = {}
      local res = mock_res()
      local ctx = { sse = fake_sse, bufnr = 1, config = {} }
      local req = { method = "GET", path = "/events", params = {}, query = {} }
      router.dispatch(direct.routes, req, res, ctx)
      assert.equals(fake_sse, res._sse_instance)
    end)
  end)
end)
