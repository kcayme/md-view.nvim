local M = {}

local PALETTES = {
  dark = {
    ["--md-bg"] = "#0d1117",
    ["--md-fg"] = "#e6edf3",
    ["--md-heading"] = "#f0f6fc",
    ["--md-bold"] = "inherit",
    ["--md-muted"] = "#848d97",
    ["--md-blockquote"] = "#848d97",
    ["--md-link"] = "#4493f8",
    ["--md-code-fg"] = "#f0d96a",
    ["--md-code-bg"] = "#161b22",
    ["--md-pre-fg"] = "#e6edf3",
    ["--md-border"] = "#30363d",
    ["--md-checkbox"] = "#1f6feb",
    ["--md-table-header-bg"] = "#161b22",
    ["--md-row-alt"] = "#161b2205",
  },
  light = {
    ["--md-bg"] = "#ffffff",
    ["--md-fg"] = "#1f2328",
    ["--md-heading"] = "#1f2328",
    ["--md-bold"] = "inherit",
    ["--md-muted"] = "#656d76",
    ["--md-blockquote"] = "#656d76",
    ["--md-link"] = "#0969da",
    ["--md-code-fg"] = "#6639ba",
    ["--md-code-bg"] = "#eff1f3",
    ["--md-pre-fg"] = "#1f2328",
    ["--md-border"] = "#d1d9e0",
    ["--md-checkbox"] = "#0969da",
    ["--md-table-header-bg"] = "#f6f8fa",
    ["--md-row-alt"] = "#f6f8fa80",
  },
}

local THEME_DEFAULTS = {
  dark = { highlight_theme = "vs2015", mermaid_theme = "dark" },
  light = { highlight_theme = "github", mermaid_theme = "default" },
}

local mappings = {
  { var = "--md-bg", groups = { "Normal" }, attr = "bg" },
  { var = "--md-fg", groups = { "Normal" }, attr = "fg" },
  { var = "--md-heading", groups = { "Title", "@markup.heading", "Normal" }, attr = "fg" },
  { var = "--md-bold", groups = { "@markup.strong", "@markup.bold", "Normal" }, attr = "fg" },
  { var = "--md-muted", groups = { "Comment" }, attr = "fg" },
  { var = "--md-blockquote", groups = { "@markup.quote", "Comment", "Normal" }, attr = "fg" },
  { var = "--md-link", groups = { "@markup.link.url", "@markup.link", "Underlined" }, attr = "fg" },
  { var = "--md-code-fg", groups = { "Statement", "@markup.raw", "String" }, attr = "fg" },
  { var = "--md-code-bg", groups = { "CursorLine", "Pmenu" }, attr = "bg" },
  { var = "--md-pre-fg", groups = { "Normal" }, attr = "fg" },
  { var = "--md-border", groups = { "WinSeparator", "VertSplit" }, attr = "fg" },
  { var = "--md-checkbox", groups = { "DiagnosticInfo", "Function" }, attr = "fg" },
  { var = "--md-table-header-bg", groups = { "CursorLine", "Pmenu" }, attr = "bg" },
  { var = "--md-row-alt", groups = { "CursorLine" }, attr = "bg" },
}

local hljs_mappings = {
  { selector = "pre code", groups = { "Normal" }, attr = "fg" },
  { selector = "pre code .hljs-keyword", groups = { "@keyword", "Keyword", "Statement" }, attr = "fg" },
  { selector = "pre code .hljs-string", groups = { "@string", "String" }, attr = "fg" },
  { selector = "pre code .hljs-comment", groups = { "@comment", "Comment" }, attr = "fg" },
  { selector = "pre code .hljs-function", groups = { "@function", "Function" }, attr = "fg" },
  { selector = "pre code .hljs-number", groups = { "@number", "Number" }, attr = "fg" },
  { selector = "pre code .hljs-title", groups = { "@function", "Function" }, attr = "fg" },
  { selector = "pre code .hljs-title.class_", groups = { "@type", "Type" }, attr = "fg" },
  { selector = "pre code .hljs-type", groups = { "@type", "Type" }, attr = "fg" },
  { selector = "pre code .hljs-built_in", groups = { "@function.builtin", "@type.builtin", "Special" }, attr = "fg" },
  { selector = "pre code .hljs-literal", groups = { "@boolean", "Boolean" }, attr = "fg" },
  { selector = "pre code .hljs-params", groups = { "@variable.parameter", "Identifier" }, attr = "fg" },
  { selector = "pre code .hljs-attr", groups = { "@property", "@attribute", "Identifier" }, attr = "fg" },
  { selector = "pre code .hljs-variable", groups = { "@variable", "Identifier" }, attr = "fg" },
  { selector = "pre code .hljs-symbol", groups = { "@string.special.symbol", "Special" }, attr = "fg" },
  { selector = "pre code .hljs-meta", groups = { "@keyword.directive", "PreProc" }, attr = "fg" },
  { selector = "pre code .hljs-operator", groups = { "@operator", "Operator" }, attr = "fg" },
  { selector = "pre code .hljs-punctuation", groups = { "@punctuation.delimiter", "Delimiter" }, attr = "fg" },
  { selector = "pre code .hljs-property", groups = { "@property", "Identifier" }, attr = "fg" },
  { selector = "pre code .hljs-regexp", groups = { "@string.regexp", "String" }, attr = "fg" },
  { selector = "pre code .hljs-tag", groups = { "@tag", "Tag" }, attr = "fg" },
  { selector = "pre code .hljs-name", groups = { "@tag", "Tag" }, attr = "fg" },
  { selector = "pre code .hljs-selector-class", groups = { "@type", "Type" }, attr = "fg" },
  { selector = "pre code .hljs-selector-id", groups = { "@variable", "Identifier" }, attr = "fg" },
}

