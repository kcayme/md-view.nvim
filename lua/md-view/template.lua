local M = {}

-- NOTE: innerHTML usage here is safe — this is a local-only preview server
-- (127.0.0.1) rendering the user's own markdown buffer content. No untrusted
-- external content is involved. morphdom requires innerHTML for DOM diffing.

local TEMPLATE = [[
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>%%TITLE%%</title>
<script src="https://cdn.jsdelivr.net/npm/markdown-it@14.1.0/dist/markdown-it.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/markdown-it-task-lists@2.1.1/dist/markdown-it-task-lists.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/morphdom@2.7.4/dist/morphdom-umd.min.js"></script>
%%HIGHLIGHT_LINK%%
<script src="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11/build/highlight.min.js"></script>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe WPC", "Segoe UI", system-ui, Ubuntu, "Droid Sans", sans-serif;
    font-size: 14px;
    line-height: 1.6;
    color: var(--md-fg);
    background: var(--md-bg);
    padding: 0 26px;
    max-width: 882px;
    margin: 0 auto;
    word-wrap: break-word;
  }
  h1, h2, h3, h4, h5, h6 {
    color: var(--md-heading);
    margin-top: 24px;
    margin-bottom: 16px;
    line-height: 1.25;
  }
  h1 { font-size: 2em; font-weight: 700; padding-bottom: 0.3em; border-bottom: 1px solid var(--md-border); }
  h2 { font-size: 1.5em; font-weight: 650; padding-bottom: 0.3em; border-bottom: 1px solid var(--md-border); }
  h3 { font-size: 1.25em; font-weight: 600; }
  h4 { font-size: 1em; font-weight: 550; }
  h5 { font-size: 0.875em; font-weight: 500; }
  h6 { font-size: 0.85em; font-weight: 450; color: var(--md-muted); }
  p { margin-bottom: 16px; }
  a { color: var(--md-link); text-decoration: none; }
  a:hover { text-decoration: underline; }
  strong { font-weight: 600; color: var(--md-bold); }
  code {
    font-family: Menlo, Monaco, Consolas, "Droid Sans Mono", "Courier New", monospace, "Droid Sans Fallback";
    font-size: 1em;
    padding: 2px 6px;
    color: var(--md-code-fg);
    background: var(--md-code-bg);
    border-radius: 4px;
  }
  pre {
    background: var(--md-code-bg);
    padding: 16px;
    border-radius: 3px;
    overflow-x: auto;
    margin-bottom: 16px;
  }
  pre code {
    color: var(--md-pre-fg);
    padding: 0;
    font-size: 14px;
    line-height: 19px;
    background: none;
    word-break: normal;
    white-space: pre;
  }
  blockquote {
    border-left: 4px solid var(--md-border);
    padding: 0 16px;
    color: var(--md-fg);
    margin: 0 0 16px 0;
  }
  blockquote p:last-child { margin-bottom: 0; }
  table { border-collapse: collapse; width: 100%; margin-bottom: 16px; }
  th, td { border: 1px solid var(--md-border); padding: 6px 13px; }
  th { background: var(--md-table-header-bg); font-weight: 600; }
  tr:nth-child(even) { background: var(--md-row-alt); }
  img { max-width: 100%; }
  ul, ol { padding-left: 2em; margin-bottom: 16px; }
  li { margin-bottom: 0; }
  li + li { margin-top: 4px; }
  li > p { margin-bottom: 0; }
  li > ul, li > ol { margin-bottom: 0; margin-top: 4px; }
  hr { border: none; height: 2px; background: var(--md-border); margin: 24px 0; }
  .task-list-item { list-style: none; }
  .task-list-item input[type="checkbox"] {
    margin: 0 0.35em 0 -1.6em;
    vertical-align: middle;
    appearance: none;
    width: 16px;
    height: 16px;
    border: 1px solid var(--md-border);
    border-radius: 3px;
    background: transparent;
    cursor: default;
    position: relative;
  }
  .task-list-item input[type="checkbox"]:checked {
    background: var(--md-checkbox);
    border-color: var(--md-checkbox);
  }
  .task-list-item input[type="checkbox"]:checked::after {
    content: "";
    position: absolute;
    left: 4px;
    top: 1px;
    width: 5px;
    height: 9px;
    border: solid #fff;
    border-width: 0 2px 2px 0;
    transform: rotate(45deg);
  }
  .front-matter { margin-top: 24px; margin-bottom: 24px; }
  .front-matter table { border-collapse: collapse; width: 100%; }
  .front-matter th, .front-matter td {
    border: 1px solid var(--md-border);
    padding: 4px 10px;
    text-align: left;
    font-size: 13px;
    font-family: Menlo, Monaco, Consolas, "Droid Sans Mono", "Courier New", monospace;
  }
  .front-matter th { background: var(--md-code-bg); color: var(--md-fg); font-weight: 600; width: 120px; }
  .front-matter td { color: var(--md-fg); }
  .mermaid-wrapper { margin-bottom: 16px; }
  .mermaid-wrapper svg { max-width: 100%; }
  %%PALETTE_CSS%%
  %%THEME_CSS%%
  %%CSS%%
</style>
</head>
<body>
<div id="content"></div>
<script>
(function() {
  mermaid.initialize({ startOnLoad: false, theme: "%%MERMAID_THEME%%" });

  var md = window.markdownit({
    html: true, linkify: true, typographer: true,
    highlight: function(str, lang) {
      if (lang && hljs.getLanguage(lang)) {
        try { return hljs.highlight(str, { language: lang }).value; } catch (_) {}
      }
      return "";
    }
  }).use(window.markdownitTaskLists);

  function parseFrontMatter(text) {
    var match = text.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/);
    if (!match) return { body: text, html: "" };
    var body = text.slice(match[0].length);
    var lines = match[1].split(/\r?\n/);
    var rows = [];
    var currentKey = null;
    var currentValues = [];

    function flushKey() {
      if (currentKey !== null) {
        rows.push({ key: currentKey, value: currentValues.join(", ") });
        currentValues = [];
      }
    }

    lines.forEach(function(line) {
      var kvMatch = line.match(/^(\w[\w\s-]*):\s*(.*)/);
      var listMatch = line.match(/^\s+-\s+(.*)/);
      if (kvMatch) {
        flushKey();
        currentKey = kvMatch[1].trim();
        if (kvMatch[2].trim()) {
          currentValues.push(kvMatch[2].trim());
        }
      } else if (listMatch && currentKey) {
        currentValues.push(listMatch[1].trim());
      }
    });
    flushKey();

    if (rows.length === 0) return { body: body, html: "" };

    function esc(s) {
      var el = document.createElement("span");
      el.textContent = s;
      return el.innerHTML;
    }

    var html = '<div class="front-matter" data-source-line="0"><table>';
    rows.forEach(function(r) {
      html += "<tr><th>" + esc(r.key) + "</th><td>" + esc(r.value) + "</td></tr>";
    });
    html += "</table></div>";
    return { body: body, html: html };
  }

  var defaultFence = md.renderer.rules.fence || function(tokens, idx, options, env, self) {
    return self.renderToken(tokens, idx, options);
  };

  md.renderer.rules.fence = function(tokens, idx, options, env, self) {
    var token = tokens[idx];
    if (token.info.trim() === "mermaid") {
      var line = token.map ? token.map[0] : "";
      return '<div class="mermaid-wrapper" data-source-line="' + line + '"><pre class="mermaid">' +
        md.utils.escapeHtml(token.content) + '</pre></div>';
    }
    return defaultFence(tokens, idx, options, env, self);
  };

  function addSourceLine(origRule) {
    return function(tokens, idx, options, env, self) {
      var token = tokens[idx];
      if (token.map && token.map.length) {
        token.attrSet("data-source-line", token.map[0]);
      }
      if (origRule) {
        return origRule(tokens, idx, options, env, self);
      }
      return self.renderToken(tokens, idx, options);
    };
  }

  var blockRules = [
    "paragraph_open", "heading_open", "blockquote_open",
    "bullet_list_open", "ordered_list_open", "table_open",
    "code_block", "hr"
  ];
  blockRules.forEach(function(rule) {
    md.renderer.rules[rule] = addSourceLine(md.renderer.rules[rule]);
  });

  var container = document.getElementById("content");

  function renderMarkdown(text) {
    var fm = parseFrontMatter(text);
    var html = fm.html + md.render(fm.body);
    var tmp = document.createElement("div");
    // Safe: content is the user's own local markdown buffer, served only on 127.0.0.1
    tmp.innerHTML = html;
    morphdom(container, tmp, { childrenOnly: true });
    container.querySelectorAll("pre.mermaid").forEach(function(el) {
      if (el.getAttribute("data-processed")) {
        el.removeAttribute("data-processed");
      }
    });
    mermaid.run({ nodes: container.querySelectorAll("pre.mermaid") });
  }

  fetch("/content")
    .then(function(r) { return r.json(); })
    .then(function(d) { renderMarkdown(d.content); });

  var source = new EventSource("/events");

  var channel = new BroadcastChannel("mdview_" + location.port);
  channel.onmessage = function(e) {
    if (e.data === "takeover") {
      source.close();
      channel.close();
      window.close();
      document.body.innerHTML = '<p style="text-align:center;margin-top:40vh;color:#888;">Preview moved to new tab</p>';
    }
  };
  channel.postMessage("takeover");

  source.addEventListener("content", function(e) {
    var d = JSON.parse(e.data);
    renderMarkdown(d.content);
  });

  source.addEventListener("theme", function(e) {
    var d = JSON.parse(e.data);
    var style = document.getElementById("md-view-theme");
    if (!style) {
      style = document.createElement("style");
      style.id = "md-view-theme";
      document.head.appendChild(style);
    }
    style.textContent = d.css;
  });

  source.addEventListener("close", function(e) {
    window.close();
    // Fallback if window.close() is blocked by browser
    document.body.innerHTML = '<p style="text-align:center;margin-top:40vh;color:#888;">Preview closed</p>';
  });

  source.addEventListener("scroll", function(e) {
    var d = JSON.parse(e.data);
    if (d.percent != null) {
      var maxScroll = document.documentElement.scrollHeight - window.innerHeight;
      window.scrollTo({ top: d.percent * maxScroll, behavior: "smooth" });
    } else if (d.line != null) {
      var best = null;
      var bestDist = Infinity;
      container.querySelectorAll("[data-source-line]").forEach(function(el) {
        var sl = parseInt(el.getAttribute("data-source-line"), 10);
        var dist = Math.abs(sl - d.line);
        if (dist < bestDist) {
          bestDist = dist;
          best = el;
        }
      });
      if (best) {
        best.scrollIntoView({ behavior: "smooth", block: "center" });
      }
    }
  });
})();
</script>
</body>
</html>
]]

