# Configuration Options

Full reference for all options accepted by `require("md-view").setup()`. All options are optional — omitted keys fall back to the defaults shown below.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `port` | `integer` | `0` | Port for the local preview server. `0` lets the OS auto-assign a free port. |
| `host` | `string` | `"127.0.0.1"` | Bind address for the preview server. Must be a loopback address (`127.0.0.1`, `::1`, `localhost`). |
| `browser` | `string\|nil` | `nil` | Path to a browser executable. `nil` auto-detects (`open` on macOS, `xdg-open` on Linux, `cmd /c start` on Windows). |
| `debounce_ms` | `integer` | `300` | Milliseconds to wait after the last edit before pushing an update to the browser. |
| `css` | `string\|nil` | `nil` | Custom CSS string injected into the preview page. Use this to override any default styles. |
| `auto_close` | `boolean` | `true` | Auto-close the browser tab when the preview is stopped. |
| `follow_focus` | `boolean` | `false` | When `true`, always opens a new browser tab when revisiting a buffer that already has an active preview (via `:MdView` or `auto_open`). Ensures the browser always shows the preview for the current buffer. **Note:** opens a new tab each time, closing the existing one via the tab-dedup mechanism — any split-tab arrangement in the browser will break. |
| `scroll.method` | `MdViewScrollMethod` | `"percentage"` | Scroll sync algorithm. `"percentage"` keeps the browser at the same proportional offset as the cursor. `"cursor"` anchors the browser to the nearest source line in the rendered DOM. |
| `theme.mode` | `MdViewThemeMode` | `"auto"` | Color theme for the preview page. `"auto"` follows Neovim's `background` setting; `"dark"` / `"light"` force a palette; `"sync"` mirrors your current colorscheme live. |
| `theme.syntax` | `string\|nil` | `nil` | [highlight.js theme](https://highlightjs.org/demo) for syntax highlighting in fenced code blocks. `nil` auto-selects based on `theme.mode`: dark themes use `"vs2015"`, light themes use `"github"`. |
| `theme.highlights` | `table<string, string>` | `{}` | Highlight group overrides for CSS variable extraction. Only used when `theme.mode = "sync"`. |
| `notations.mermaid.enable` | `boolean` | `true` | Load the Mermaid CDN library. Set `false` to skip (saves bandwidth). |
| `notations.mermaid.theme` | `string\|nil` | `nil` | Mermaid diagram theme. One of `"default"`, `"dark"`, `"forest"`, `"neutral"`, or `"base"`. `nil` auto-chooses based on `theme.mode`. |
| `notations.katex.enable` | `boolean` | `true` | Load KaTeX for math fences and `$...$` / `$$...$$` inline math. |
| `notations.graphviz.enable` | `boolean` | `true` | Load Graphviz (viz.js) for `dot` fences. |
| `notations.wavedrom.enable` | `boolean` | `true` | Load WaveDrom for digital timing diagram fences. |
| `notations.nomnoml.enable` | `boolean` | `true` | Load nomnoml for UML diagram fences. |
| `notations.abc.enable` | `boolean` | `true` | Load ABCJS for ABC music notation fences. |
| `notations.vegalite.enable` | `boolean` | `true` | Load Vega-Lite for chart fences. |
| `filetypes` | `string[]` | `{ "markdown" }` | Buffer filetypes the plugin will preview. Running `:MdView` on a buffer whose filetype is not in this list emits a warning and does nothing. Set to `{}` to allow any filetype. |
| `auto_open.enable` | `boolean` | `false` | When `true`, automatically opens (or re-focuses) a preview whenever you enter a qualifying buffer. Toggle at runtime with `:MdViewAutoOpen`. |
| `auto_open.events` | `string[]` | `{ "BufWinEnter" }` | Neovim autocmd events that trigger the auto-open check. |
| `picker.prompt` | `string` | `"Markdown Previews"` | Title/prompt shown at the top of the `:MdViewList` picker. |
| `picker.format_item` | `fun(item: table): string\|nil` | `nil` | Custom item formatter. `item` has `.bufnr`, `.port`, `.name` (basename). `nil` uses the built-in `"name  http://host:port"` format. |
| `picker.kind` | `string\|nil` | `nil` | Hint passed as `opts.kind` to `vim.ui.select`. Some picker replacements use this to provide a specialised UI (e.g. a file-preview pane). |
| `single_page.enable` | `boolean` | `false` | When `true`, all active previews are multiplexed into one browser tab via a shared hub server. The hub uses the top-level `port` option for its address. |
| `single_page.tab_label` | `MdViewTabLabel\|fun(ctx: MdViewTabLabelCtx): string` | `"parent"` | Label shown on each preview's tab in the hub. `"filename"` — basename; `"relative"` — path relative to cwd; `"parent"` — parent dir + basename; function for a fully custom label. |
| `single_page.close_by` | `MdViewCloseBy` | `nil` | Controls what closes when a preview ends, overriding top-level `auto_close`. `nil` — inherit from `auto_close`; `"page"` — close the browser window when the last preview ends; `"tab"` or `false` — only remove the preview's tab, keep the window open. |
