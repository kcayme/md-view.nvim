local M = {}

local vendor = require("md-view.vendor")

-- NOTE: innerHTML usage here is safe — this is a local-only preview server
-- (127.0.0.1) rendering the user's own markdown buffer content. No untrusted
-- external content is involved. morphdom requires innerHTML for DOM diffing.

-- Three states: nil = not yet tried, false = failed, string = loaded
local TEMPLATE

local function load_template()
  if type(TEMPLATE) == "string" then
    return TEMPLATE
  end
  if TEMPLATE == false then
    return nil
  end

  local path = vim.api.nvim_get_runtime_file("assets/template.html", false)[1]
  if not path then
    vim.notify("md-view.nvim: could not find assets/template.html in runtimepath", vim.log.levels.ERROR)
    TEMPLATE = false
    return nil
  end

  local fh, err = io.open(path, "rb") -- binary mode: no CRLF translation on Windows
  if not fh then
    vim.notify("md-view.nvim: could not open " .. path .. ": " .. (err or ""), vim.log.levels.ERROR)
    TEMPLATE = false
    return nil
  end

  local content = fh:read("*a")
  fh:close()
  if not content or content == "" then
    vim.notify("md-view.nvim: assets/template.html is empty or unreadable", vim.log.levels.ERROR)
    TEMPLATE = false
    return nil
  end
  TEMPLATE = content
  return TEMPLATE
end

local VALID_MERMAID_THEMES = {
  default = true,
  dark = true,
  forest = true,
  neutral = true,
  base = true,
}

local function html_escape(str)
  return str:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&#39;")
end

local function sanitize_theme_name(name)
  return name:gsub("[^%w_%-]", "")
end

