local M = {}

local config = require("md-view.config")
local preview = require("md-view.preview")
local theme = require("md-view.theme")
local util = require("md-view.util")
local vendor = require("md-view.vendor")

local VALID_THEME_MODES = {
  "dark",
  "light",
  "auto",
  "sync",
}
local current_live_theme = "dark"

local function get_live_css()
  if current_live_theme == "sync" then
    local highlights = (config.options and config.options.theme and config.options.theme.highlights) or {}

    return theme.css(highlights)
  elseif current_live_theme == "auto" then
    local resolved = vim.o.background == "light" and "light" or "dark"

    return theme.palette_css(resolved)
  end

  return theme.palette_css(current_live_theme)
end

-- Returns the highlight.js CSS URL for the current live theme, or nil when in sync
-- mode (which uses inline CSS overrides instead of a theme stylesheet).
local function get_live_hljs_url()
  if current_live_theme == "sync" then
    return nil
  end

  local copts = config.options or {}
  local theme_tbl = copts.theme or {}
  local resolved_mode = current_live_theme == "auto" and (vim.o.background == "light" and "light" or "dark")
    or current_live_theme

  local resolved = theme.resolve(
    vim.tbl_extend("force", copts, { theme = vim.tbl_extend("force", theme_tbl, { mode = resolved_mode }) })
  )

  return vendor.hljs_url(resolved.highlight_theme)
end

local function register_auto_open_augroup()
  local group = vim.api.nvim_create_augroup("md_view_auto_open", { clear = true })
  vim.api.nvim_create_autocmd(config.options.auto_open.events, {
    group = group,
    pattern = "*",
    callback = function()
      M.open({ verbose = false })
    end,
  })
end

local function is_valid_filetype(bufnr, verbose)
  local ft = vim.bo[bufnr].filetype
  local filetypes = config.options.filetypes

  if filetypes and #filetypes > 0 then
    for _, v in ipairs(filetypes) do
      if string.lower(v) == ft then
        return true
      end
    end

    util.notify(
      { verbose = verbose },
      "[md-view] filetype '" .. ft .. "' is not in filetypes list",
      vim.log.levels.WARN
    )

    return false
  end

  return true
end

local function init_assets()
  if not vendor.is_available() and vim.fn.executable("curl") == 1 then
    util.notify(config.options, "[md-view] Caching vendor assets...", vim.log.levels.INFO)

    vendor.fetch()
  end
end

---@param opts MdViewOptions|nil
M.setup = function(opts)
  current_live_theme = nil
  config.setup(opts)
  pcall(vim.api.nvim_del_augroup_by_name, "md_view_auto_open")
  init_assets()

  if config.options.auto_open.enable then
    register_auto_open_augroup()
  end
end

---@param opts { verbose?: boolean, follow_focus?: boolean, browser?: string }|nil
M.open = function(opts)
  opts = opts or {}

  if not config.options then
    config.setup({})
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local existing_preview = preview.get_by_buffer(bufnr)
  local preview_opts = config.options
  local verbose = opts.verbose == nil and config.options.verbose or opts.verbose

  if not is_valid_filetype(bufnr, verbose) then
    return
  end

  if current_live_theme then
    preview_opts = vim.tbl_extend("force", preview_opts, {
      theme = vim.tbl_extend("force", preview_opts.theme, { mode = current_live_theme }),
    })
  end

  local call_opts = {
    verbose = verbose,
    follow_focus = (opts.follow_focus ~= nil and existing_preview and opts.follow_focus),
    browser = (opts.browser ~= nil and opts.browser),
  }

  preview.create(vim.tbl_extend("force", preview_opts, call_opts))

  if current_live_theme and existing_preview and existing_preview.sse then
    existing_preview.sse:push("palette", { css = get_live_css() })
  end
end

---@param bufnr integer|nil
M.stop = function(bufnr)
  preview.destroy(bufnr)
end

---@param bufnr integer|nil
M.close = function(bufnr)
  preview.close(bufnr)
end

---@return nil
M.close_all = function()
  for bufnr, _ in pairs(preview.get_active_previews()) do
    preview.close(bufnr)
  end
end

---@return nil
M.restart = function()
  local bufs = vim.tbl_keys(preview.get_active_previews())

  if #bufs == 0 then
    return
  end

  for _, bufnr in ipairs(bufs) do
    preview.destroy(bufnr)
  end

  local preview_opts = config.options

  if current_live_theme then
    preview_opts = vim.tbl_extend("force", preview_opts, {
      theme = vim.tbl_extend("force", preview_opts.theme, { mode = current_live_theme }),
    })
  end

  for _, bufnr in ipairs(bufs) do
    preview.create(vim.tbl_extend("force", preview_opts, { bufnr = bufnr }))
  end
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
    util.notify(config.options, "[md-view] auto-open enabled", vim.log.levels.INFO)

    register_auto_open_augroup()
  else
    util.notify(config.options, "[md-view] auto-open disabled", vim.log.levels.INFO)
  end
end

---@param mode MdViewThemeMode|nil
M.set_theme = function(mode)
  -- Validate explicit arg first (before checking active previews)
  if mode and mode ~= "" then
    if not vim.tbl_contains(VALID_THEME_MODES, mode) then
      util.notify(config.options, "[md-view] invalid theme mode: '" .. mode .. "'", vim.log.levels.WARN)

      return
    end
  end

  local active_previews = preview.get_active_previews()

  -- Early exit if no active previews (no state mutation)
  if vim.tbl_isempty(active_previews) then
    return
  end

  if mode and mode ~= "" then
    -- Explicit arg path
    current_live_theme = mode
  else
    -- Cycle path: lazy-initialize from config on first cycle after setup, then advance
    if current_live_theme == nil then
      if config.options.theme.mode == "sync" then
        current_live_theme = "sync"
      else
        current_live_theme = theme.resolve(config.options).theme
      end
    end

    -- Advance to next in cycle
    local idx = 1

    for i, v in ipairs(VALID_THEME_MODES) do
      if v == current_live_theme then
        idx = i
        break
      end
    end

    current_live_theme = VALID_THEME_MODES[(idx % #VALID_THEME_MODES) + 1]
  end

  -- Push to all active previews
  local css = get_live_css()
  local hljs_url = get_live_hljs_url()
  local is_sync = current_live_theme == "sync"
  local hub = preview.get_mux and preview.get_mux()

  for bufnr, pview in pairs(active_previews) do
    if pview.sse then
      pview.sse:push("palette", { css = css })

      if not is_sync then
        -- Clear any sync CSS overrides baked into the static page at load time
        pview.sse:push("theme", { css = "" })
        pview.sse:push("hljs_theme", { url = hljs_url })
      end
    end

    if hub and hub.server then
      hub:push("palette", { id = bufnr, css = css })
    end
  end

  -- Push hub-level palette and hljs theme so the whole page updates immediately
  if hub and hub.server then
    hub:push("hub_palette", { css = css })

    if not is_sync then
      -- Clear any sync CSS overrides baked into the static hub page at load time
      hub:push("hub_theme", { css = "" })
      hub:push("hub_hljs_theme", { url = hljs_url })
    end
  end

  util.notify(config.options, "[md-view] theme: " .. current_live_theme, vim.log.levels.INFO)
end

return M