local VALID_MERMAID_THEMES = {
  default = true, dark = true, forest = true, neutral = true, base = true,
}

local function html_escape(str)
  return str:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&#39;")
end

local function sanitize_theme_name(name)
  return name:gsub("[^%w_%-]", "")
end

function M.render(opts, filename)
  local css = opts.css or ""
  local mermaid_theme = opts.mermaid and opts.mermaid.theme or "default"
  local highlight_theme = opts.highlight_theme or "vs2015"
  local title = filename and filename ~= "" and filename or "md-view"
  local theme_css = opts.theme_css or ""
  local palette_css = opts.palette_css or ""

  if not VALID_MERMAID_THEMES[mermaid_theme] then
    mermaid_theme = "default"
  end
  highlight_theme = sanitize_theme_name(highlight_theme)
  title = html_escape(title)

  local highlight_link = ""
  if not opts.theme_sync then
    highlight_link = '<link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11/build/styles/'
      .. highlight_theme .. '.min.css">'
  end
  local html = TEMPLATE
    :gsub("%%%%PALETTE_CSS%%%%", function() return palette_css end)
    :gsub("%%%%THEME_CSS%%%%", function() return theme_css end)
    :gsub("%%%%CSS%%%%", function() return css end)
    :gsub("%%%%MERMAID_THEME%%%%", function() return mermaid_theme end)
    :gsub("%%%%HIGHLIGHT_LINK%%%%", function() return highlight_link end)
    :gsub("%%%%TITLE%%%%", function() return title end)
  return html
end

return M
