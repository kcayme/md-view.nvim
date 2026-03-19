local M = {}

---@alias MdViewThemeMode "auto"|"dark"|"light"|"sync"
---@alias MdViewScrollMethod "percentage"|"cursor"
---@alias MdViewTabLabel "filename"|"relative"|"parent"
---@alias MdViewCloseBy "page"|"tab"|false|nil

---@class MdViewTabLabelCtx
---@field bufnr integer
---@field filename string
---@field path string

---@class MdViewScrollOptions
---@field method MdViewScrollMethod

---@class MdViewThemeOptions
---@field mode MdViewThemeMode
---@field syntax string|nil
---@field highlights table<string, string>

---@class MdViewNotationOptions
---@field enable boolean

---@class MdViewMermaidNotationOptions : MdViewNotationOptions
---@field theme string|nil

---@class MdViewNotationsOptions
---@field mermaid MdViewMermaidNotationOptions
---@field katex MdViewNotationOptions
---@field graphviz MdViewNotationOptions
---@field wavedrom MdViewNotationOptions
---@field nomnoml MdViewNotationOptions
---@field abc MdViewNotationOptions
---@field vegalite MdViewNotationOptions

---@class MdViewAutoOpenOptions
---@field enable boolean
---@field events string[]

---@class MdViewPickerOptions
---@field prompt string
---@field format_item (fun(item: table): string)|nil
---@field kind string|nil

---@class MdViewSinglePageOptions
---@field enable boolean
---@field tab_label MdViewTabLabel|(fun(ctx: MdViewTabLabelCtx): string)
---@field close_by MdViewCloseBy

---@class MdViewOptions
---@field port integer
---@field host string
---@field browser string|nil
---@field debounce_ms integer
---@field css string|nil
---@field auto_close boolean
---@field follow_focus boolean
---@field scroll MdViewScrollOptions
---@field theme MdViewThemeOptions
---@field notations MdViewNotationsOptions
---@field filetypes string[]
---@field auto_open MdViewAutoOpenOptions
---@field picker MdViewPickerOptions
---@field single_page MdViewSinglePageOptions

M.defaults = {
  port = 0,
  host = "127.0.0.1",
  browser = nil,
  debounce_ms = 300,
  css = nil,
  auto_close = true,
  follow_focus = false,
  scroll = {
    method = "percentage", -- "percentage" | "cursor"
  },
  theme = {
    mode = "auto", -- "auto" | "dark" | "light" | "sync"
    syntax = nil, -- highlight.js theme; nil = auto-select
    highlights = {}, -- highlight group overrides (only used when mode = "sync")
  },
  notations = {
    mermaid = { enable = true, theme = nil },
    katex = { enable = true },
    graphviz = { enable = true },
    wavedrom = { enable = true },
    nomnoml = { enable = true },
    abc = { enable = true },
    vegalite = { enable = true },
  },
  filetypes = { "markdown" },
  auto_open = {
    enable = false,
    events = { "BufWinEnter" },
  },
  picker = {
    prompt = "Markdown Previews",
    format_item = nil,
    kind = nil,
  },
  single_page = {
    enable = false,
    tab_label = "parent",
  },
}

---@type MdViewOptions|nil
M.options = nil

local LOOPBACK = { ["127.0.0.1"] = true, ["::1"] = true, ["localhost"] = true }

---@param opts MdViewOptions|nil
function M.setup(opts)
  -- Deprecated: theme_sync = true → theme = { mode = "sync" }
  if opts and opts.theme_sync == true then
    vim.notify('[md-view] `theme_sync` is deprecated; use `theme = { mode = "sync" }` instead', vim.log.levels.WARN)
    local existing = type(opts.theme) == "table" and opts.theme or {}
    local new_theme = (existing.mode == nil) and vim.tbl_extend("force", existing, { mode = "sync" }) or existing
    opts = vim.tbl_extend("force", opts, { theme = new_theme })
    opts.theme_sync = nil
  end
  -- Deprecated: theme as a plain string → theme = { mode = <value> }
  if opts and type(opts.theme) == "string" then
    vim.notify("[md-view] `theme` as a string is deprecated; use `theme = { mode = ... }` instead", vim.log.levels.WARN)
    opts = vim.tbl_extend("force", opts, { theme = { mode = opts.theme } })
  end
  -- Deprecated: scroll_sync → scroll.method
  if opts and opts.scroll_sync ~= nil then
    vim.notify("[md-view] `scroll_sync` is deprecated; use `scroll = { method = ... }` instead", vim.log.levels.WARN)
    local new_scroll
    if type(opts.scroll) == "table" and opts.scroll.method ~= nil then
      new_scroll = opts.scroll
    else
      local method = (opts.scroll_sync == "percentage") and "percentage" or "cursor"
      new_scroll = vim.tbl_extend("force", type(opts.scroll) == "table" and opts.scroll or {}, { method = method })
    end
    opts = vim.tbl_extend("force", opts, { scroll = new_scroll })
    opts.scroll_sync = nil
  end
  -- Deprecated: highlight_theme → theme.syntax
  if opts and opts.highlight_theme ~= nil then
    vim.notify("[md-view] `highlight_theme` is deprecated; use `theme = { syntax = ... }` instead", vim.log.levels.WARN)
    local theme_tbl = type(opts.theme) == "table" and opts.theme or {}
    if theme_tbl.syntax == nil then
      opts =
        vim.tbl_extend("force", opts, { theme = vim.tbl_extend("force", theme_tbl, { syntax = opts.highlight_theme }) })
    end
    opts.highlight_theme = nil
  end
  -- Deprecated: highlights → theme.highlights
  if opts and opts.highlights ~= nil then
    vim.notify("[md-view] `highlights` is deprecated; use `theme = { highlights = ... }` instead", vim.log.levels.WARN)
    local theme_tbl = type(opts.theme) == "table" and opts.theme or {}
    if theme_tbl.highlights == nil then
      opts =
        vim.tbl_extend("force", opts, { theme = vim.tbl_extend("force", theme_tbl, { highlights = opts.highlights }) })
    end
    opts.highlights = nil
  end
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
  -- filetypes is an array; deep-extend cannot clear it with {}, so override directly
  if opts and opts.filetypes ~= nil then
    M.options.filetypes = opts.filetypes
  end
  -- auto_open.events is an array; deep-extend cannot clear it with {}, so override directly
  if opts and opts.auto_open ~= nil and opts.auto_open.events ~= nil then
    M.options.auto_open.events = opts.auto_open.events
  end
  if not LOOPBACK[M.options.host] then
    vim.notify(
      "[md-view] WARNING: host '"
        .. M.options.host
        .. "' is not loopback — preview server will be exposed to the network",
      vim.log.levels.WARN
    )
  end
end

return M
