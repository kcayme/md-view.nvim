# Auto-open

`auto_open` automatically opens a preview whenever you enter a qualifying buffer, so you never need to run `:MdView` manually.

**Enable with the default trigger event (`BufWinEnter`):**

```lua
require("md-view").setup({
  auto_open = { enable = true },
})
```

**Use `BufEnter` instead** (fires more broadly — also on splits and `:e` without a window change):

```lua
require("md-view").setup({
  auto_open = { enable = true, events = { "BufEnter" } },
})
```

Toggle at runtime with `:MdViewAutoOpen`.

---

## lazy.nvim users

`auto_open` registers an autocmd at `setup()` time. If your spec uses `cmd = {...}` the plugin won't load until a command is invoked and the autocmd will never fire.

Either disable lazy-loading entirely:

```lua
{
  "kcayme/md-view.nvim",
  lazy = false,
  opts = { auto_open = { enable = true } },
}
```

Or keep command-based lazy-loading and add the trigger event to your spec so the plugin loads early enough:

```lua
{
  "kcayme/md-view.nvim",
  cmd   = { "MdView", "MdViewStop", "MdViewToggle", "MdViewAutoOpen" },
  event = { "BufWinEnter" },
  opts  = { auto_open = { enable = true } },
}
```
