# Single Page Mode

## How it works

When `single_page.enable = true`, all active previews are multiplexed into one browser tab. A shared hub server starts on the first `:MdView` call and stays alive until every preview is closed. Each preview registers with the hub and gets its own tab in the browser — switching buffers in Neovim focuses the matching tab automatically.

The hub server uses the top-level `port` option (`0` = OS-assigned free port).

---

## Basic setup

```lua
require("md-view").setup({
  single_page = { enable = true },
})
```

Open as many markdown buffers as you like with `:MdView`. Each one appears as a tab in the same browser window rather than opening a new tab.

---

## Customising tab labels

The `tab_label` option controls what each tab is called in the browser. The built-in presets cover most cases:

| Value | Example label |
|-------|--------------|
| `"filename"` (default) | `README.md` |
| `"relative"` | `docs/guide/README.md` |
| `"parent"` | `guide/README.md` |

For anything beyond that, pass a function. The function receives a `ctx` table and must return a string:

```lua
-- ctx fields:
--   ctx.bufnr    — Neovim buffer number
--   ctx.filename — basename of the file (e.g. "README.md")
--   ctx.path     — full absolute path  (e.g. "/home/user/project/docs/README.md")
tab_label = function(ctx)
  return ctx.filename
end
```

### Examples

**Show the git branch alongside the filename** (useful when you have the same file open from two worktrees):

```lua
require("md-view").setup({
  single_page = {
    enable = true,
    tab_label = function(ctx)
      local branch = vim.fn.systemlist("git -C " .. vim.fn.fnamemodify(ctx.path, ":h") .. " branch --show-current")[1]
      return (branch and branch ~= "" and "[" .. branch .. "] " or "") .. ctx.filename
    end,
  },
})
```

**Show the project root name + relative path** (useful in a monorepo where filenames alone are ambiguous):

```lua
require("md-view").setup({
  single_page = {
    enable = true,
    tab_label = function(ctx)
      local root = vim.fn.fnamemodify(ctx.path, ":h:h:t")  -- grandparent directory
      local parent = vim.fn.fnamemodify(ctx.path, ":h:t")   -- parent directory
      return root .. "/" .. parent .. "/" .. ctx.filename
    end,
  },
})
```

**Truncate long paths to a fixed width:**

```lua
require("md-view").setup({
  single_page = {
    enable = true,
    tab_label = function(ctx)
      local label = vim.fn.fnamemodify(ctx.path, ":~:.")  -- relative to home, then cwd
      if #label > 40 then
        label = "…" .. label:sub(-39)
      end
      return label
    end,
  },
})
```

---

## Controlling close behaviour

By default, `single_page` mode inherits the top-level `auto_close` setting. You can override this independently with `close_by`:

| Value | Behaviour |
|-------|-----------|
| `nil` (default) | Inherit from top-level `auto_close` — `true` closes the window when the last preview ends, `false` never does. |
| `"page"` | Close the browser window when the last preview ends, regardless of `auto_close`. |
| `"tab"` / `false` | Only remove the preview's tab from the hub page; never close the browser window. |

**Keep the hub window open after all previews close** (useful if you want to reuse the tab later):

```lua
require("md-view").setup({
  single_page = {
    enable = true,
    close_by = "tab",
  },
})
```

**Always close the window when the last preview ends**, even if `auto_close = false` elsewhere:

```lua
require("md-view").setup({
  auto_close = false,   -- don't auto-close individual (non-single-page) previews
  single_page = {
    enable = true,
    close_by = "page",  -- but do close the hub window when it empties
  },
})
```