local KEY_TO_VAR = {
  bg = "--md-bg",
  fg = "--md-fg",
  heading = "--md-heading",
  bold = "--md-bold",
  muted = "--md-muted",
  blockquote = "--md-blockquote",
  link = "--md-link",
  code = "--md-code-fg",
  code_bg = "--md-code-bg",
  pre_fg = "--md-pre-fg",
  border = "--md-border",
  checkbox = "--md-checkbox",
  table_header_bg = "--md-table-header-bg",
  row_alt = "--md-row-alt",
}

function M.build_mappings(overrides)
  if not overrides or vim.tbl_isempty(overrides) then
    return mappings
  end
  local result = {}
  for _, m in ipairs(mappings) do
    result[#result + 1] = vim.deepcopy(m)
  end
  for key, groups in pairs(overrides) do
    local var = KEY_TO_VAR[key]
    if var then
      if type(groups) == "string" then
        groups = { groups }
      end
      for i, m in ipairs(result) do
        if m.var == var then
          result[i].groups = groups
          break
        end
      end
    end
  end
  return result
end

local function int_to_hex(val)
  return string.format("#%06x", val)
end

function M.extract(custom_mappings)
  local map = custom_mappings or mappings
  local vars = {}
  for _, m in ipairs(map) do
    for _, group in ipairs(m.groups) do
      local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
      if ok and hl and hl[m.attr] then
        vars[m.var] = int_to_hex(hl[m.attr])
        break
      end
    end
  end
  -- Fallback: if Normal bg/fg weren't found, use vim.o.background
  if not vars["--md-bg"] then
    vars["--md-bg"] = vim.o.background == "light" and "#ffffff" or "#0d1117"
  end
  if not vars["--md-fg"] then
    vars["--md-fg"] = vim.o.background == "light" and "#1e1e1e" or "#cccccc"
  end

  return vars
end

function M.extract_hljs()
  local rules = {}
  for _, m in ipairs(hljs_mappings) do
    for _, group in ipairs(m.groups) do
      local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
      if ok and hl and hl[m.attr] then
        local props = { "color: " .. int_to_hex(hl[m.attr]) }
        if hl.bold then
          props[#props + 1] = "font-weight: bold"
        end
        if hl.italic then
          props[#props + 1] = "font-style: italic"
        end
        rules[#rules + 1] = m.selector .. " { " .. table.concat(props, "; ") .. "; }"
        break
      end
    end
  end
  return rules
end

function M.to_css(vars)
  local parts = { ":root {" }
  for var, val in pairs(vars) do
    parts[#parts + 1] = "  " .. var .. ": " .. val .. ";"
  end
  parts[#parts + 1] = "}"
  return table.concat(parts, "\n")
end

function M.css(overrides)
  local merged = M.build_mappings(overrides)
  local css = M.to_css(M.extract(merged))
  local hljs_rules = M.extract_hljs()
  if #hljs_rules > 0 then
    css = css .. "\n" .. table.concat(hljs_rules, "\n")
  end
  return css
end

function M.palette_css(theme_name)
  return M.to_css(PALETTES[theme_name] or PALETTES.dark)
end

function M.resolve(opts)
  local resolved_theme = opts.theme.mode
  if resolved_theme ~= "light" and resolved_theme ~= "dark" then
    resolved_theme = vim.o.background
  end

  local defs = THEME_DEFAULTS[resolved_theme] or THEME_DEFAULTS.dark
  local m = opts.notations and opts.notations.mermaid
  return {
    theme = resolved_theme,
    highlight_theme = opts.theme.syntax or defs.highlight_theme,
    mermaid_theme = (m and m.theme) or defs.mermaid_theme,
  }
end

return M
