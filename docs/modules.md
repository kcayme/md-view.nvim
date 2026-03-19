# Module Reference

## `plugin/md-view.lua`

Entry point loaded by Neovim at startup. Registers all user-facing commands that lazy-load the plugin via `require("md-view")`:

| Command | Description |
|---------|-------------|
| `:MdView` | Open preview for current buffer |
| `:MdViewStop` | Stop preview for current buffer |
| `:MdViewToggle` | Toggle preview |
| `:MdViewList` | Open picker of active previews |
| `:MdViewAutoOpen` | Toggle auto-open on buffer enter |
| `:MdViewTheme [mode]` | Switch live theme (dark/light/auto/sync); no arg cycles |
| `:MdViewFetchAssets` | Re-fetch vendor assets for offline use |

## `init.lua`

Public API facade. All plugin entry points go through here.

- **`setup(opts)`** — merges user config; sets up `auto_open` autocmd if enabled; pre-fetches vendor assets if curl is available and assets are missing
- **`open(opts?)`** — validates filetype against `config.options.filetypes`, applies any live theme override, delegates to `preview.create()`
- **`stop(bufnr)`** — delegates to `preview.destroy(bufnr)`
- **`toggle()`** — calls `stop` or `open` depending on whether a preview is already active for the current buffer
- **`list()`** — opens the picker UI via `picker.open()`
- **`get_active_previews()`** — returns the raw `active_previews` table from `preview`
- **`toggle_auto_open()`** — toggles the `auto_open` autocmd at runtime without a full `setup()` call
- **`set_theme(mode?)`** — switches the live theme for all active previews and pushes a `palette` SSE event to each; cycles `dark → light → auto → sync` if called with no argument

## `config.lua`

Stores defaults and the merged user configuration. Uses `vim.tbl_deep_extend("force", {}, defaults, opts)` so nested tables are merged rather than replaced. The `options` field is `nil` until `setup()` is called; `init.open()` calls `setup({})` as a fallback if the user never called it explicitly.

## `preview.lua`

Orchestration module. Owns the `active_previews` table (keyed by buffer number) and the singleton `_mux` hub instance.

- **`create(opts)`** — resolves theme, creates an SSE instance, starts the per-buffer TCP server, attaches a buffer watcher, registers cleanup autocmds (`BufDelete`, `BufWipeout`, `VimLeavePre`), and opens the browser. In single-page mode, also calls `ensure_mux()` to start the hub server if not running.
- **`destroy(bufnr)`** — tears down everything for a buffer: pushes `close`/`preview_removed` events, closes SSE clients, stops the buffer watcher, stops the TCP server, removes the augroup and the `active_previews` entry.
- **`get(bufnr)`** — returns the preview entry for a buffer, or nil.
- **`get_active()`** — returns the full `active_previews` table.
- **`get_mux()`** — returns the hub instance, or nil if single-page mode is not in use.

`read_content_async(bufnr, callback)` is a module-local helper that reads from the Neovim buffer when it has unsaved edits, and from disk otherwise. The callback is always called on the main Neovim thread via `vim.schedule()`.

## `buffer.lua`

Attaches Neovim autocmds and a filesystem watcher to a buffer. Exposes a dependency-injectable `M.new(deps)` factory (used by tests) and a convenience `M.watch(...)` alias that uses production defaults.

**Content autocmds** (`TextChanged`, `TextChangedI`, `BufWritePost`, `BufReadPost`, `FileChangedShellPost`) — debounced at `debounce_ms`. On fire, reads buffer lines and calls `callbacks.on_content(lines)`. `BufWritePost` sets a `wrote_from_nvim` flag so the filesystem watcher skips the redundant push that would otherwise double-fire on `:w`.

**Cursor autocmds** (`CursorMoved`, `CursorMovedI`) — debounced at 50ms. Reads the cursor position and calls:
- `callbacks.on_scroll({ line = N })` (0-indexed) when `scroll_method = "cursor"`
- `callbacks.on_scroll({ percent = N })` for the default percent-based method

**Filesystem watcher** — `uv.fs_event` on the buffer's file path. Handles external edits from tools that use atomic rename-based writes (e.g. `sed -i`, Claude Code). On a `rename` event the old inode is gone, so the watcher stops itself and schedules a restart via `vim.schedule(pcall(start_watching))`. A `watcher_stopped` flag prevents restart after `stop()` is called.

`stop()` closes both debounce timers, stops and closes the fs watcher, and deletes the augroup.

## `theme.lua`

All theme concerns in one place.

