local M = {}

local config = require("md-view.config")
local preview = require("md-view.preview")
local theme = require("md-view.theme")

local VALID_THEME_MODES = { dark = true, light = true, auto = true, sync = true }
local THEME_CYCLE = { "dark", "light", "auto", "sync" }
local current_live_theme = nil

local function compute_live_css()
  if current_live_theme == "sync" then
    local highlights = (config.options and config.options.theme and config.options.theme.highlights) or {}
    return theme.css(highlights)
  elseif current_live_theme == "auto" then
    local resolved = vim.o.background == "light" and "light" or "dark"
    return theme.palette_css(resolved)
  else
    return theme.palette_css(current_live_theme)
  end
end

local function register_auto_open_augroup()
  local group = vim.api.nvim_create_augroup("md_view_auto_open", { clear = true })
  vim.api.nvim_create_autocmd(config.options.auto_open.events, {
    group = group,
    pattern = "*",
    callback = function()
      M.open({ silent = true })
    end,
  })
end

---@param opts MdViewOptions|nil
M.setup = function(opts)
  current_live_theme = nil
  config.setup(opts)
  pcall(vim.api.nvim_del_augroup_by_name, "md_view_auto_open")
  if config.options.auto_open.enable then
    register_auto_open_augroup()
  end
  local vendor = require("md-view.vendor")
  if not vendor.is_available() and vim.fn.executable("curl") == 1 then
    vim.notify("[md-view] Caching vendor assets...", vim.log.levels.INFO)
    vendor.fetch()
  end
end

---@param opts { silent?: boolean }|nil
M.open = function(opts)
  opts = opts or {}
  if not config.options then
    config.setup({})
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local ft = vim.bo[bufnr].filetype
  local filetypes = config.options.filetypes
  if filetypes and #filetypes > 0 then
    local allowed = false
    for _, v in ipairs(filetypes) do
      if v == ft then
        allowed = true
        break
      end
    end
    if not allowed then
      if not opts.silent then
        vim.notify("[md-view] filetype '" .. ft .. "' is not in filetypes list", vim.log.levels.WARN)
      end
      return
    end
  end
  local existing = preview.get_by_buffer(bufnr)
  local preview_opts = config.options
  if current_live_theme then
    preview_opts = vim.tbl_extend("force", preview_opts, {
      theme = vim.tbl_extend("force", preview_opts.theme, { mode = current_live_theme }),
    })
  end
  preview.create(vim.tbl_extend("force", preview_opts, { silent = opts.silent }))
  if current_live_theme and existing then
    existing.sse:push("palette", { css = compute_live_css() })
  end
end

---@param bufnr integer|nil
M.stop = function(bufnr)
  preview.destroy(bufnr)
end

---@return nil
M.toggle = function()
  local bufnr = vim.api.nvim_get_current_buf()
  if preview.get_by_buffer(bufnr) then
    M.stop(bufnr)
  else
    M.open()
  end
end

---@return table<integer, table>
M.get_active_previews = function()
  return preview.get_active_previews()
end

---@return nil
M.list = function()
  require("md-view.picker").open()
end

---@return nil
M.toggle_auto_open = function()
  if not config.options then
    config.setup({})
  end
  local enabled = not config.options.auto_open.enable
  config.options.auto_open.enable = enabled
  pcall(vim.api.nvim_del_augroup_by_name, "md_view_auto_open")
  if enabled then
    vim.notify("[md-view] auto-open enabled")
    register_auto_open_augroup()
  else
    vim.notify("[md-view] auto-open disabled")
  end
end

---@param mode MdViewThemeMode|nil
M.set_theme = function(mode)
  -- Validate explicit arg first (before checking active previews)
  if mode and mode ~= "" then
    if not VALID_THEME_MODES[mode] then
      vim.notify("[md-view] invalid theme mode: '" .. mode .. "'", vim.log.levels.WARN)
      return
    end
  end

  -- Early exit if no active previews (no state mutation)
  if vim.tbl_isempty(preview.get_active_previews()) then
    return
  end

  local notified_mode
  if mode and mode ~= "" then
    -- Explicit arg path
    current_live_theme = mode
    notified_mode = mode
  else
    -- Cycle path: lazy-initialize then advance
    if current_live_theme == nil then
      if config.options and config.options.theme and config.options.theme.mode == "sync" then
        current_live_theme = "sync"
      elseif config.options then
        current_live_theme = theme.resolve(config.options).theme
      else
        current_live_theme = "dark"
      end
    end
    -- Advance to next in cycle
    local idx = 1
    for i, v in ipairs(THEME_CYCLE) do
      if v == current_live_theme then
        idx = i
        break
      end
    end
    current_live_theme = THEME_CYCLE[(idx % #THEME_CYCLE) + 1]
    notified_mode = current_live_theme
  end

  -- Push to all active previews
  local css = compute_live_css()
  local h = preview.get_mux and preview.get_mux()
  for bufnr, p in pairs(preview.get_active_previews()) do
    p.sse:push("palette", { css = css })
    if h and h.server then
      h:push("palette", { id = bufnr, css = css })
    end
  end
  -- Push hub-level palette so the chrome (tab bar, body) updates immediately
  if h and h.server then
    h:push("hub_palette", { css = css })
  end

  vim.notify("[md-view] theme: " .. notified_mode, vim.log.levels.INFO)
end

return M
