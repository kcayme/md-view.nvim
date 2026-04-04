# md-view.nvim

Browser-based markdown preview for Neovim with live mermaid diagram rendering.

Opens a browser tab that renders your markdown buffer — including mermaid diagrams as SVG — and updates live as you type. Scroll sync keeps the browser viewport aligned with your cursor position.

![Demo](docs/demo/demo.gif)
![Colorscheme Sync](docs/demo/colorscheme-sync.png)
![Single Page Mode](docs/demo/single-page.png)

## Why another markdown preview plugin?

I heavily use mermaid diagrams in my markdown files. The in-editor previewers I tried don't render them,
and the browser-based ones that do (like markdown-preview.nvim) need Node.js or Deno
installed. I wanted something that's lightweight and just works out of the box — no runtime, no setup.

- **Mermaid out of the box** — most previewers can't render mermaid diagrams at all.
  The ones that can need a Node.js or Deno runtime. This one just loads mermaid.js from
  CDN and gets out of the way.

- **Zero dependencies** — no Node.js, no Deno, no external binaries. Pure Lua, all
  rendering delegated to the browser via CDN. (`curl` is optionally required for
  one-time offline asset fetching via `:MdViewFetchAssets`.)

- **Preview picker** — I often have multiple markdown files open at the same time.
  `:MdViewList` lets me see and jump between all active previews without digging through
  buffers.

  ![Picker](docs/demo/picker.png)

- **Error feedback** — when I mess up a diagram's syntax, mermaid.js shows an inline
  error in the browser right away. Fast feedback loop for iterating on diagrams.

  ![Error feedback](docs/demo/error-feedback.png)

## Features