- **`resolve(opts)`** — maps `opts.theme.mode` and `vim.o.background` to a concrete theme name, a highlight.js theme name, and a mermaid theme name.
- **`palette_css(theme)`** — returns a CSS string of `--md-*` custom property values for the given named theme (`dark`, `light`).
- **`css(highlights)`** — builds a `sync`-mode CSS string by reading Neovim highlight groups via `nvim_get_hl`.

## `picker.lua`

Thin wrapper around `vim.ui.select`. Lists active previews by filename and port; selecting an entry calls `init.open()` for that buffer or opens the browser if a preview is already running.

## `util.lua`

- **`open_browser(url, browser)`** — uses `browser` directly if configured; otherwise detects the platform (`open` on macOS, `wslview` for WSL, `xdg-open` on Linux, `cmd /c start` on Windows) and launches detached via `vim.fn.jobstart`.
- **`debounce(fn, ms)`** — wraps `fn` in a `uv.new_timer()`. Each call resets the timer; `fn` fires `ms` ms after the last call, via `vim.schedule()`. Returns a table with a `.stop()` method.

## `server/tcp.lua`

Creates a TCP server on the loopback interface using `vim.uv` (Neovim 0.10+) or `vim.loop` (0.8–0.9). Binds to the configured host and port (default 0 for OS auto-assignment), resolves the actual port via `getsockname()`. On each connection, accumulates data until `\r\n\r\n` is detected, then calls the `on_request(client, buf)` callback on the main thread via `vim.schedule()`.

## `server/router.lua`

Parses the HTTP request line (method + path + query string), matches against a route table that supports `:param` segments, builds a `res` helper (`.send`, `.json`, `.send_file`, `.sse_upgrade`), and calls the matched handler. Responds 404 if no route matches and 405 for non-GET methods.

`sse_upgrade(sse_instance)` writes SSE response headers to the client first, then calls `sse_instance:add_client(client)`, then re-enables reads so browser disconnects are detected and the stale client is removed.

## `server/sse.lua`

Holds a list of open client sockets and a `last` cache of replay-eligible events. Dead clients are detected during `push()` via `pcall` and removed.

- **`add_client(client)`** — inserts the client, replays `last` events (`palette`, `theme`), then calls `on_client_added(client)` if set. The hook is used by `preview.lua` to push fresh content from disk immediately after connect.
- **`push(event_type, data)`** — fans out a named SSE event to all clients; caches the value for replay-eligible event types.
- **`remove_client(client)`** — removes and closes a specific client (called on browser disconnect).
- **`close_all()`** — closes all clients and clears `last`; called on preview shutdown.

`content` and `scroll` are intentionally excluded from replay: content is always delivered fresh via `on_client_added`, and scroll position is ephemeral.

## `server/template.lua`

Generates self-contained HTML by substituting placeholders in `assets/template.html` (single-page preview) or `assets/mux.html` (hub). Injects vendor script tags, palette/theme CSS, and the mermaid theme name.

The embedded JavaScript (`assets/common.js`) handles:
- markdown-it rendering with a custom fence rule for mermaid blocks and `data-source-line` attributes on block elements
- morphdom DOM patching for efficient re-renders
- `EventSource` listeners for `content`, `scroll`, `theme`, `palette`, and `close` events

## `server/handlers/direct.lua`

Route handlers for per-buffer preview servers:

| Route | Handler |
|-------|---------|
| `GET /` | Render `template.html` for the buffer |
| `GET /content` | Return current buffer lines as JSON |
| `GET /events` | SSE upgrade |
| `GET /vendor/:file` | Serve a vendored JS/CSS asset |
| `GET /file` | Serve a local media file relative to the buffer's directory |

## `server/handlers/hub.lua`

Route handlers and state manager for the single-page hub server. The hub instance holds:
- `registry` — map of `bufnr → { title, label }` for all registered previews
- `clients` — shared SSE client list across all previews
- `last` — per-preview replay state (`preview_added`, `palette`, `theme`) and hub-level `last_hub_palette`
- `on_client_added` — hook set by `preview.lua` to push initial content for all registered previews on connect

Replay order on connect: `hub_palette` → per-preview `preview_added` → `palette` → `theme` → `on_client_added` (async content). This ordering ensures panels exist in the browser before content and styles arrive.

| Route | Handler |
|-------|---------|
| `GET /` | Render `mux.html` |
| `GET /sse` | SSE upgrade (shared across all previews) |
| `GET /content?id=` | Return buffer lines for a specific preview as JSON |
| `GET /vendor/:file` | Serve a vendored JS/CSS asset |
| `GET /file?id=&path=` | Serve a local media file relative to the named preview's buffer directory |
