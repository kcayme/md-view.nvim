local M = {}

local uv = vim.uv or vim.loop

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
  -- highlight-theme.min.css is inserted dynamically at fetch() time (after highlight-11.min.js)
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
  -- Check the 17 static files from MANIFEST
  for _, entry in ipairs(MANIFEST) do
    local stat = uv.fs_stat(dir .. "/" .. entry.name)
    if not stat then
      return false
    end
  end
  -- Check the dynamic highlight-theme.min.css file
  local stat = uv.fs_stat(dir .. "/highlight-theme.min.css")
  if not stat then
    return false
  end
  return true
end

M.fetch = function(opts)
  opts = opts or {}
  if fetching then
    vim.notify("md-view.nvim: asset fetch already in progress", vim.log.levels.WARN)
    return
  end

  fetching = true

  local highlight_theme = opts.highlight_theme or "vs2015"
  highlight_theme = highlight_theme:gsub("[^%w_%-]", "")

  if highlight_theme == "" then
    highlight_theme = "vs2015"
  end

  if vim.fn.executable("curl") ~= 1 then
    fetching = false
    vim.notify("md-view.nvim: curl is required to fetch vendor assets", vim.log.levels.ERROR)
    return
  end

  local dir = M.vendor_dir()

  if vim.fn.mkdir(dir, "p") == 0 then
    fetching = false
    vim.notify("md-view.nvim: could not create vendor dir: " .. dir, vim.log.levels.ERROR)
    return
  end

  -- Build the full list of files to download: static manifest + dynamic highlight theme CSS
  local files = {}

  for _, entry in ipairs(MANIFEST) do
    files[#files + 1] = { name = entry.name, url = entry.url }
    -- Insert highlight-theme.min.css after highlight-11.min.js (after position 5 in MANIFEST)
    if entry.name == "highlight-11.min.js" then
      files[#files + 1] = {
        name = "highlight-theme.min.css",
        url = "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11/build/styles/" .. highlight_theme .. ".min.css",
      }
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
            vim.notify("md-view.nvim: failed to download " .. filename, vim.log.levels.WARN)
          end

          if done + failed == total then
            fetching = false
            if failed == 0 then
              vim.notify("md-view.nvim: All " .. total .. " vendor assets downloaded", vim.log.levels.INFO)
            else
              vim.notify(
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