- **Live preview** — browser updates within ~300ms of each edit
- **Mermaid diagrams** — fenced `mermaid` code blocks render as SVG
- **Syntax highlighting** — fenced code blocks highlighted via [highlight.js](https://highlightjs.org) with configurable themes
- **Scroll sync** — browser follows your cursor as you navigate the buffer
- **Zero dependencies** — pure Lua, no Node.js/Deno/external processes (`curl` optional for offline asset fetch)
- **Multi-buffer** — each buffer gets its own server on an auto-assigned port
- **Auto-cleanup** — servers shut down when buffers close or Neovim exits
- **Single Page Mode** — preview all your markdown files in 1 browser tab
- **Table of Contents** — collapsible TOC sidebar with active-heading tracking and click-to-scroll

## Requirements

- Neovim >= 0.8
- A web browser

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

`setup()` is optional — all options have sensible defaults. Adding `---@type MdViewOptions` above your call enables LSP completion and hover docs. See [docs/options.md](docs/options.md) for the full reference.

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
  -- When true, always opens a new browser tab when switching to a buffer that
  -- already has an active preview (via :MdView or auto_open). This ensures the
  -- browser always shows the preview for the current buffer, at the cost of
  -- breaking any split-tab arrangement in the browser.
  follow_focus = false,
  -- Scroll sync method. "percentage" syncs by proportional scroll offset.
  -- "cursor" anchors to the nearest source line in the preview DOM.
  scroll = {
    method = "percentage",  -- "percentage" | "cursor"
  },
  -- Color theme for the preview page.
  theme = {
    -- One of: "auto", "dark", "light", "sync"
    -- "auto" follows Neovim's background setting; "sync" mirrors your colorscheme live.
    mode = "auto",
    -- highlight.js theme for fenced code blocks. See Syntax Highlighting Themes below.
    -- nil auto-selects: "vs2015" for dark themes, "github" for light themes.
    syntax = nil,
    -- Highlight group overrides for CSS variable extraction (only used when mode = "sync").
    highlights = {},
  },
  notations = {
    -- Each notation has an `enable` field (default true) and optional config.
    -- Set enable = false to skip loading the library (saves bandwidth).
    mermaid  = { enable = true, theme = nil },  -- nil = auto-chosen per theme
    katex    = { enable = true },   -- math fences and $...$ / $$...$$ inline math
    graphviz = { enable = true },   -- dot / graphviz fences
    wavedrom = { enable = true },   -- wavedrom fences
    nomnoml  = { enable = true },   -- nomnoml fences
    abc      = { enable = true },   -- abc music notation fences
    vegalite = { enable = true },   -- vega-lite fences
  },
  -- Filetypes this plugin will preview. Running :MdView on a buffer whose
  -- filetype is not in this list emits a warning and does nothing.
  -- Set to {} to allow any filetype.
  filetypes = { "markdown" },
  -- Automatically open (or re-focus) a preview whenever you enter a qualifying
  -- buffer. Opt-in; disabled by default.
  auto_open = {
    enable = false,
    -- Neovim events that trigger the auto-open check.
    events = { "BufWinEnter" },
  },
  -- Customise the :MdViewList picker (vim.ui.select).
  -- Works with any vim.ui.select replacement (Telescope, fzf-lua, snacks, dressing.nvim, etc.).
  picker = {
    -- Title/prompt shown at the top of the picker.
    prompt = "Markdown Previews",
    -- Custom item formatter. function(item) → string.
    -- item has: .bufnr, .port, .name (basename of the file).
    -- nil uses the built-in "name  http://host:port" format.
    format_item = nil,
    -- Hint passed as opts.kind to vim.ui.select. Some pickers use this
    -- to provide a specialised UI (e.g. a file-preview pane).
    kind = nil,
  },
  -- Single-page mode: all active previews share one browser tab.
  -- The mux server uses the top-level `port` option (0 = OS-assigned).
  single_page = {
    enable = false,
    -- How to label each preview's tab in the hub page.
    -- "filename"  — basename only (e.g. "README.md")
    -- "relative"  — path relative to cwd (e.g. "docs/README.md")
    -- "parent"    — parent dir + basename (e.g. "docs/README.md")
    -- function(ctx) — custom label; ctx = { bufnr, filename, path }
    tab_label = "parent",
    -- What to close when a preview ends (overrides top-level `auto_close`).
    -- nil    — inherit from top-level `auto_close`
    -- "page" — close the browser window when the last preview ends
    -- "tab"  — only remove the preview's tab; keep the window open
    -- false  — same as "tab"
    close_by = nil,
  },
  -- Table of contents sidebar shown alongside the preview.
  -- Off by default — opt in explicitly.
  table_of_contents = {
    enable   = false,
    position = "left",   -- "left" | "right"
    max_depth = 6,        -- 1–6; headings deeper than this are omitted
  },
})
```

### Type specification

Full [LuaLS / EmmyLua](https://luals.github.io/wiki/annotations/) types for the configuration. Adding `---@type MdViewOptions` above your `setup()` call enables completion and hover docs in any editor with `lua-language-server` configured.

<details>
<summary>Expand type definitions</summary>

```lua
---@alias MdViewThemeMode "auto"|"dark"|"light"|"sync"
---@alias MdViewScrollMethod "percentage"|"cursor"
---@alias MdViewTabLabel "filename"|"relative"|"parent"
---@alias MdViewCloseBy "page"|"tab"|false|nil

---@class MdViewTabLabelCtx Context passed to a custom `tab_label` function.
---@field bufnr integer Buffer number of the preview.
---@field filename string Basename of the file (e.g. `"README.md"`).
---@field path string Full absolute file path.

---@class MdViewScrollOptions
---@field method MdViewScrollMethod `"cursor"` anchors to the nearest source line; `"percentage"` syncs by proportional scroll offset.

