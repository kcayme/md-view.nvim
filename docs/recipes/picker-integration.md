# Picker Integration

This plugin involves two distinct picker concepts:

1. **Preview a file picked from a file picker** — wire your file picker
   (fff.nvim, snacks.nvim, telescope.nvim, fzf-lua) so selecting a markdown
   file opens an `MdView` preview for it. See below.
2. **Choosing a backend for `:MdViewList`** — `:MdViewList` uses
   `vim.ui.select` to list active previews; any plugin that overrides
   `vim.ui.select` takes over that UI. See
   [Choosing a backend for `:MdViewList`](#choosing-a-backend-for-mdviewlist).

---

## Preview a file picked from a file picker

`require("md-view").open({ path = <file path> })` starts a preview for an
arbitrary file without it having to be the current buffer. Wire it into your
picker's confirm action/keymap. This previews only the files you pick — unlike
`auto_open`, which fires for every markdown buffer you visit.

### Auto-preview on open (toggleable)

If instead you want a preview to open automatically whenever you *enter* a
markdown buffer — regardless of which picker (or command) opened it — use the
built-in [`auto_open`](auto-open.md) feature rather than wiring a custom
autocommand. It registers an autocommand (default event `BufWinEnter`) that
previews any markdown buffer you enter, and respects your `filetypes` setting:

```lua
require("md-view").setup({
  auto_open = { enable = true },
})
```

Toggle it on and off at runtime with:

```lua
require("md-view").toggle_auto_open()
```

This is the simplest way to get auto-preview-on-open with a runtime toggle. The
per-picker recipes below are for the narrower case of previewing *only* the
files you explicitly pick.

### fff.nvim

fff.nvim has no hook for picker-scoped preview: its only selection hook,
`select.select_window`, is a window router (overriding it clobbers fff's
split/tab routing), and its `keymaps` map only to built-in actions, not custom
Lua functions. Use the built-in
[`auto_open`](#auto-preview-on-open-toggleable) feature for auto-preview-on-open
(note: previews *every* markdown buffer you enter, not only picked files). For
picker-scoped preview, use snacks.nvim, telescope, or fzf-lua below.

### snacks.nvim

Bind a key (e.g. `<c-p>`) to a custom action to preview without changing the
default Enter behavior — this is the recommended approach:

```lua
require("snacks").picker.files({
  win = {
    input = {
      keys = { ["<c-p>"] = { "md_view", mode = { "n", "i" } } },
    },
  },
  actions = {
    md_view = function(picker, item)
      if item and item.file then
        require("md-view").open({ path = item.file })
      end
    end,
  },
})
```

Alternatively, override `confirm` to preview the selected item and then
perform the normal open:

```lua
require("snacks").picker.files({
  confirm = function(picker, item)
    picker:action("confirm") -- default open behavior
    if item and item.file then
      require("md-view").open({ path = item.file })
    end
  end,
})
```

Note: `picker:action("confirm")` reproduces the default open action but was not found as an explicit example in the snacks docs — verify it against your snacks version.

### telescope.nvim

Attach a custom action in `attach_mappings` that reads the selected entry's
path:

```lua
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

require("telescope.builtin").find_files({
  attach_mappings = function(_, map)
    local function preview_md(prompt_bufnr)
      local entry = action_state.get_selected_entry()
      actions.close(prompt_bufnr)
      if entry and entry.path then
        require("md-view").open({ path = entry.path })
      end
    end
    map({ "i", "n" }, "<c-p>", preview_md)
    return true
  end,
})
```

`entry.path` is the absolute file path computed by telescope's `find_files`
entry maker (it combines `cwd` and the relative filename via a metatable).

### fzf-lua

Add a custom action; fzf-lua passes the selected entries as the first argument
and an options table as the second:

```lua
require("fzf-lua").files({
  actions = {
    ["ctrl-p"] = function(selected, opts)
      local file = selected and require("fzf-lua").path.entry_to_file(selected[1], opts)
      if file and file.path then
        require("md-view").open({ path = file.path })
      end
    end,
  },
})
```

`require("fzf-lua").path.entry_to_file(entry_str, opts)` strips fzf decorations
(icons, line/col suffixes) and returns a table whose `.path` field is the
absolute file path.

### Multiple selections

`open({ path = ... })` previews one file. To preview several picked files,
loop over the selected paths:

```lua
for _, path in ipairs(selected_paths) do
  require("md-view").open({ path = path })
end
```

---

## Choosing a backend for `:MdViewList`

`:MdViewList` calls `vim.ui.select` with the list of active previews. Any plugin that overrides `vim.ui.select` automatically takes over the picker — no md-view-specific configuration is required beyond the optional `picker.*` options described below.

---

### Per-picker setup

### dressing.nvim

dressing.nvim replaces `vim.ui.select` automatically when it loads — no extra call needed. The `picker.kind` option is forwarded and can be used to select which dressing backend handles `:MdViewList`.

```lua
-- dressing.nvim setup (relevant part)
require("dressing").setup({
  select = {
    -- Route any vim.ui.select call with kind="md-view" to the telescope backend.
    get_config = function(opts)
      if opts.kind == "md-view" then
        return { backend = "telescope" }
      end
    end,
  },
})

-- md-view setup
require("md-view").setup({
  picker = { kind = "md-view" },
})
```

Without `get_config`, dressing uses its default backend for all `vim.ui.select` calls including `:MdViewList`.

---

### telescope-ui-select.nvim

Load the extension after Telescope is set up. Once loaded it replaces `vim.ui.select` globally.

```lua
require("telescope").setup({
  extensions = {
    ["ui-select"] = {
      require("telescope.themes").get_dropdown({}),
    },
  },
})
require("telescope").load_extension("ui-select")
```

`picker.kind` is not used directly by telescope-ui-select. All `vim.ui.select` calls go through the same Telescope UI.

Custom `format_item` example — if the Telescope preview pane already shows the URL, show only the buffer name:

```lua
require("md-view").setup({
  picker = {
    format_item = function(item)
      return item.name
    end,
  },
})
```

---

### fzf-lua

Call `register_ui_select()` once during startup. This replaces `vim.ui.select` with fzf-lua's implementation.

```lua
require("fzf-lua").register_ui_select()
```

`picker.kind` is not used directly by fzf-lua. All `vim.ui.select` calls are routed through the same fzf-lua UI.

Custom `format_item` example — include the port number more prominently:

```lua
require("md-view").setup({
  picker = {
    format_item = function(item)
      return string.format("[:%d]  %s", item.port, item.name)
    end,
  },
})
```

---

### snacks.nvim

snacks replaces `vim.ui.select` automatically via its `picker.select` integration when snacks is set up. The `picker.kind` value is forwarded as a source hint that snacks can use to apply a custom display style.

```lua
-- snacks.nvim setup (relevant part)
require("snacks").setup({
  picker = { enabled = true },
})

-- md-view setup — kind is forwarded to snacks as a hint
require("md-view").setup({
  picker = { kind = "md-view" },
})
```

---

### mini.pick

mini.pick does not replace `vim.ui.select` by default. Wire it up manually in your config using `MiniExtra.pickers.ui_select` (recommended) or by assigning `vim.ui.select` directly.

**Option A — MiniExtra (recommended):**

```lua
require("mini.extra").setup()
-- MiniExtra registers a ui_select picker that mini.pick will use.
-- No further setup needed; vim.ui.select is replaced automatically.
```

**Option B — manual assignment:**

```lua
vim.ui.select = require("mini.pick").ui_select
```

`picker.kind` is not used by mini.pick.

---

## Using `picker.kind` as a hint

`kind` is a free-form string passed as `opts.kind` to `vim.ui.select`. Pickers that support it (dressing.nvim, snacks.nvim) can use it to route `:MdViewList` to a specific backend or apply a custom display style. Pickers that ignore it are unaffected.

```lua
require("md-view").setup({
  picker = { kind = "md-view" },  -- arbitrary string; the picker decides what to do with it
})
```

---

## Custom `prompt`

The picker title defaults to `"Markdown Previews"`. Override it with:

```lua
require("md-view").setup({
  picker = { prompt = "My Previews" },
})
```

---

## Custom `format_item` tips

The default format is `"name  http://host:port"`. A few common customisations:

```lua
-- Buffer name only (useful when the picker already shows the URL in a preview pane)
format_item = function(item)
  return item.name
end

-- Port number first (useful when you have several previews open on different ports)
format_item = function(item)
  return string.format("[:%d]  %s", item.port, item.name)
end

-- Full URL only
format_item = function(item)
  return string.format("http://127.0.0.1:%d", item.port)
end
```

Apply any of these via:

```lua
require("md-view").setup({
  picker = {
    format_item = function(item)
      return item.name  -- replace with whichever formatter you prefer
    end,
  },
})
```
