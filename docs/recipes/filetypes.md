# Filetypes

By default md-view only opens previews for `markdown` buffers. The `filetypes` option controls which buffer filetypes are allowed.

**Add MDX support alongside markdown:**

```lua
require("md-view").setup({
  filetypes = { "markdown", "mdx" },
})
```

**Allow any filetype** (useful for previewing non-standard markdown extensions):

```lua
require("md-view").setup({
  filetypes = {},
})
```

> Note: the list replaces the default rather than extending it, so always include `"markdown"` if you want it.