---@class MdViewThemeOptions
---@field mode MdViewThemeMode `"auto"` follows `vim.o.background`; `"dark"`/`"light"` are fixed palettes; `"sync"` mirrors the active colorscheme via highlight group extraction.
---@field syntax string|nil highlight.js theme for fenced code blocks. `nil` = auto-select (`"vs2015"` for dark, `"github"` for light).
---@field highlights table<string, string|string[]> Highlight group overrides for CSS variable extraction. Single group name or ordered list — first group with the attribute wins. Only applied when `mode = "sync"`.

---@class MdViewNotationOptions
---@field enable boolean Load and render this notation. Set to `false` to skip loading the CDN library entirely.

---@alias MdViewMermaidSecurityLevel "strict"|"antiscript"|"loose"|"sandbox"

---@class MdViewMermaidNotationOptions : MdViewNotationOptions
---@field theme string|nil Mermaid diagram theme. `nil` = auto-chosen based on the page theme.
---@field security_level MdViewMermaidSecurityLevel Mermaid `securityLevel` option. Default: `"strict"`.

---@class MdViewNotationsOptions
---@field mermaid MdViewMermaidNotationOptions `mermaid` fenced code blocks rendered as SVG diagrams.
---@field katex MdViewNotationOptions `math` fences and `$...$` / `$$...$$` inline math via KaTeX.
---@field graphviz MdViewNotationOptions `dot` / `graphviz` fences rendered via Graphviz (@viz-js/viz).
---@field wavedrom MdViewNotationOptions `wavedrom` fences rendered as digital timing diagrams.
---@field nomnoml MdViewNotationOptions `nomnoml` fences rendered as UML diagrams.
---@field abc MdViewNotationOptions `abc` fences rendered as sheet music via abcjs.
---@field vegalite MdViewNotationOptions `vega-lite` fences rendered as Vega-Lite charts.

---@class MdViewAutoOpenOptions
---@field enable boolean Automatically open (or refocus) a preview whenever entering a qualifying buffer.
---@field events string[] Neovim events that trigger the auto-open check. Default: `{ "BufWinEnter" }`.

---@class MdViewPickerOptions
---@field prompt string Title/prompt shown at the top of the `:MdViewList` picker.
---@field format_item (fun(item: table): string)|nil Custom item formatter. `item` exposes `.bufnr`, `.port`, `.name` (basename). `nil` = built-in `"name  http://host:port"` format.
---@field kind string|nil Hint passed as `opts.kind` to `vim.ui.select`. Some pickers use this to render a specialised UI (e.g. a file-preview pane).

---@class MdViewSinglePageOptions
---@field enable boolean Multiplex all active previews into one browser tab via a hub server.
---@field tab_label MdViewTabLabel|(fun(ctx: MdViewTabLabelCtx): string) Label for each preview tab. `"filename"` = basename; `"relative"` = path from cwd; `"parent"` = parent dir + basename; or a custom function.
---@field close_by MdViewCloseBy What to close when a preview ends. `nil` = inherit top-level `auto_close`; `"page"` = close the browser window when the last preview ends; `"tab"` / `false` = remove the tab only.

---@alias MdViewTocPosition "left"|"right"

---@class MdViewTableOfContentsOptions
---@field enable boolean Show a collapsible TOC sidebar alongside the preview. Off by default.
---@field position MdViewTocPosition Which side of the preview the sidebar appears on. Default: `"left"`.
---@field max_depth integer Maximum heading level shown (`1`–`6`). Headings deeper than this are omitted. Default: `6`.

