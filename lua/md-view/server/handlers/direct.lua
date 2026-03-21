local M = {}

local template = require("md-view.server.template")
local vendor = require("md-view.vendor")
local router = require("md-view.server.router")

M.serve_shell = function(_req, res, ctx)
  local bufname = vim.api.nvim_buf_get_name(ctx.bufnr)
  local filename = vim.fn.fnamemodify(bufname, ":t")
  local html = template.render(ctx.config, filename)

  res.send("200 OK", "text/html", html)
end

M.serve_content = function(_req, res, ctx)
  local lines = vim.api.nvim_buf_get_lines(ctx.bufnr, 0, -1, false)

  res.json("200 OK", { content = table.concat(lines, "\n") })
end

M.serve_sse = function(_req, res, ctx)
  res.sse_upgrade(ctx.sse)
end

M.serve_vendor = function(req, res, _ctx)
  local filename = req.params.file
  if not filename or not filename:match("^[%w%.%-_]+$") then
    res.send("404 Not Found", "text/plain", "Not Found")
    return
  end

  local ext = filename:match("%.([^%.]+)$")
  local content_type = ext == "css" and "text/css" or "application/javascript"

  res.send_file(vendor.vendor_dir() .. "/" .. filename, content_type)
end

M.serve_file = function(req, res, ctx)
  local raw = req.query.path
  local bufname = vim.api.nvim_buf_get_name(ctx.bufnr)
  local bufdir = vim.fn.fnamemodify(bufname, ":p:h")
  local abs = router.resolve_media_path(bufdir, raw)

  if not abs then
    res.send("400 Bad Request", "text/plain", "Bad Request")
    return
  end

  local ext = (abs:match("%.([^%.]+)$") or ""):lower()

  res.send_file(abs, router.MEDIA_TYPES[ext] or "application/octet-stream")
end

M.routes = {
  { method = "GET", path = "/", handler = M.serve_shell },
  { method = "GET", path = "/content", handler = M.serve_content },
  { method = "GET", path = "/events", handler = M.serve_sse },
  { method = "GET", path = "/vendor/:file", handler = M.serve_vendor },
  { method = "GET", path = "/file", handler = M.serve_file },
}

return M