local function build_script_tags(opts)
  local use_local = vendor.is_available()
  local function asset_src(local_name, cdn_url)
    return use_local and ("/vendor/" .. local_name) or cdn_url
  end

  local highlight_theme = sanitize_theme_name(opts.highlight_theme or "vs2015")
  local highlight_link = ""
  if opts.theme ~= "sync" then
    highlight_link = '<link rel="stylesheet" href="'
      .. asset_src(
        "highlight-theme.min.css",
        "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11/build/styles/" .. highlight_theme .. ".min.css"
      )
      .. '">'
  end

  local core_scripts = '<script src="'
    .. asset_src("markdown-it-14.1.0.min.js", "https://cdn.jsdelivr.net/npm/markdown-it@14.1.0/dist/markdown-it.min.js")
    .. '"></script>\n'
    .. '<script src="'
    .. asset_src(
      "markdown-it-task-lists-2.1.1.min.js",
      "https://cdn.jsdelivr.net/npm/markdown-it-task-lists@2.1.1/dist/markdown-it-task-lists.min.js"
    )
    .. '"></script>\n'
    .. '<script src="'
    .. asset_src("morphdom-2.7.4.min.js", "https://cdn.jsdelivr.net/npm/morphdom@2.7.4/dist/morphdom-umd.min.js")
    .. '"></script>'
  if highlight_link ~= "" then
    core_scripts = core_scripts .. "\n" .. highlight_link
  end
  core_scripts = core_scripts
    .. '\n<script src="'
    .. asset_src("highlight-11.min.js", "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11/build/highlight.min.js")
    .. '"></script>'

  local mermaid_tags = ""
  if opts.notations and opts.notations.mermaid and opts.notations.mermaid.enable ~= false then
    mermaid_tags = '<script src="'
      .. asset_src("mermaid-11.4.1.min.js", "https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.min.js")
      .. '"></script>'
  end

  local katex_tags = ""
  if opts.notations and opts.notations.katex and opts.notations.katex.enable ~= false then
    katex_tags = '<link rel="stylesheet" href="'
      .. asset_src("katex-0.16.38.min.css", "https://cdn.jsdelivr.net/npm/katex@0.16.38/dist/katex.min.css")
      .. '">\n'
      .. '<script src="'
      .. asset_src("katex-0.16.38.min.js", "https://cdn.jsdelivr.net/npm/katex@0.16.38/dist/katex.min.js")
      .. '"></script>\n'
      .. '<script src="'
      .. asset_src("texmath-1.0.0.js", "https://cdn.jsdelivr.net/npm/markdown-it-texmath@1.0.0/texmath.js")
      .. '"></script>'
  end

  local graphviz_tags = ""
  if opts.notations and opts.notations.graphviz and opts.notations.graphviz.enable ~= false then
    graphviz_tags = '<script src="'
      .. asset_src("viz-3.25.0.js", "https://cdn.jsdelivr.net/npm/@viz-js/viz@3.25.0/dist/viz-global.js")
      .. '"></script>'
  end

  local wavedrom_tags = ""
  if opts.notations and opts.notations.wavedrom and opts.notations.wavedrom.enable ~= false then
    wavedrom_tags = '<script src="'
      .. asset_src("wavedrom-3.5.0-skin-default.js", "https://cdn.jsdelivr.net/npm/wavedrom@3.5.0/skins/default.js")
      .. '"></script>\n'
      .. '<script src="'
      .. asset_src("wavedrom-3.5.0.min.js", "https://cdn.jsdelivr.net/npm/wavedrom@3.5.0/wavedrom.min.js")
      .. '"></script>'
  end

  local nomnoml_tags = ""
  if opts.notations and opts.notations.nomnoml and opts.notations.nomnoml.enable ~= false then
    nomnoml_tags = '<script src="'
      .. asset_src("graphre-0.1.3.js", "https://cdn.jsdelivr.net/npm/graphre@0.1.3/dist/graphre.js")
      .. '"></script>\n'
      .. '<script src="'
      .. asset_src("nomnoml-1.6.2.min.js", "https://cdn.jsdelivr.net/npm/nomnoml@1.6.2/dist/nomnoml.min.js")
      .. '"></script>'
  end

  local abcjs_tag = ""
  if opts.notations and opts.notations.abc and opts.notations.abc.enable ~= false then
    abcjs_tag = '<script src="'
      .. asset_src("abcjs-6.4.4-basic.min.js", "https://cdn.jsdelivr.net/npm/abcjs@6.4.4/dist/abcjs-basic-min.js")
      .. '"></script>'
  end

  local vegalite_tags = ""
  if opts.notations and opts.notations.vegalite and opts.notations.vegalite.enable ~= false then
    vegalite_tags = '<script src="'
      .. asset_src("vega-5.30.0.min.js", "https://cdn.jsdelivr.net/npm/vega@5.30.0/build/vega.min.js")
      .. '"></script>\n'
      .. '<script src="'
      .. asset_src("vega-lite-5.21.0.min.js", "https://cdn.jsdelivr.net/npm/vega-lite@5.21.0/build/vega-lite.min.js")
      .. '"></script>\n'
      .. '<script src="'
      .. asset_src("vega-embed-6.26.0.min.js", "https://cdn.jsdelivr.net/npm/vega-embed@6.26.0/build/vega-embed.min.js")
      .. '"></script>'
  end

  local mermaid_theme = opts.mermaid and opts.mermaid.theme or "default"
  if not VALID_MERMAID_THEMES[mermaid_theme] then
    mermaid_theme = "default"
  end

  return {
    core_scripts = core_scripts,
    mermaid_tags = mermaid_tags,
    katex = katex_tags,
    graphviz = graphviz_tags,
    wavedrom = wavedrom_tags,
    nomnoml = nomnoml_tags,
    abcjs = abcjs_tag,
    vegalite = vegalite_tags,
    mermaid_theme = mermaid_theme,
  }
end

