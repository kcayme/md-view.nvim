# md-view.nvim

Browser-based markdown preview for Neovim with live mermaid diagram rendering.

![Demo](docs/demo/demo.gif)

## Features

- **Live preview** — the browser updates within ~300ms of each edit, with scroll sync
- **Mermaid and more** — mermaid, KaTeX, Graphviz, WaveDrom, Nomnoml, ABC and Vega-Lite render out of the box, with inline syntax errors
- **Zero dependencies** — pure Lua, no Node.js or Deno; rendering happens in the browser via CDN (`curl` optional for offline assets)
- **Syntax highlighting** — fenced code blocks via [highlight.js](https://highlightjs.org) with configurable themes
- **Colorscheme sync** — mirror your Neovim colorscheme in the preview, live
- **Multi-buffer** — one preview per buffer; `:MdViewList` jumps between them
- **Single page mode** — all previews in one browser tab
- **Table of contents** — collapsible sidebar with active-heading tracking
- **Terminal preview** — render inside a Neovim split or tmux pane via the kitty graphics protocol
- **Auto-cleanup** — servers shut down when buffers close or Neovim exits

## Requirements

- Neovim >= 0.8
- A web browser
- Terminal preview only: kitty, Ghostty or WezTerm, plus a Chromium-based browser

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{ "kcayme/md-view.nvim" }
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use("kcayme/md-view.nvim")
```

## Configuration

`setup()` is optional since every option has a default. See [docs/options.md](docs/options.md) for the full reference. Adding `---@type MdViewOptions` enables LSP completion and hover docs:

```lua
---@type MdViewOptions
require("md-view").setup({
  -- Port for the local preview server. 0 = auto-assign a free port.
  port = 0,
  -- Bind address. Must be a loopback address (127.0.0.1, ::1, localhost).
  host = "127.0.0.1",
  -- Browser executable. nil = auto-detect (open/xdg-open/cmd /c start).
  browser = nil,
  -- Milliseconds to debounce buffer updates before pushing to the browser.
  debounce_ms = 300,
  -- Custom CSS string injected into the preview page.
  css = nil,
  -- Auto-close the browser tab when the preview is stopped.
  auto_close = true,
  -- Show [md-view] notifications on open/stop.
  verbose = true,
  -- Open a new browser tab when entering a buffer that already has a preview.
  follow_focus = false,
  -- Scroll sync: "percentage" (proportional offset) or "cursor" (nearest source line).
  scroll = {
    method = "cursor", -- "percentage" | "cursor"
  },
  -- Color theme for the preview page.
  theme = {
    -- "auto" (follows 'background') | "dark" | "light" | "sync" (mirrors colorscheme live).
    mode = "auto",
    -- highlight.js theme for code blocks. nil = "vs2015" (dark) / "github" (light).
    syntax = nil,
    -- Highlight group overrides for CSS variable extraction (only used when mode = "sync").
    highlights = {},
  },
  notations = {
    -- Set enable = false on a notation to skip loading its library.
    mermaid = {
      enable = true,
      theme = nil, -- nil = auto-chosen per theme
      security_level = "strict", -- "strict" | "antiscript" | "loose" | "sandbox"
    },
    katex = { enable = true }, -- math fences and $...$ / $$...$$ inline math
    graphviz = { enable = true }, -- dot / graphviz fences
    wavedrom = { enable = true }, -- wavedrom fences
    nomnoml = { enable = true }, -- nomnoml fences
    abc = { enable = true }, -- abc music notation fences
    vegalite = { enable = true }, -- vega-lite fences
  },
  -- Filetypes :MdView will preview. {} = any filetype.
  filetypes = { "markdown" },
  -- Auto-open (or re-focus) a preview when entering a qualifying buffer.
  auto_open = {
    enable = false,
    -- Neovim events that trigger the auto-open check.
    events = { "BufWinEnter" },
  },
  -- :MdViewList picker; works with any vim.ui.select replacement.
  picker = {
    -- Title/prompt shown at the top of the picker.
    prompt = "Markdown Previews",
    -- function(item) -> string; item = { bufnr, port, name }. nil = "name  http://host:port".
    format_item = nil,
    -- Passed as opts.kind to vim.ui.select.
    kind = nil,
  },
  -- Single-page mode: all previews share one browser tab (uses top-level `port`).
  single_page = {
    enable = false,
    -- "filename" | "relative" | "parent" | function(ctx) -> string; ctx = { bufnr, filename, path }.
    tab_label = "parent",
    -- nil (inherit `auto_close`) | "page" (close window after last preview) | "tab" | false (= "tab").
    close_by = nil,
  },
  -- Table of contents sidebar shown alongside the preview.
  table_of_contents = {
    enable = false,
    position = "left", -- "left" | "right"
    max_depth = 6, -- 1–6; headings deeper than this are omitted
  },
  -- Brief "Updated" pill shown in the preview after live changes land.
  toast = {
    enable = true,
    debounce_ms = 500, -- quiet period before the pill appears
    duration_ms = 3000, -- how long it stays visible
    position = "top-right", -- "bottom-left" | "bottom-right" | "top-left" | "top-right"
  },
  preview = {
    -- "browser" | "split" | "tmux" (split/tmux render in-terminal via kitty graphics).
    target = "browser",
    terminal = {
      -- Chromium-based executable for headless rendering. nil = best-effort auto-detect
      -- (PATH, Playwright/Puppeteer caches, macOS app bundles); set a full path if it isn't found.
      browser = nil,
      -- Device scale factor for the rendered page.
      scale = 1,
      -- Quiet time (ms) after the viewer is resized before it re-renders.
      resize_debounce_ms = 200,
    },
  },
})
```

## Usage

| Command | Description |
|---------|-------------|
| `:MdView [target]` | Open a preview for the current buffer. `target` is `browser`, `split` or `tmux`; any other value is used as the browser command (e.g. `:MdView firefox`). |
| `:MdViewStop` | Stop the preview |
| `:MdViewClose [all]` | Close preview panel(s) without stopping the server |
| `:MdViewRestart` | Restart all active preview servers |
| `:MdViewToggle` | Toggle the preview on/off |
| `:MdViewList` | Pick from all active previews |
| `:MdViewAutoOpen` | Toggle automatic preview on buffer enter |
| `:MdViewTheme [mode]` | Switch the live theme (`dark`, `light`, `auto`, `sync`); no argument cycles |
| `:MdViewFetchAssets` | Re-fetch vendor assets for offline use |

The plugin sets no keymaps. Bind the commands yourself:

```lua
vim.keymap.set("n", "<leader>mp", "<cmd>MdViewToggle<cr>", { desc = "Toggle markdown preview" })
```

## Recipes

- [Theming](docs/recipes/theming.md) — syntax themes, custom CSS, colorscheme sync
- [Notations](docs/recipes/notations.md) — supported notations; enabling and configuring them
- [Filetypes](docs/recipes/filetypes.md) — restrict or expand which buffer filetypes open a preview
- [Auto-open](docs/recipes/auto-open.md) — open previews automatically on buffer enter; lazy.nvim setup
- [Picker integration](docs/recipes/picker-integration.md) — dressing.nvim, Telescope, fzf-lua, snacks.nvim, mini.pick
- [Single-page mode](docs/recipes/single-page-mode.md) — multiplex all previews into one browser tab

## Comparison

| | md-view.nvim | [markdown-preview.nvim](https://github.com/iamcco/markdown-preview.nvim) | [peek.nvim](https://github.com/toppair/peek.nvim) | [glow.nvim](https://github.com/ellisonleao/glow.nvim) | [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim) | [markview.nvim](https://github.com/OXY2DEV/markview.nvim) |
|---|---|---|---|---|---|---|
| **Runtime dependency** | None (curl optional) | Node.js + yarn | Deno | glow CLI (Go) | None | None |
| **Renders where** | Browser | Browser | Webview / Browser | Terminal float | Inline (extmarks) | Inline (extmarks) |
| **Mermaid diagrams** | Yes | Yes | Yes | No | No | No |
| **Notation support** | Mermaid, KaTeX, Graphviz, WaveDrom, Nomnoml, ABC, Vega-Lite | Mermaid | Mermaid | None | None | None |
| **Live reload** | Yes | Yes | Yes | No | Yes | Yes |
| **Scroll sync** | Yes | Yes | Yes | No | N/A | Yes (splitview) |
| **Maintained** | Yes | Yes | Yes | Archived | Yes | Yes |

## License

[MIT](LICENSE)
