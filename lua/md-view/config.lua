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
---@field highlights table<string, string|string[]>

---@class MdViewNotationOptions
---@field enable boolean

---@alias MdViewMermaidSecurityLevel "strict"|"antiscript"|"loose"|"sandbox"

---@class MdViewMermaidNotationOptions : MdViewNotationOptions
---@field theme string|nil
---@field security_level MdViewMermaidSecurityLevel

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
---@field bufnr integer|nil
---@field debounce_ms integer
---@field css string|nil
---@field auto_close boolean
---@field verbose boolean
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
  verbose = true,
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
    mermaid = { enable = true, theme = nil, security_level = "strict" },
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

local LOOPBACK = {
  ["127.0.0.1"] = true,
  ["::1"] = true,
  ["localhost"] = true,
}

local SCHEMA = {
  fields = {
    port = { type = "number" },
    host = { type = "string" },
    browser = { type = "string" },
    debounce_ms = { type = "number" },
    css = { type = "string" },
    auto_close = { type = "boolean" },
    verbose = { type = "boolean" },
    follow_focus = { type = "boolean" },
    scroll = {
      fields = {
        method = { type = "string", enum = { "percentage", "cursor" } },
      },
    },
    theme = {
      fields = {
        mode = { type = "string", enum = { "auto", "dark", "light", "sync" } },
        syntax = { type = "string" },
        highlights = { type = "table" },
      },
    },
    notations = {
      fields = {
        mermaid = {
          fields = {
            enable = { type = "boolean" },
            theme = { type = "string" },
          },
        },
        katex = { fields = { enable = { type = "boolean" } } },
        graphviz = { fields = { enable = { type = "boolean" } } },
        wavedrom = { fields = { enable = { type = "boolean" } } },
        nomnoml = { fields = { enable = { type = "boolean" } } },
        abc = { fields = { enable = { type = "boolean" } } },
        vegalite = { fields = { enable = { type = "boolean" } } },
      },
    },
    filetypes = { type = "table" },
    auto_open = {
      fields = {
        enable = { type = "boolean" },
        events = { type = "table" },
      },
    },
    picker = {
      fields = {
        prompt = { type = "string" },
        format_item = { type = "function" },
        kind = { type = "string" },
      },
    },
    single_page = {
      fields = {
        enable = { type = "boolean" },
        tab_label = { type = { "string", "function" }, enum = { "filename", "relative", "parent" } },
        close_by = { type = { "string", "boolean" }, enum = { "page", "tab" } },
      },
    },
  },
}

local function validate(schema, value, path)
  if value == nil then
    return
  end

  if schema.fields then
    if type(value) ~= "table" then
      error("[md-view] option '" .. path .. "' must be a table, got " .. type(value))
    end

    for k in pairs(value) do
      if schema.fields[k] == nil then
        vim.notify("[md-view] unknown option '" .. path .. "." .. k .. "'", vim.log.levels.WARN)
      end
    end

    for k, child in pairs(schema.fields) do
      validate(child, value[k], path .. "." .. k)
    end
  else
    local expected = schema.type
    local actual = type(value)
    local type_ok

    if type(expected) == "table" then
      type_ok = vim.tbl_contains(expected, actual)
    else
      type_ok = actual == expected
    end

    if not type_ok then
      local expected_str = type(expected) == "table" and table.concat(expected, "|") or expected
      error("[md-view] option '" .. path .. "' must be " .. expected_str .. ", got " .. actual)
    end

    if schema.enum and actual == "string" then
      if not vim.tbl_contains(schema.enum, value) then
        vim.notify(
          "[md-view] option '" .. path .. "' has unrecognized value: " .. vim.inspect(value),
          vim.log.levels.WARN
        )
      end
    end
  end
end

---@param opts MdViewOptions|nil
M.setup = function(opts)
  if opts then
    local ok, err = pcall(validate, SCHEMA, opts, "config")

    if not ok then
      vim.notify(err, vim.log.levels.ERROR)

      return
    end
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
