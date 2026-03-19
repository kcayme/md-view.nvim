# Architecture

## Overview

md-view.nvim is a browser-based markdown preview plugin for Neovim. It runs a local HTTP server inside Neovim using libuv TCP bindings, serves an HTML page that renders markdown with mermaid diagrams, and pushes live updates over Server-Sent Events (SSE) as the buffer changes.

There are no external runtime dependencies — the server is pure Lua running on Neovim's built-in libuv event loop, and the browser handles all rendering via CDN-loaded JavaScript libraries.

## Project Structure

```
md-view.nvim/
├── plugin/
│   └── md-view.lua              # User command registration
└── lua/md-view/
    ├── init.lua                  # Public API facade: setup(), open(), stop(), toggle(), list()
    ├── config.lua                # Defaults + merge via tbl_deep_extend
    ├── preview.lua               # Preview lifecycle orchestration (create, destroy, state)
    ├── buffer.lua                # Buffer autocmds + debounced content/scroll push
    ├── theme.lua                 # All theme concerns: palettes, defaults, resolve, CSS
    ├── picker.lua                # UI selector for active previews
    ├── util.lua                  # Browser opening, debounce, platform detection
    └── server/
        ├── tcp.lua               # TCP server (bind, listen, accept)
        ├── router.lua            # HTTP request parsing + route dispatch
        ├── sse.lua               # SSE connection manager + event fan-out
        └── template.lua          # HTML page (markdown-it + mermaid.js + morphdom)
```

## Module Dependency Graph

```mermaid
graph TD
    plugin["plugin/md-view.lua"]
    init["init.lua<br/><i>API facade</i>"]
    config["config.lua"]
    preview["preview.lua<br/><i>orchestration</i>"]
    theme["theme.lua<br/><i>palettes, resolve, CSS</i>"]
    server["server/tcp.lua"]
    router["server/router.lua"]
    template["server/template.lua"]
    sse["server/sse.lua"]
    hub["server/handlers/hub.lua"]
    buffer["buffer.lua"]
    util["util.lua"]
    picker["picker.lua"]

    plugin --> init
    init --> config
    init --> preview
    init --> theme
    init -.->|lazy| picker
    picker --> init

    preview --> theme
    preview --> server
    preview --> router
    preview --> sse
    preview --> hub
    preview --> buffer
    preview --> util

    server -.->|on_request callback| router
    router --> template
    router -.->|reads from ctx| sse
    hub -.->|lazy| template
    hub -.->|lazy| config
    hub -.->|lazy| theme

    buffer --> util
```

## Data Flow

### 1. Initialization (`:MdView`)

```mermaid
sequenceDiagram
    actor User
    participant init as init.lua
    participant config as config.lua
    participant preview as preview.lua
    participant theme as theme.lua
    participant sse as server/sse.lua
    participant server as server/tcp.lua
    participant buffer as buffer.lua
    participant util as util.lua
    participant Browser

    User->>init: :MdView
    init->>config: setup({}) if needed
    init->>preview: create(opts)
    preview->>theme: resolve(opts)
    theme-->>preview: theme, highlight_theme, mermaid_theme
    preview->>theme: palette_css(resolved_theme)
    theme-->>preview: CSS string
    preview->>sse: new()
    sse-->>preview: sse_instance
    preview->>server: start(host, port)
    server-->>preview: srv, port
    preview->>buffer: watch(bufnr, callbacks)
    buffer-->>preview: watcher
    preview->>preview: store in active_previews[bufnr]
    preview->>util: open_browser(url)
    util->>Browser: launch
```

### 2. Browser Initial Load

```mermaid
sequenceDiagram
    participant Browser
    participant router as server/router.lua
    participant template as server/template.lua
    participant preview as preview.lua
    participant sse as server/sse.lua

    Browser->>router: GET /
    router->>template: render(opts, filename)
    template-->>router: HTML
    router-->>Browser: HTML response

    Browser->>router: GET /events
    Note over router: sse_upgrade: write SSE headers first,<br/>then add_client
    router-->>Browser: SSE headers (keep-alive)
    router->>sse: add_client(socket)
    Note over sse: replay last events (theme, palette)<br/>then call on_client_added hook
    sse->>preview: on_client_added(client)
    preview->>preview: read_content_async(bufnr)
    Note over preview: buffer if modified;<br/>disk read otherwise
    preview-->>Browser: SSE: content {content}

    Note over Browser: markdown-it parse<br/>→ morphdom patch DOM<br/>→ mermaid.run()
```

### 3. Live Update — Content

```mermaid
sequenceDiagram
    participant Neovim as Neovim Buffer
    participant buffer as buffer.lua
    participant preview as preview.lua
    participant sse as server/sse.lua
    participant Browser

    Neovim->>buffer: TextChanged / TextChangedI / BufWritePost
    Note over buffer: debounce timer resets (300ms)
    buffer->>buffer: timer expires → read buffer lines
    buffer->>preview: callbacks.on_content(lines)
    preview->>sse: push("content", {content})
    sse->>Browser: event: content\ndata: {json}

    Note over Browser: markdown-it parse<br/>→ morphdom diff/patch<br/>→ mermaid.run()
```