---@class MdViewOptions
---@field port integer Port for the local preview server. `0` = auto-assign a free port (recommended).
---@field host string Bind address. Must be a loopback address (`127.0.0.1`, `::1`, `localhost`).
---@field browser string|nil Browser executable to launch. `nil` = auto-detect via `open` / `xdg-open` / `cmd /c start`.
---@field bufnr integer|nil Target buffer number. `nil` = current buffer at the time `:MdView` is called.
---@field debounce_ms integer Milliseconds to debounce buffer content updates before pushing to the browser. Default: `300`.
---@field css string|nil Raw CSS string injected into the preview page after all built-in styles. Use to override layout, typography, or CSS custom properties.
---@field auto_close boolean Close the browser tab automatically when the preview is stopped.
---@field verbose boolean Show `[md-view]` notifications on open/stop.
---@field follow_focus boolean Reopen the browser tab when switching to a buffer that already has an active preview.
---@field scroll MdViewScrollOptions Scroll-sync settings.
---@field theme MdViewThemeOptions Color theme settings.
---@field notations MdViewNotationsOptions Notation renderer settings (mermaid, katex, graphviz, …).
---@field filetypes string[] Buffer filetypes this plugin will preview. `{}` = allow any filetype.
---@field auto_open MdViewAutoOpenOptions Automatic preview-on-enter settings.
---@field picker MdViewPickerOptions `:MdViewList` picker settings.
---@field single_page MdViewSinglePageOptions Single-page (hub) mode settings.
```

</details>


### Syntax Highlighting Themes

Fenced code blocks with a language tag (e.g. ` ```lua `, ` ```python `) are syntax highlighted using [highlight.js](https://highlightjs.org). Set `theme.syntax` to any theme from the [highlight.js demo](https://highlightjs.org/demo).

Some popular dark themes:

| Theme | Description |
|-------|-------------|
| `"vs2015"` | Visual Studio 2015 dark (auto-selected for dark themes) |
| `"github-dark"` | GitHub dark theme |
| `"github-dark-dimmed"` | GitHub dark dimmed |
| `"atom-one-dark"` | Atom One Dark |
| `"monokai"` | Monokai |
| `"dracula"` | Dracula |
| `"nord"` | Nord |
| `"tokyo-night-dark"` | Tokyo Night dark |
| `"catppuccin-mocha"` | Catppuccin Mocha |

Some popular light themes (pair with custom `css` to change the background):

| Theme | Description |
|-------|-------------|
| `"github"` | GitHub light |
| `"vs"` | Visual Studio light |
| `"atom-one-light"` | Atom One Light |
| `"catppuccin-latte"` | Catppuccin Latte |

Example:

```lua
require("md-view").setup({
  theme = { syntax = "github-dark" },
  notations = {
    mermaid = { theme = "dark" },
  },
})
```

### Custom CSS

The `css` option injects a raw CSS string into the preview page's `<style>` block, after all built-in styles. Use it to override layout, typography, or colors.

The page uses CSS custom properties for theming. Override these to restyle any element without fighting specificity:

| Variable | Controls |
|----------|---------|
| `--md-bg` | Page background |
| `--md-fg` | Body text color |
| `--md-heading` | Heading color |
| `--md-bold` | Bold text color |
| `--md-muted` | Muted / secondary text (e.g. `h6`) |
| `--md-blockquote` | Blockquote text color |
| `--md-link` | Link color |
| `--md-code-fg` | Inline code text |
| `--md-code-bg` | Inline code and code block background |
| `--md-pre-fg` | Code block text color |
| `--md-border` | Borders, `<hr>`, table lines |
| `--md-checkbox` | Checkbox color |
| `--md-table-header-bg` | Table header background |
| `--md-row-alt` | Alternating table row background |

**Wider content area** (default `max-width` is `882px`):

```lua
require("md-view").setup({
  css = "body { max-width: 1100px; }",
})
```

**Custom font and larger base size:**

```lua
require("md-view").setup({
  css = [[
    body {
      font-family: "Georgia", serif;
      font-size: 16px;
      line-height: 1.8;
    }
  ]],
})
```

**Light theme with a warm background** (pair with a light syntax theme):

```lua
require("md-view").setup({
  theme = { mode = "light", syntax = "github" },
  css = [[
    :root {
      --md-bg: #faf8f5;
      --md-code-bg: #f0ede8;
    }
  ]],
})
```

**Full-width, no side padding** (useful on wide monitors):

```lua
require("md-view").setup({
  css = "body { max-width: none; padding: 0 48px; }",
})
```

### Neovim Colorscheme Sync

Set `theme.mode = "sync"` to mirror your current Neovim colorscheme in the preview. Colors are extracted from Neovim highlight groups and pushed to the browser via SSE on every `ColorScheme` event — no page reload needed.

```lua
require("md-view").setup({ theme = { mode = "sync" } })
```

![Colorscheme sync](docs/demo/colorscheme-sync.png)

Use `theme.highlights` to override which highlight groups are sampled per CSS variable. Values can be a single group name or a list — the first group that has the attribute wins:

```lua
require("md-view").setup({
  theme = {
    mode    = "sync",
    highlights = {
      heading = "@markup.heading",
      link    = { "MyLink", "Underlined" },
    },
  },
})
```

Available keys and their defaults (all keys only apply when `theme.mode = "sync"`):

| Key | CSS variable | Controls | Default groups (tried in order) |
|-----|-------------|----------|---------------------------------|
| `bg` | `--md-bg` | Page background | `Normal` (bg) |
| `fg` | `--md-fg` | Body text | `Normal` (fg) |
| `heading` | `--md-heading` | Headings | `Title`, `@markup.heading`, `Normal` (fg) |
| `bold` | `--md-bold` | Bold text | `@markup.strong`, `@markup.bold`, `Normal` (fg) |
| `muted` | `--md-muted` | Muted / secondary text | `Comment` (fg) |
| `blockquote` | `--md-blockquote` | Blockquote text | `@markup.quote`, `Comment`, `Normal` (fg) |
| `link` | `--md-link` | Hyperlinks | `@markup.link.url`, `@markup.link`, `Underlined` (fg) |
| `code` | `--md-code-fg` | Inline code text | `Statement`, `@markup.raw`, `String` (fg) |
| `code_bg` | `--md-code-bg` | Inline code and code block background | `CursorLine`, `Pmenu` (bg) |
| `pre_fg` | `--md-pre-fg` | Code block text | `Normal` (fg) |
| `border` | `--md-border` | Borders and dividers | `WinSeparator`, `VertSplit` (fg) |
| `checkbox` | `--md-checkbox` | Checkboxes | `DiagnosticInfo`, `Function` (fg) |
| `table_header_bg` | `--md-table-header-bg` | Table header background | `CursorLine`, `Pmenu` (bg) |
| `row_alt` | `--md-row-alt` | Alternating row background | `CursorLine` (bg) |

> **Note:** The `bold` key (`--md-bold`) defaults to `inherit` in the built-in `auto`/`dark`/`light` palettes. In `sync` mode it extracts the foreground color from the groups listed above.

`theme.highlights` has no effect when `theme.mode` is not `"sync"`.

### Notation Support

md-view.nvim renders notation languages embedded in markdown code fences. All notations are enabled by default and loaded via CDN — disable any to skip loading its library.

| Notation | Fence Language | Status |
|----------|---------------|--------|
| Mermaid  | `mermaid`     | Built-in |
| KaTeX    | `math` / `$...$` / `$$...$$` | Built-in |
| Graphviz | `dot`, `graphviz` | Built-in |
| WaveDrom | `wavedrom` | Built-in |
| Nomnoml  | `nomnoml` | Built-in |
| abcjs    | `abc` | Built-in |
| Vega-Lite | `vega-lite` | Built-in |

To disable a notation:

```lua
require("md-view").setup({
  notations = {
    katex = { enable = false }, -- skip loading KaTeX (~280 KB)
  },
})
```

To set a mermaid diagram theme:

```lua
require("md-view").setup({
  notations = {
    mermaid = { theme = "forest" },
  },
})
```

## Recipes

- [Filetypes](docs/recipes/filetypes.md) — restrict or expand which buffer filetypes open a preview
- [Auto-open](docs/recipes/auto-open.md) — open previews automatically on buffer enter; lazy.nvim setup
- [Picker integration](docs/recipes/picker-integration.md) — dressing.nvim, Telescope, fzf-lua, snacks.nvim, mini.pick
- [Single-page mode](docs/recipes/single-page-mode.md) — multiplex all previews into one browser tab

## Offline Support

md-view.nvim can work offline by caching vendor assets locally. This is useful when developing without internet access or for reproducible deployments.

### Auto-fetch on setup

`setup()` automatically fetches vendor assets the first time it runs (i.e. when the vendor directory doesn't exist yet). You'll see a notification immediately:

```
[md-view] Fetching vendor assets for offline use...
```

followed by a completion notification once all downloads finish. The fetch is non-blocking — setup completes immediately and the downloads happen in the background.

The 18 vendor libraries (markdown-it, mermaid, highlight.js, KaTeX, graphviz, wavedrom, nomnoml, abcjs, vega-lite, and their dependencies) are saved to `~/.local/share/nvim/md-view.nvim/vendor/`. The plugin automatically detects this directory and uses the cached assets instead of loading from CDN. If the vendor directory is missing or incomplete, it falls back to CDN.

### Re-fetching assets

Run `:MdViewFetchAssets` anytime to re-download the cached assets — for example after a partial failure, or to update to the latest versions.

To specify a custom highlight.js theme for the cached CSS:

```vim
:MdViewFetchAssets highlight_theme=github-dark
```

## Usage

### Commands

| Command                  | Description                                      |
|--------------------------|--------------------------------------------------|
| `:MdView [browser]`      | Open preview for the current buffer. Optional `browser` arg overrides the configured browser for this call (e.g. `:MdView firefox`). |
| `:MdViewStop`            | Stop the preview                                 |
| `:MdViewClose [all]`     | Close preview panel(s) without stopping the server |
| `:MdViewRestart`         | Restart all active preview servers                |
| `:MdViewToggle`          | Toggle the preview on/off                        |
| `:MdViewList`            | Pick from all active previews                    |
| `:MdViewAutoOpen`        | Toggle automatic preview on buffer enter on/off  |
| `:MdViewFetchAssets`     | Re-fetch vendor assets for offline use           |

### Keymaps

The plugin does not set any keymaps. Bind the commands yourself:

```lua
vim.keymap.set("n", "<leader>mp", "<cmd>MdViewToggle<cr>", { desc = "Toggle markdown preview" })
```

### Example

Given a markdown file with a mermaid block:

````markdown
# My Document

Some text here.

```mermaid
graph LR
  A --> B --> C
