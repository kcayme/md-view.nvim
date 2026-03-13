local template = require("md-view.template")

describe("template", function()
  local function make_opts(overrides)
    return vim.tbl_extend("force", {
      css = "",
      theme_css = "",
      palette_css = ":root { --md-bg: #000; }",
      highlight_theme = "vs2015",
      mermaid = { theme = "dark" },
      theme_sync = false,
    }, overrides or {})
  end

  describe("render", function()
    it("returns valid HTML", function()
      local html = template.render(make_opts(), "test.md")
      assert.truthy(html:find("<!DOCTYPE html>"))
      assert.truthy(html:find("</html>"))
    end)

    it("injects the title", function()
      local html = template.render(make_opts(), "my-doc.md")
      assert.truthy(html:find("<title>my%-doc%.md</title>"))
    end)

    it("defaults title to md-view when filename is empty", function()
      local html = template.render(make_opts(), "")
      assert.truthy(html:find("<title>md%-view</title>"))
    end)

    it("defaults title to md-view when filename is nil", function()
      local html = template.render(make_opts(), nil)
      assert.truthy(html:find("<title>md%-view</title>"))
    end)

    it("injects palette CSS", function()
      local opts = make_opts({ palette_css = ":root { --md-bg: #123456; }" })
      local html = template.render(opts, "test.md")
      assert.truthy(html:find("#123456"))
    end)

    it("injects theme CSS", function()
      local opts = make_opts({ theme_css = ".custom { color: red; }" })
      local html = template.render(opts, "test.md")
      assert.truthy(html:find("%.custom { color: red; }"))
    end)

    it("injects user CSS", function()
      local opts = make_opts({ css = "body { font-size: 16px; }" })
      local html = template.render(opts, "test.md")
      assert.truthy(html:find("body { font%-size: 16px; }"))
    end)

    it("injects mermaid theme", function()
      local opts = make_opts({ mermaid = { theme = "forest" } })
      local html = template.render(opts, "test.md")
      assert.truthy(html:find('theme: "forest"'))
    end)

    it("includes highlight link when theme_sync is false", function()
      local opts = make_opts({ theme_sync = false, highlight_theme = "github" })
      local html = template.render(opts, "test.md")
      assert.truthy(html:find("github%.min%.css"))
    end)

    it("omits highlight link when theme_sync is true", function()
      local opts = make_opts({ theme_sync = true })
      local html = template.render(opts, "test.md")
      assert.is_nil(html:find("styles/vs2015"))
    end)

    it("uses pinned CDN versions", function()
      local html = template.render(make_opts(), "test.md")
      assert.truthy(html:find("markdown%-it@14%.1%.0"))
      assert.truthy(html:find("mermaid@11%.4%.1"))
      assert.truthy(html:find("morphdom@2%.7%.4"))
      assert.truthy(html:find("markdown%-it%-task%-lists@2%.1%.1"))
    end)
  end)

  describe("security", function()
    it("HTML-escapes title with angle brackets", function()
      local html = template.render(make_opts(), '</title><script>alert(1)</script>')
      assert.is_nil(html:find("</title><script>"))
      assert.truthy(html:find("&lt;/title&gt;&lt;script&gt;"))
    end)

    it("HTML-escapes title with ampersands", function()
      local html = template.render(make_opts(), "foo&bar")
      assert.truthy(html:find("foo&amp;bar"))
    end)

    it("HTML-escapes title with quotes", function()
      local html = template.render(make_opts(), 'file"name')
      assert.truthy(html:find("file&quot;name"))
    end)

    it("rejects invalid mermaid theme and falls back to default", function()
      local opts = make_opts({ mermaid = { theme = '"; alert(1); "' } })
      local html = template.render(opts, "test.md")
      assert.truthy(html:find('theme: "default"'))
    end)

    it("sanitizes highlight theme name", function()
      local opts = make_opts({
        theme_sync = false,
        highlight_theme = 'vs2015" onload="alert(1)',
      })
      local html = template.render(opts, "test.md")
      -- attribute injection chars (" =) should be stripped
      assert.is_nil(html:find('onload=', 1, true))
      -- the sanitized name should be a single token with no breaks
      assert.truthy(html:find("vs2015onloadalert1", 1, true))
    end)

    it("allows valid mermaid themes", function()
      for _, name in ipairs({ "default", "dark", "forest", "neutral", "base" }) do
        local opts = make_opts({ mermaid = { theme = name } })
        local html = template.render(opts, "test.md")
        assert.truthy(html:find('theme: "' .. name .. '"'), "expected theme: " .. name)
      end
    end)

    it("handles gsub pattern characters in CSS safely", function()
      local opts = make_opts({ css = "body { content: '%1'; }" })
      local html = template.render(opts, "test.md")
      assert.truthy(html:find("%1", 1, true))
    end)

    it("handles gsub pattern characters in palette_css safely", function()
      local opts = make_opts({ palette_css = ":root { --x: '%0'; }" })
      local html = template.render(opts, "test.md")
      assert.truthy(html:find("%0", 1, true))
    end)
  end)
end)
