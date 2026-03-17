local template = require("md-view.server.template")
local vendor = require("md-view.vendor")

describe("template", function()
  local function make_opts(overrides)
    return vim.tbl_extend("force", {
      css = "",
      theme_css = "",
      palette_css = ":root { --md-bg: #000; }",
      highlight_theme = "vs2015",
      notations = {
        mermaid = { enable = true, theme = "dark" },
      },
      theme = "auto",
    }, overrides or {})
  end

  describe("render", function()
    local orig_is_available

    before_each(function()
      orig_is_available = vendor.is_available
      vendor.is_available = function()
        return false
      end
    end)

    after_each(function()
      vendor.is_available = orig_is_available
    end)

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

    it("includes highlight link when theme is not sync", function()
      local opts = make_opts({ theme = "auto", highlight_theme = "github" })
      local html = template.render(opts, "test.md")
      assert.truthy(html:find("github%.min%.css"))
    end)

    it("omits highlight link when theme is sync", function()
      local opts = make_opts({ theme = "sync" })
      local html = template.render(opts, "test.md")
      assert.is_nil(html:find("styles/vs2015"))
    end)

    it("includes mermaid CDN when notations.mermaid.enable is not false", function()
      local html = template.render(make_opts(), "test.md")
      assert.truthy(html:find("mermaid@11%.4%.1"))
    end)

    it("omits mermaid CDN when notations.mermaid.enable is false", function()
      local opts = make_opts({ notations = { mermaid = { enable = false } } })
      local html = template.render(opts, "test.md")
      assert.is_nil(html:find("mermaid@11%.4%.1"))
    end)

    it("uses pinned CDN versions", function()
      local html = template.render(make_opts(), "test.md")
      assert.truthy(html:find("markdown%-it@14%.1%.0"))
      assert.truthy(html:find("mermaid@11%.4%.1"))
      assert.truthy(html:find("morphdom@2%.7%.4"))
      assert.truthy(html:find("markdown%-it%-task%-lists@2%.1%.1"))
    end)

    it("includes KaTeX CDN when notations.katex is true", function()
      local opts = make_opts({ notations = { katex = { enable = true } } })
      local html = template.render(opts, "test.md")
      assert.truthy(html:find("katex@0%.16%.38/dist/katex%.min%.js"))
      assert.truthy(html:find("katex@0%.16%.38/dist/katex%.min%.css"))
      assert.truthy(html:find("markdown%-it%-texmath@1%.0%.0/texmath%.js"))
    end)

    it("excludes KaTeX CDN when notations.katex is false", function()
      local opts = make_opts({ notations = { katex = { enable = false } } })
      local html = template.render(opts, "test.md")
      assert.is_nil(html:find("katex@"))
      assert.is_nil(html:find("markdown%-it%-texmath@"))
    end)

    it("excludes KaTeX CDN when notations is nil", function()
      local opts = make_opts()
      opts.notations = nil
      local html = template.render(opts, "test.md")
      assert.is_nil(html:find("katex@"))
    end)

    it("includes Graphviz CDN when notations.graphviz is true", function()
      local opts = make_opts({ notations = { graphviz = { enable = true } } })
      local html = template.render(opts, "test.md")
      assert.truthy(html:find("@viz%-js/viz@3%.25%.0/dist/viz%-global%.js"))
    end)

    it("excludes Graphviz CDN when notations.graphviz is false", function()
      local opts = make_opts({ notations = { graphviz = { enable = false } } })
      local html = template.render(opts, "test.md")
      assert.is_nil(html:find("viz%-js/viz@"))
    end)

    it("excludes Graphviz CDN when notations is nil", function()
      local opts = make_opts()
      opts.notations = nil
      local html = template.render(opts, "test.md")
      assert.is_nil(html:find("viz%-js/viz@"))
    end)

    it("includes WaveDrom CDN when notations.wavedrom is true", function()
      local opts = make_opts({ notations = { wavedrom = { enable = true } } })
      local html = template.render(opts, "test.md")
      assert.truthy(html:find("wavedrom@3%.5%.0/wavedrom%.min%.js"))
      assert.truthy(html:find("wavedrom@3%.5%.0/skins/default%.js"))
    end)

    it("excludes WaveDrom CDN when notations.wavedrom is false", function()
      local opts = make_opts({ notations = { wavedrom = { enable = false } } })
      local html = template.render(opts, "test.md")
      assert.is_nil(html:find("wavedrom@"))
    end)

    it("excludes WaveDrom CDN when notations is nil", function()
      local opts = make_opts()
      opts.notations = nil
      local html = template.render(opts, "test.md")
      assert.is_nil(html:find("wavedrom@"))
    end)

    it("includes Nomnoml CDN when notations.nomnoml is true", function()
      local opts = make_opts({ notations = { nomnoml = { enable = true } } })
      local html = template.render(opts, "test.md")
      assert.truthy(html:find("graphre@0%.1%.3/dist/graphre%.js"))
      assert.truthy(html:find("nomnoml@1%.6%.2/dist/nomnoml%.min%.js"))
    end)

    it("excludes Nomnoml CDN when notations.nomnoml is false", function()
      local opts = make_opts({ notations = { nomnoml = { enable = false } } })
      local html = template.render(opts, "test.md")
      assert.is_nil(html:find("nomnoml@"))
    end)

    it("excludes Nomnoml CDN when notations is nil", function()
      local opts = make_opts()
      opts.notations = nil
      local html = template.render(opts, "test.md")
      assert.is_nil(html:find("nomnoml@"))
    end)

    it("includes abcjs CDN when notations.abc is true", function()
      local opts = make_opts({ notations = { abc = { enable = true } } })
      local html = template.render(opts, "test.md")
      assert.truthy(html:find("abcjs@6%.4%.4/dist/abcjs%-basic%-min%.js"))
    end)

    it("excludes abcjs CDN when notations.abc is false", function()
      local opts = make_opts({ notations = { abc = { enable = false } } })
      local html = template.render(opts, "test.md")
      assert.is_nil(html:find("abcjs@"))
    end)

    it("excludes abcjs CDN when notations is nil", function()
      local opts = make_opts()
      opts.notations = nil
      local html = template.render(opts, "test.md")
      assert.is_nil(html:find("abcjs@"))
    end)

    it("includes Vega-Lite CDN when notations.vegalite is true", function()
      local opts = make_opts({ notations = { vegalite = { enable = true } } })
      local html = template.render(opts, "test.md")
      assert.truthy(html:find("vega@5%.30%.0/build/vega%.min%.js"))
      assert.truthy(html:find("vega%-lite@5%.21%.0/build/vega%-lite%.min%.js"))
      assert.truthy(html:find("vega%-embed@6%.26%.0/build/vega%-embed%.min%.js"))
    end)

    it("excludes Vega-Lite CDN when notations.vegalite is false", function()
      local opts = make_opts({ notations = { vegalite = { enable = false } } })
      local html = template.render(opts, "test.md")
      assert.is_nil(html:find("vega@"))
      assert.is_nil(html:find("vega%-lite@"))
      assert.is_nil(html:find("vega%-embed@"))
    end)

    it("excludes Vega-Lite CDN when notations is nil", function()
      local opts = make_opts()
      opts.notations = nil
      local html = template.render(opts, "test.md")
      assert.is_nil(html:find("vega@"))
    end)
  end)

  describe("error handling", function()
    local html

    before_each(function()
      html = template.render(
        make_opts({
          notations = {
            mermaid = { enable = true },
            katex = { enable = true },
            graphviz = { enable = true },
            wavedrom = { enable = true },
            nomnoml = { enable = true },
            abc = { enable = true },
            vegalite = { enable = true },
          },
        }),
        "test.md"
      )
    end)

    it("should include error popup markup", function()
      assert.truthy(html:find('id="notation%-popup"'))
      assert.truthy(html:find('class="notation%-popup%-header"'))
      assert.truthy(html:find('id="notation%-popup%-body"'))
      assert.truthy(html:find('id="notation%-popup%-close"'))
    end)

    it("should include floating action button markup", function()
      assert.truthy(html:find('id="notation%-fab"'))
      assert.truthy(html:find('id="notation%-fab%-badge"'))
      assert.truthy(html:find('style="display:none"'))
    end)

    it("should not include old toast markup", function()
      assert.is_nil(html:find("notation%-toast"))
      assert.is_nil(html:find("toastEl"))
      assert.is_nil(html:find("toastTimer"))
      assert.is_nil(html:find("toastQueue"))
    end)

    it("should define notifyError with notation and source parameters", function()
      assert.truthy(html:find("function notifyError%(notation, source%)"))
    end)

    it("should reset error state at start of renderMarkdown", function()
      assert.truthy(html:find("errorEntries = %[%];"))
      assert.truthy(html:find('fab%.style%.display = "none"'))
    end)

    it("should pass source to notifyError for Mermaid errors", function()
      assert.truthy(html:find('notifyError%("Mermaid", mermaidSources'))
    end)

    it("should pass source to notifyError for KaTeX errors", function()
      assert.truthy(html:find('notifyError%("KaTeX", source%)'))
    end)

    it("should pass source to notifyError for Graphviz errors", function()
      assert.truthy(html:find('notifyError%("Graphviz", source%)'))
    end)

    it("should pass source to notifyError for WaveDrom errors", function()
      assert.truthy(html:find('notifyError%("WaveDrom", source%)'))
    end)

    it("should pass source to notifyError for Nomnoml errors", function()
      assert.truthy(html:find('notifyError%("Nomnoml", source%)'))
    end)

    it("should pass source to notifyError for ABC errors", function()
      assert.truthy(html:find('notifyError%("ABC", source%)'))
    end)

    it("should pass source to notifyError for all Vega-Lite error paths", function()
      -- Find all notifyError("Vega-Lite" calls and ensure none are missing source
      local pos = 1
      local count = 0
      while true do
        local s = html:find('notifyError%("Vega%-Lite"', pos)
        if not s then
          break
        end
        count = count + 1
        -- Verify this call includes source as second arg
        local call_end = html:find("%)", s)
        local call = html:sub(s, call_end)
        assert.truthy(call:find("source"), "Vega-Lite notifyError call #" .. count .. " missing source arg")
        pos = s + 1
      end
      assert.are.equal(2, count, "expected 2 Vega-Lite notifyError calls (sync + async)")
    end)

    it("should build popup items with notation name and source preview", function()
      assert.truthy(html:find("entry%.notation"))
      assert.truthy(html:find("entry%.source"))
      assert.truthy(html:find("notation%-popup%-item"))
    end)
  end)

  describe("security", function()
    local orig_is_available

    before_each(function()
      orig_is_available = vendor.is_available
      vendor.is_available = function()
        return false
      end
    end)

    after_each(function()
      vendor.is_available = orig_is_available
    end)

    it("HTML-escapes title with angle brackets", function()
      local html = template.render(make_opts(), "</title><script>alert(1)</script>")
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
        highlight_theme = 'vs2015" onload="alert(1)',
      })
      local html = template.render(opts, "test.md")
      -- attribute injection chars (" =) should be stripped
      assert.is_nil(html:find("onload=", 1, true))
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

  describe("load failure", function()
    local orig_get_runtime
    local orig_template

    before_each(function()
      -- Save and clear the cached module so we get a fresh load
      orig_template = package.loaded["md-view.server.template"]
      package.loaded["md-view.server.template"] = nil
      -- Save the real nvim_get_runtime_file
      orig_get_runtime = vim.api.nvim_get_runtime_file
    end)

    after_each(function()
      -- Restore module cache and API
      package.loaded["md-view.server.template"] = orig_template
      vim.api.nvim_get_runtime_file = orig_get_runtime
    end)

    it("returns empty string when template file is not found", function()
      vim.api.nvim_get_runtime_file = function()
        return {}
      end
      local M = require("md-view.server.template")
      local result = M.render({
        css = "",
        theme_css = "",
        palette_css = "",
        highlight_theme = "vs2015",
        mermaid = { theme = "default" },
        theme = "auto",
      }, "test.md")
      assert.equals("", result)
    end)

    it("does not retry after a failed load", function()
      local call_count = 0
      vim.api.nvim_get_runtime_file = function()
        call_count = call_count + 1
        return {}
      end
      local M = require("md-view.server.template")
      local opts = {
        css = "",
        theme_css = "",
        palette_css = "",
        highlight_theme = "vs2015",
        mermaid = { theme = "default" },
        theme = "auto",
      }
      M.render(opts, "test.md")
      M.render(opts, "test.md")
      -- nvim_get_runtime_file should only be called once despite two render calls
      assert.equals(1, call_count)
    end)

    it("returns empty string when template file is empty", function()
      local orig_open = io.open
      io.open = function(path, mode)
        return {
          read = function()
            return ""
          end,
          close = function() end,
        }
      end
      local M = require("md-view.server.template")
      local result = M.render({
        css = "",
        theme_css = "",
        palette_css = "",
        highlight_theme = "vs2015",
        mermaid = { theme = "default" },
        theme = "auto",
      }, "test.md")
      io.open = orig_open
      assert.equals("", result)
    end)
  end)

  describe("load caching", function()
    local orig_open
    local orig_template

    before_each(function()
      orig_template = package.loaded["md-view.server.template"]
      package.loaded["md-view.server.template"] = nil
      orig_open = io.open
    end)

    after_each(function()
      package.loaded["md-view.server.template"] = orig_template
      io.open = orig_open
    end)

    it("calls io.open only once across two render calls", function()
      local open_count = 0
      io.open = function(path, mode)
        open_count = open_count + 1
        return orig_open(path, mode)
      end
      local M = require("md-view.server.template")
      local opts = {
        css = "",
        theme_css = "",
        palette_css = "",
        highlight_theme = "vs2015",
        mermaid = { theme = "default" },
        theme = "auto",
      }
      M.render(opts, "test.md")
      M.render(opts, "test.md")
      assert.equals(1, open_count)
    end)
  end)
end)