```
````

Running `:MdView` opens a browser tab with the rendered markdown and a live SVG diagram.

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

**Why md-view.nvim?**

- **No external runtime.** markdown-preview.nvim requires Node.js and yarn. peek.nvim requires Deno. glow.nvim requires a Go binary. md-view.nvim is pure Lua — it uses Neovim's built-in libuv TCP server and offloads rendering to the browser via CDN scripts. Nothing to install beyond the plugin itself.

- **Mermaid support without the weight.** The inline/extmark plugins (render-markdown.nvim, markview.nvim) are great for in-editor rendering but cannot draw diagrams. md-view.nvim gives you live mermaid SVGs alongside standard markdown, without the Node.js/Deno overhead of the other browser-based options.

- **Broad notation support without the runtime.** Beyond mermaid, md-view.nvim renders KaTeX math, Graphviz, WaveDrom, Nomnoml, ABC notation, and Vega-Lite charts — all via CDN, no extra installs. The other browser-based options stop at mermaid.

## How It Works

The plugin starts a local HTTP server (via Neovim's built-in libuv bindings) that serves an HTML page. The browser loads markdown-it, mermaid.js, and morphdom from CDN. Buffer changes are pushed to the browser over Server-Sent Events (SSE), where JavaScript re-renders the markdown and patches the DOM.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full technical design.

## License

[MIT](LICENSE)