### 4. Live Update — Scroll Sync

```mermaid
sequenceDiagram
    participant Neovim as Neovim Cursor
    participant buffer as buffer.lua
    participant preview as preview.lua
    participant sse as server/sse.lua
    participant Browser

    Neovim->>buffer: CursorMoved / CursorMovedI
    Note over buffer: debounce timer resets (50ms)
    buffer->>buffer: timer expires → read cursor position
    buffer->>preview: callbacks.on_scroll(data)
    preview->>sse: push("scroll", data)
    sse->>Browser: event: scroll\ndata: {json}

    Note over Browser: find closest<br/>data-source-line element<br/>→ scrollIntoView()
```

The scroll sync works because markdown-it exposes source map information (line numbers) per token. The template JS hooks into markdown-it's block-level renderer rules (`paragraph_open`, `heading_open`, `blockquote_open`, etc.) to attach `data-source-line` attributes to rendered HTML elements. When a scroll event arrives, the browser finds the element whose `data-source-line` is closest to the cursor line and smoothly scrolls to it.

### 5. Shutdown

```mermaid
sequenceDiagram
    actor User
    participant init as init.lua
    participant preview as preview.lua
    participant sse as server/sse.lua
    participant buffer as buffer.lua
    participant server as server/tcp.lua

    User->>init: :MdViewStop / BufDelete / VimLeavePre
    init->>preview: destroy(bufnr)
    preview->>sse: push("close", {})
    preview->>sse: close_all()
    preview->>buffer: watcher.stop()
    preview->>server: stop(srv)
    preview->>preview: delete augroup
    preview->>preview: active_previews[bufnr] = nil
```

### 6. Single-Page Mode — Hub Connect

When `single_page.enable = true`, all previews share one browser tab served by a central hub server. The hub replays state to new SSE clients in a fixed order so panels exist before content and styles arrive.

```mermaid
sequenceDiagram
    actor User
    participant preview as preview.lua
    participant hub as hub.lua
    participant buffer as buffer.lua
    participant Browser

    User->>preview: create(opts) — first preview
    preview->>preview: ensure_mux() → start hub server (port H)
    preview->>preview: start per-buffer server (port A)
    preview->>buffer: watch(bufnr=1, callbacks)
    preview->>hub: register(bufnr=1, path, tab_label)
    preview->>hub: push("preview_added", {id=1, label})
    preview->>hub: push("hub_palette", {css})
    preview->>Browser: open_browser(hub_url :H)

    Browser->>hub: GET /
    hub-->>Browser: mux.html

    Browser->>hub: GET /sse
    Note over hub: add_client replay order:<br/>1. hub_palette (chrome styled first)<br/>2. preview_added (panel created)<br/>3. palette / theme (panel styled)<br/>4. on_client_added → async disk read → content
    hub-->>Browser: SSE: hub_palette {css}
    hub-->>Browser: SSE: preview_added {id=1, label}
    hub-->>Browser: SSE: content {id=1, content}

    Note over Browser: createPanel(1) → activateTab(1)<br/>→ panels[1].renderMarkdown(content)
```

### 7. Single-Page Mode — Second Preview and Live Updates

