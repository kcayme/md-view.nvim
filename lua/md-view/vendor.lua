local M = {}

local uv = vim.uv or vim.loop
local util = require("md-view.util")

local fetching = false

local MANIFEST = {
  {
    name = "markdown-it-14.1.0.min.js",
    url = "https://cdn.jsdelivr.net/npm/markdown-it@14.1.0/dist/markdown-it.min.js",
  },
  {
    name = "markdown-it-task-lists-2.1.1.min.js",
    url = "https://cdn.jsdelivr.net/npm/markdown-it-task-lists@2.1.1/dist/markdown-it-task-lists.min.js",
  },
  {
    name = "mermaid-11.4.1.min.js",
    url = "https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.min.js",
  },
  {
    name = "morphdom-2.7.4.min.js",
    url = "https://cdn.jsdelivr.net/npm/morphdom@2.7.4/dist/morphdom-umd.min.js",
  },
  {
    name = "highlight-11.min.js",
    url = "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11/build/highlight.min.js",
  },
  -- highlight-theme-{name}.min.css files are inserted dynamically at fetch() time (after highlight-11.min.js)
  {
    name = "katex-0.16.38.min.css",
    url = "https://cdn.jsdelivr.net/npm/katex@0.16.38/dist/katex.min.css",
  },
  {
    name = "katex-0.16.38.min.js",
    url = "https://cdn.jsdelivr.net/npm/katex@0.16.38/dist/katex.min.js",
  },
  {
    name = "texmath-1.0.0.js",
    url = "https://cdn.jsdelivr.net/npm/markdown-it-texmath@1.0.0/texmath.js",
  },
  {
    name = "viz-3.25.0.js",
    url = "https://cdn.jsdelivr.net/npm/@viz-js/viz@3.25.0/dist/viz-global.js",
  },
  {
    name = "wavedrom-3.5.0-skin-default.js",
    url = "https://cdn.jsdelivr.net/npm/wavedrom@3.5.0/skins/default.js",
  },
  {
    name = "wavedrom-3.5.0.min.js",
    url = "https://cdn.jsdelivr.net/npm/wavedrom@3.5.0/wavedrom.min.js",
  },
  {
    name = "graphre-0.1.3.js",
    url = "https://cdn.jsdelivr.net/npm/graphre@0.1.3/dist/graphre.js",
  },
  {
    name = "nomnoml-1.6.2.min.js",
    url = "https://cdn.jsdelivr.net/npm/nomnoml@1.6.2/dist/nomnoml.min.js",
  },
  {
    name = "abcjs-6.4.4-basic.min.js",
    url = "https://cdn.jsdelivr.net/npm/abcjs@6.4.4/dist/abcjs-basic-min.js",
  },
  {
    name = "vega-5.30.0.min.js",
    url = "https://cdn.jsdelivr.net/npm/vega@5.30.0/build/vega.min.js",
  },
  {
    name = "vega-lite-5.21.0.min.js",
    url = "https://cdn.jsdelivr.net/npm/vega-lite@5.21.0/build/vega-lite.min.js",
  },
  {
    name = "vega-embed-6.26.0.min.js",
    url = "https://cdn.jsdelivr.net/npm/vega-embed@6.26.0/build/vega-embed.min.js",
  },
}

M.vendor_dir = function()
  return vim.fn.stdpath("data") .. "/md-view.nvim/vendor"
end

M.is_available = function()
  local dir = M.vendor_dir()

  for _, entry in ipairs(MANIFEST) do
    local stat, err = uv.fs_stat(dir .. "/" .. entry.name)
    if err or not stat then
      return false
    end
  end

  return true
end

---@param name string highlight.js theme name (e.g. "github", "vs2015")
---@return boolean
M.has_theme = function(name)
  name = name:gsub("[^%w_%-]", "")
  local stat, err = uv.fs_stat(M.vendor_dir() .. "/highlight-theme-" .. name .. ".min.css")

  return not err and stat ~= nil
end

---@param name string highlight.js theme name (e.g. "github", "vs2015")
---@return string URL for the highlight.js theme CSS (vendor path or CDN)
M.hljs_url = function(name)
  name = name:gsub("[^%w_%-]", "")

  if M.is_available() and M.has_theme(name) then
    return "/vendor/highlight-theme-" .. name .. ".min.css"
  end

  return "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11/build/styles/" .. name .. ".min.css"
end

M.fetch = function(opts)
  opts = opts or {}

  if fetching then
    util.notify(nil, "md-view.nvim: asset fetch already in progress", vim.log.levels.WARN)

    return
  end

  fetching = true

  -- Collect and deduplicate highlight themes to fetch.
  -- Accepts opts.highlight_themes (array), opts.highlight_theme (single, backward compat),
  -- or defaults to both built-in light ("github") and dark ("vs2015") themes.
  local highlight_themes = {}
  local seen = {}

  local function add_theme(raw)
    local name = (raw or ""):gsub("[^%w_%-]", "")
    if name == "" then
      name = "vs2015"
    end
    if not seen[name] then
      seen[name] = true
      highlight_themes[#highlight_themes + 1] = name
    end
  end

  if opts.highlight_themes then
    for _, t in ipairs(opts.highlight_themes) do
      add_theme(t)
    end
  elseif opts.highlight_theme then
    add_theme(opts.highlight_theme)
  else
    add_theme("github")
    add_theme("vs2015")
  end

  if vim.fn.executable("curl") ~= 1 then
    fetching = false
    util.notify(nil, "md-view.nvim: curl is required to fetch vendor assets", vim.log.levels.ERROR)

    return
  end

  local dir = M.vendor_dir()

  if vim.fn.mkdir(dir, "p") == 0 then
    fetching = false
    util.notify(nil, "md-view.nvim: could not create vendor dir: " .. dir, vim.log.levels.ERROR)

    return
  end

  -- Build the full list of files to download: static manifest + per-theme highlight CSS files.
  local files = {}

  for _, entry in ipairs(MANIFEST) do
    files[#files + 1] = { name = entry.name, url = entry.url }
    -- Insert highlight theme CSS files after highlight-11.min.js
    if entry.name == "highlight-11.min.js" then
      for _, name in ipairs(highlight_themes) do
        files[#files + 1] = {
          name = "highlight-theme-" .. name .. ".min.css",
          url = "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11/build/styles/" .. name .. ".min.css",
        }
      end
    end
  end

  local total = #files
  local done = 0
  local failed = 0

  for _, file in ipairs(files) do
    local dest = dir .. "/" .. file.name
    local filename = file.name
    local url = file.url

    vim.fn.jobstart({ "curl", "-fsSL", "-o", dest, url }, {
      on_exit = function(_, exit_code)
        vim.schedule(function()
          if exit_code == 0 then
            done = done + 1
          else
            failed = failed + 1

            util.notify(nil, "md-view.nvim: failed to download " .. filename, vim.log.levels.WARN)
          end

          if done + failed == total then
            fetching = false

            if failed == 0 then
              util.notify(nil, "md-view.nvim: All " .. total .. " vendor assets downloaded", vim.log.levels.INFO)
            else
              util.notify(
                nil,
                "md-view.nvim: " .. done .. "/" .. total .. " vendor assets downloaded (" .. failed .. " failed)",
                vim.log.levels.WARN
              )
            end
          end
        end)
      end,
    })
  end
end

return M
