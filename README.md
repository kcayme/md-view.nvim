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

`setup()` is optional — every option has a default. See [docs/options.md](docs/options.md) for the full reference. Adding `---@type MdViewOptions` enables LSP completion and hover docs:

```lua
---@type MdViewOptions
require("md-view").setup({
  theme = { mode = "sync" },
  single_page = { enable = true },
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
