# Picker Integration

## How it works

`:MdViewList` calls `vim.ui.select` with the list of active previews. Any plugin that overrides `vim.ui.select` automatically takes over the picker — no md-view-specific configuration is required beyond the optional `picker.*` options described below.

---

## Per-picker setup

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
