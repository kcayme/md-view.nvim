local theme = require("md-view.theme")

describe("theme", function()
  describe("to_css", function()
    it("wraps vars in :root block", function()
      local css = theme.to_css({ ["--md-bg"] = "#000000" })
      assert.truthy(css:find(":root {"))
      assert.truthy(css:find("  %-%-md%-bg: #000000;"))
      assert.truthy(css:find("}"))
    end)

    it("handles multiple vars", function()
      local css = theme.to_css({
        ["--md-bg"] = "#000",
        ["--md-fg"] = "#fff",
      })
      assert.truthy(css:find("%-%-md%-bg: #000;"))
      assert.truthy(css:find("%-%-md%-fg: #fff;"))
    end)

    it("handles empty table", function()
      local css = theme.to_css({})
      assert.are.equal(":root {\n}", css)
    end)
  end)

  describe("palette_css", function()
    it("returns dark palette CSS for 'dark'", function()
      local css = theme.palette_css("dark")
      assert.truthy(css:find(":root {"))
      assert.truthy(css:find("#0d1117"))
    end)

    it("returns light palette CSS for 'light'", function()
      local css = theme.palette_css("light")
      assert.truthy(css:find(":root {"))
      assert.truthy(css:find("#ffffff"))
    end)

    it("falls back to dark for unknown theme", function()
      local css = theme.palette_css("nope")
      assert.truthy(css:find("#0d1117"))
    end)

    it("falls back to dark for nil", function()
      local css = theme.palette_css(nil)
      assert.truthy(css:find("#0d1117"))
    end)
  end)

  describe("resolve", function()
    it("resolves explicit dark theme", function()
      local r = theme.resolve({ theme = { mode = "dark" } })
      assert.are.equal("dark", r.theme)
      assert.are.equal("vs2015", r.highlight_theme)
      assert.are.equal("dark", r.mermaid_theme)
    end)

    it("resolves explicit light theme", function()
      local r = theme.resolve({ theme = { mode = "light" } })
      assert.are.equal("light", r.theme)
      assert.are.equal("github", r.highlight_theme)
      assert.are.equal("default", r.mermaid_theme)
    end)

    it("falls back to vim.o.background for auto", function()
      local orig = vim.o.background
      vim.o.background = "light"
      local r = theme.resolve({ theme = { mode = "auto" } })
      assert.are.equal("light", r.theme)
      assert.are.equal("github", r.highlight_theme)
      vim.o.background = orig
    end)

    it("respects user syntax override", function()
      local r = theme.resolve({ theme = { mode = "dark", syntax = "monokai" } })
      assert.are.equal("monokai", r.highlight_theme)
      assert.are.equal("dark", r.mermaid_theme)
    end)

    it("respects user mermaid theme override", function()
      local r = theme.resolve({ theme = { mode = "dark" }, notations = { mermaid = { theme = "forest" } } })
      assert.are.equal("forest", r.mermaid_theme)
      assert.are.equal("vs2015", r.highlight_theme)
    end)

    it("respects both overrides together", function()
      local r = theme.resolve({
        theme = { mode = "light", syntax = "custom" },
        notations = { mermaid = { theme = "neutral" } },
      })
      assert.are.equal("custom", r.highlight_theme)
      assert.are.equal("neutral", r.mermaid_theme)
    end)

    it("handles nil mermaid table", function()
      local r = theme.resolve({ theme = { mode = "dark" } })
      assert.are.equal("dark", r.mermaid_theme)
    end)

    it("handles mermaid table with nil theme", function()
      local r = theme.resolve({ theme = { mode = "dark" }, notations = { mermaid = {} } })
      assert.are.equal("dark", r.mermaid_theme)
    end)
  end)

  describe("build_mappings", function()
    it("returns default mappings when no overrides", function()
      local m = theme.build_mappings(nil)
      assert.is_true(#m > 0)
      assert.are.equal("--md-bg", m[1].var)
    end)

    it("returns default mappings for empty overrides", function()
      local m = theme.build_mappings({})
      assert.are.equal("--md-bg", m[1].var)
    end)

    it("overrides a mapping group with a table", function()
      local m = theme.build_mappings({ bg = { "MyGroup" } })
      local found = false
      for _, entry in ipairs(m) do
        if entry.var == "--md-bg" then
          assert.are.same({ "MyGroup" }, entry.groups)
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("overrides a mapping group with a string", function()
      local m = theme.build_mappings({ fg = "CustomNormal" })
      for _, entry in ipairs(m) do
        if entry.var == "--md-fg" then
          assert.are.same({ "CustomNormal" }, entry.groups)
          return
        end
      end
      error("--md-fg not found")
    end)

    it("ignores unknown override keys", function()
      local m = theme.build_mappings({ nonexistent = { "Foo" } })
      -- should still have all default mappings unchanged
      assert.is_true(#m > 0)
    end)

    it("does not mutate default mappings", function()
      local before = theme.build_mappings(nil)
      local orig_groups = vim.deepcopy(before[1].groups)
      theme.build_mappings({ bg = { "Override" } })
      local after = theme.build_mappings(nil)
      assert.are.same(orig_groups, after[1].groups)
    end)
  end)
end)
