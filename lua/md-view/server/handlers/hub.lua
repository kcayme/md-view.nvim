local M = {}
M.__index = M

---@class MdViewHub
---@field registry table<integer, {title: string, label: string}>
---@field clients table[]
---@field last table<integer, table<string, table>>
---@field last_hub_palette table|nil
---@field on_client_added (fun(client: table))|nil
---@field server userdata|nil
---@field port integer|nil

local REPLAY_EVENTS = { palette = true, theme = true, preview_added = true }
-- preview_added must be replayed before palette/theme so the panel exists when styles arrive
local REPLAY_ORDER = { "preview_added", "palette", "theme" }

---@return MdViewHub
M.new = function()
  return setmetatable({
    registry = {}, -- bufnr -> { title, label }
    clients = {}, -- SSE client list (shared across all previews)
    last = {}, -- last[bufnr][event_type] = data (per-preview replay state)
    last_hub_palette = nil, -- hub-level palette CSS replayed on connect
    on_client_added = nil, -- set by preview.lua to push initial content on connect
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
---@param bufnr integer
---@param path string
---@param tab_label_cfg MdViewTabLabel|(fun(ctx: MdViewTabLabelCtx): string)|nil
function M:register(bufnr, path, tab_label_cfg)
  local filename = vim.fn.fnamemodify(path, ":t")
  local ctx = { bufnr = bufnr, filename = filename, path = path }
  local label = self:resolve_label(ctx, tab_label_cfg)
  self.registry[bufnr] = { title = filename, label = label }
end

-- Unregister a preview. Evicts per-preview replay state.
-- Caller must push preview_removed before calling unregister.
---@param bufnr integer
function M:unregister(bufnr)
  self.registry[bufnr] = nil
  self.last[bufnr] = nil
end

function M:add_client(client)
  table.insert(self.clients, client)
  -- Replay hub-level palette first so the chrome is styled before panels appear
  if self.last_hub_palette then
    local payload = "event: hub_palette\ndata: " .. vim.json.encode(self.last_hub_palette) .. "\n\n"
    pcall(function()
      client:write(payload)
    end)
  end
  -- Replay per-preview state in fixed order: preview_added first (creates panel),
  -- then palette/theme (style the panel). Arbitrary table iteration would apply
  -- palette before the panel exists, losing the style.
  for bufnr, _ in pairs(self.registry) do
    local per_preview = self.last[bufnr]
    if per_preview then
      for _, event_type in ipairs(REPLAY_ORDER) do
        local data = per_preview[event_type]
        if data then
          local payload = "event: " .. event_type .. "\ndata: " .. vim.json.encode(data) .. "\n\n"
          pcall(function()
            client:write(payload)
          end)
        end
      end
    end
  end
  -- Push initial content after preview_added replay so panels exist in the browser
  -- when the content events arrive.
  if self.on_client_added then
    self.on_client_added(client)
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

---@param event_type string
---@param data table
function M:push(event_type, data)
  -- Store hub-level palette for replay
  if event_type == "hub_palette" then
    self.last_hub_palette = data
  end
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
  for i, c in ipairs(self.clients) do
    local ok = pcall(function()
      c:write(payload)
    end)
    if not ok then
      dead[#dead + 1] = i
    end
  end
  for i = #dead, 1, -1 do
    local c = self.clients[dead[i]]
    table.remove(self.clients, dead[i])
    if not c:is_closing() then
      c:close()
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

-- ── Route handlers ──────────────────────────────────────────────────────

M.serve_root = function(_req, res, _ctx)
  local template = require("md-view.server.template")
  local config = require("md-view.config")
  local theme_mod = require("md-view.theme")
  local resolved = theme_mod.resolve(config.options)
  local theme_css = config.options.theme
      and config.options.theme.mode == "sync"
      and theme_mod.css(config.options.theme.highlights or {})
    or ""
  local render_opts = vim.tbl_extend("force", config.options, {
    palette_css = theme_mod.palette_css(resolved.theme),
    theme_css = theme_css,
    highlight_theme = resolved.highlight_theme,
    mermaid = { theme = resolved.mermaid_theme },
  })
  res.send("200 OK", "text/html", template.render_mux(render_opts))
end

M.serve_sse = function(_req, res, ctx)
  res.sse_upgrade(ctx.hub)
end

M.serve_content = function(req, res, ctx)
  local bufnr = req.query.id and tonumber(req.query.id)
  if not bufnr or not ctx.hub.registry[bufnr] then
    res.send("400 Bad Request", "text/plain", "Bad Request")
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  res.json("200 OK", { content = table.concat(lines, "\n") })
end

M.serve_vendor = function(req, res, _ctx)
  local vendor = require("md-view.vendor")
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
  local router = require("md-view.server.router")
  local bufnr = req.query.id and tonumber(req.query.id)
  local raw = req.query.path
  if not bufnr or not ctx.hub.registry[bufnr] or not raw or raw == "" then
    res.send("400 Bad Request", "text/plain", "Bad Request")
    return
  end
  local bufdir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":p:h")
  local abs = router.resolve_media_path(bufdir, raw)
  if not abs then
    res.send("400 Bad Request", "text/plain", "Bad Request")
    return
  end
  local ext = (abs:match("%.([^%.]+)$") or ""):lower()
  res.send_file(abs, router.MEDIA_TYPES[ext] or "application/octet-stream")
end

M.routes = {
  { method = "GET", path = "/", handler = M.serve_root },
  { method = "GET", path = "/sse", handler = M.serve_sse },
  { method = "GET", path = "/content", handler = M.serve_content },
  { method = "GET", path = "/vendor/:file", handler = M.serve_vendor },
  { method = "GET", path = "/file", handler = M.serve_file },
}

return M