function M.render(opts, filename)
  local tmpl = load_template()
  if not tmpl then
    return ""
  end
  local css = opts.css or ""
  local title = filename and filename ~= "" and filename or "md-view"
  local theme_css = opts.theme_css or ""
  local palette_css = opts.palette_css or ""
  title = html_escape(title)

  local tags = build_script_tags(opts)

  local html = tmpl
    :gsub("{{PALETTE_CSS}}", function()
      return palette_css
    end)
    :gsub("{{THEME_CSS}}", function()
      return theme_css
    end)
    :gsub("{{CSS}}", function()
      return css
    end)
    :gsub("{{MERMAID_THEME}}", function()
      return tags.mermaid_theme
    end)
    :gsub("{{CORE_SCRIPTS}}", function()
      return tags.core_scripts
    end)
    :gsub("{{MERMAID_TAGS}}", function()
      return tags.mermaid_tags
    end)
    :gsub("{{KATEX}}", function()
      return tags.katex
    end)
    :gsub("{{GRAPHVIZ}}", function()
      return tags.graphviz
    end)
    :gsub("{{WAVEDROM}}", function()
      return tags.wavedrom
    end)
    :gsub("{{NOMNOML}}", function()
      return tags.nomnoml
    end)
    :gsub("{{ABCJS}}", function()
      return tags.abcjs
    end)
    :gsub("{{VEGALITE}}", function()
      return tags.vegalite
    end)
    :gsub("{{TITLE}}", function()
      return title
    end)
  return html
end

-- Three states: nil = not yet tried, false = failed, string = loaded
local HUB_TEMPLATE

local function load_hub_template()
  if type(HUB_TEMPLATE) == "string" then
    return HUB_TEMPLATE
  end
  if HUB_TEMPLATE == false then
    return nil
  end
  local path = vim.api.nvim_get_runtime_file("assets/hub.html", false)[1]
  if not path then
    vim.notify("md-view.nvim: could not find assets/hub.html in runtimepath", vim.log.levels.ERROR)
    HUB_TEMPLATE = false
    return nil
  end
  local fh, err = io.open(path, "rb")
  if not fh then
    vim.notify("md-view.nvim: could not open " .. path .. ": " .. (err or ""), vim.log.levels.ERROR)
    HUB_TEMPLATE = false
    return nil
  end
  local content = fh:read("*a")
  fh:close()
  if not content or content == "" then
    vim.notify("md-view.nvim: assets/hub.html is empty or unreadable", vim.log.levels.ERROR)
    HUB_TEMPLATE = false
    return nil
  end
  HUB_TEMPLATE = content
  return HUB_TEMPLATE
end

-- Render the hub shell page. Same CDN scripts as render(); title is "md-view".
function M.render_hub(opts)
  local tmpl = load_hub_template()
  if not tmpl then
    return ""
  end
  opts = opts or {}
  local tags = build_script_tags(opts)
  local css = opts.css or ""
  local theme_css = opts.theme_css or ""
  local palette_css = opts.palette_css or ""
  return tmpl
    :gsub("{{PALETTE_CSS}}", function()
      return palette_css
    end)
    :gsub("{{THEME_CSS}}", function()
      return theme_css
    end)
    :gsub("{{CSS}}", function()
      return css
    end)
    :gsub("{{MERMAID_THEME}}", function()
      return tags.mermaid_theme
    end)
    :gsub("{{CORE_SCRIPTS}}", function()
      return tags.core_scripts
    end)
    :gsub("{{MERMAID_TAGS}}", function()
      return tags.mermaid_tags
    end)
    :gsub("{{KATEX}}", function()
      return tags.katex
    end)
    :gsub("{{GRAPHVIZ}}", function()
      return tags.graphviz
    end)
    :gsub("{{WAVEDROM}}", function()
      return tags.wavedrom
    end)
    :gsub("{{NOMNOML}}", function()
      return tags.nomnoml
    end)
    :gsub("{{ABCJS}}", function()
      return tags.abcjs
    end)
    :gsub("{{VEGALITE}}", function()
      return tags.vegalite
    end)
end

return M