```mermaid
sequenceDiagram
    actor User
    participant preview as preview.lua
    participant hub as hub.lua
    participant buffer as buffer.lua
    participant Browser

    User->>preview: create(opts) — second preview (hub tab already open)
    preview->>preview: start per-buffer server (port B)
    preview->>buffer: watch(bufnr=2, callbacks)
    preview->>hub: register(bufnr=2, path, tab_label)
    preview->>hub: push("preview_added", {id=2, label})
    hub-->>Browser: SSE: preview_added {id=2, label}
    Note over Browser: createPanel(2) → activateTab(2)<br/>(panel is empty until first buffer change)
    Note over preview: on_client_added fires only on NEW SSE connect,<br/>not when a preview is added to an existing hub session

    Note over buffer: TextChanged on bufnr=1 — debounce fires
    buffer->>preview: on_content(lines)
    preview->>hub: push("content", {id=1, content})
    hub-->>Browser: SSE: content {id=1, content}
    Note over Browser: panels[1].renderMarkdown(content)

    Note over preview: BufEnter autocmd fires for bufnr=1
    preview->>hub: push("focus", {id=1})
    hub-->>Browser: SSE: focus {id=1}
    Note over Browser: activateTab(1)

    Note over preview: BufDelete / :MdViewStop on bufnr=2
    preview->>hub: push("preview_removed", {id=2})
    hub-->>Browser: SSE: preview_removed {id=2}
    Note over Browser: removePanel(2) → activateTab(remaining)
    preview->>hub: unregister(bufnr=2)
```

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Transport | SSE over WebSocket | Simpler protocol, browser-native auto-reconnect via EventSource, unidirectional push is sufficient |
| Rendering | Client-side via CDN | Zero bundling, no build step, browser handles all heavy lifting |
| Port allocation | OS auto-assign (port 0) | No conflicts when multiple buffers run previews simultaneously |
| Update strategy | Full content replace | Simple and correct for v1; incremental diffing is a future optimization |
| One server per buffer | Yes | Each preview gets its own TCP socket and port. The resource cost is negligible at loopback scale (one OS file descriptor, a few KB of kernel memory, no extra threads — all I/O runs on Neovim's existing libuv event loop). Typical usage is 1–3 simultaneous previews. The alternative — a single shared server with path-based routing per bufnr — would save nothing measurable while adding multiplexing complexity and shared failure surface. Isolation also means each preview's URL is stable and closing one cannot affect others. |
| DOM patching | morphdom | Preserves mermaid SVG state between updates, avoids full re-render flicker |
| libuv compatibility | `vim.uv or vim.loop` | Works across Neovim 0.8+ (vim.loop) and 0.10+ (vim.uv) |
| Scroll sync | `data-source-line` attributes | markdown-it exposes source map (line numbers) per token; cheap to attach as data attributes during rendering |
| SSE event types | Named events (`content`, `scroll`) | Separates concerns cleanly; browser handles each independently without parsing a type field |
| Debounce | Two timers (300ms content, 50ms scroll) | Content updates are heavier (full re-render), cursor updates should feel immediate |
| Picker UI | `vim.ui.select` | Picker-agnostic by design — any replacement (Telescope, fzf-lua, snacks, dressing.nvim) automatically works. No plugin-specific configuration is exposed; customization is limited to the standardised `vim.ui.select` opts (`prompt`, `format_item`, `kind`) |

## HTTP Protocol

The server implements a minimal subset of HTTP/1.1. Regular responses use `Connection: close`; the SSE endpoint uses `text/event-stream` with `Connection: keep-alive` and stays open for streaming. No CORS headers — loopback-only binding makes same-origin the only origin.

```mermaid
flowchart LR
    req["HTTP Request"] --> parse["Parse method + path"]
    parse --> get_root{"GET /"}
    parse --> get_content{"GET /content"}
    parse --> get_events{"GET /events"}
    parse --> get_vendor{"GET /vendor/:file"}
    parse --> get_file{"GET /file"}
    parse --> other{"Other"}

    get_root    -->|yes| html["Render template → send HTML → close"]
    get_content -->|yes| json["Read buffer lines → send JSON → close"]
    get_events  -->|yes| sse["Send SSE headers → register client → keep alive"]
    get_vendor  -->|yes| vendor["Serve vendor asset → close"]
    get_file    -->|yes| media["Serve local media file → close"]
    other       -->|yes| notfound["404 response"]
```

## State Lifecycle

Each active preview is tracked in `active_previews` keyed by buffer number:

```mermaid
classDiagram
    class active_previews {
        +bufnr : key
        +server : uv_tcp_t
        +port : number
        +sse : MdViewSse
        +watcher : buffer watcher
    }
```

```mermaid
stateDiagram-v2
    [*] --> Unconfigured

    Unconfigured --> Configured: setup(opts)
    note right of Configured: config.options set

    Configured --> Active: open() → preview.create()
    note right of Active
        active_previews[bufnr] populated:
        - server handle
        - port number
        - SSE instance
        - buffer watcher
        - cleanup autocmds
    end note

    Active --> Active: open() another buffer
    Active --> Configured: stop() → preview.destroy()
    note left of Configured
        Cleanup:
        - SSE clients closed
        - timers stopped
        - autocmds removed
        - server closed
        - entry deleted
    end note

    Active --> [*]: VimLeavePre (destroy all)
```

## Browser Dependencies (CDN)

| Library      | CDN URL                                                     |
|--------------|-------------------------------------------------------------|
| markdown-it  | `https://cdn.jsdelivr.net/npm/markdown-it@14/dist/markdown-it.min.js` |
| mermaid.js   | `https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js` |
| morphdom     | `https://cdn.jsdelivr.net/npm/morphdom@2/dist/morphdom-umd.min.js` |
| KaTeX        | `https://cdn.jsdelivr.net/npm/katex@0.16.38/dist/katex.min.js` |
| texmath      | `https://cdn.jsdelivr.net/npm/markdown-it-texmath@1.0.0/texmath.js` |
| @viz-js/viz  | `https://cdn.jsdelivr.net/npm/@viz-js/viz@3.25.0/dist/viz-global.js` |
| WaveDrom     | `https://cdn.jsdelivr.net/npm/wavedrom@3.5.0/wavedrom.min.js` |
| graphre      | `https://cdn.jsdelivr.net/npm/graphre@0.1.3/dist/graphre.js` |
| Nomnoml      | `https://cdn.jsdelivr.net/npm/nomnoml@1.6.2/dist/nomnoml.min.js` |
| abcjs        | `https://cdn.jsdelivr.net/npm/abcjs@6.4.4/dist/abcjs-basic-min.js` |
| Vega         | `https://cdn.jsdelivr.net/npm/vega@5.30.0/build/vega.min.js` |
| Vega-Lite    | `https://cdn.jsdelivr.net/npm/vega-lite@5.21.0/build/vega-lite.min.js` |
| Vega-Embed   | `https://cdn.jsdelivr.net/npm/vega-embed@6.26.0/build/vega-embed.min.js` |

