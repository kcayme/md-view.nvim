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
<title>md-view</title>
<script src="https://cdn.jsdelivr.net/npm/markdown-it@14/dist/markdown-it.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/morphdom@2/dist/morphdom-umd.min.js"></script>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe WPC", "Segoe UI", system-ui, Ubuntu, "Droid Sans", sans-serif;
    font-size: 14px;
    line-height: 1.6;
    color: #cccccc;
    background: #1e1e1e;
    padding: 0 26px;
    max-width: 882px;
    margin: 0 auto;
    word-wrap: break-word;
  }
  h1, h2, h3, h4, h5, h6 {
    color: #cccccc;
    margin-top: 24px;
    margin-bottom: 16px;
    line-height: 1.25;
  }
  h1 { font-size: 2em; font-weight: 700; padding-bottom: 0.3em; border-bottom: 1px solid #65634f33; }
  h2 { font-size: 1.5em; font-weight: 650; padding-bottom: 0.3em; border-bottom: 1px solid #65634f33; }
  h3 { font-size: 1.25em; font-weight: 600; }
  h4 { font-size: 1em; font-weight: 550; }
  h5 { font-size: 0.875em; font-weight: 500; }
  h6 { font-size: 0.85em; font-weight: 450; color: #8b949e; }
  p { margin-bottom: 16px; }
  a { color: #4080d0; text-decoration: none; }
  a:hover { text-decoration: underline; }
  strong { font-weight: 600; }
  code {
    font-family: Menlo, Monaco, Consolas, "Droid Sans Mono", "Courier New", monospace, "Droid Sans Fallback";
    font-size: 1em;
    padding: 1px 3px;
    color: #d19a66;
    border-radius: 3px;
  }
  pre {
    background: #282828;
    padding: 16px;
    border-radius: 3px;
    overflow-x: auto;
    margin-bottom: 16px;
  }
  pre code {
    color: #d4d4d4;
    padding: 0;
    font-size: 14px;
    line-height: 19px;
    background: none;
    word-break: normal;
    white-space: pre;
  }
  blockquote {
    border-left: 4px solid #444;
    padding: 0 16px;
    color: #8b949e;
    margin: 0 0 16px 0;
  }
  blockquote p:last-child { margin-bottom: 0; }
  table { border-collapse: collapse; width: 100%; margin-bottom: 16px; }
  th, td { border: 1px solid #444; padding: 6px 13px; }
  th { background: #282828; font-weight: 600; }
  tr:nth-child(even) { background: #ffffff06; }
  img { max-width: 100%; }
  ul, ol { padding-left: 2em; margin-bottom: 16px; }
  li { margin-bottom: 0; }
  li + li { margin-top: 4px; }
  li > p { margin-bottom: 0; }
  li > ul, li > ol { margin-bottom: 0; margin-top: 4px; }
  hr { border: none; border-top: 1px solid #444; margin: 24px 0; }
  input[type="checkbox"] { margin-right: 4px; vertical-align: middle; }
  .mermaid-wrapper { margin-bottom: 16px; }
  .mermaid-wrapper svg { max-width: 100%; }
  %%CSS%%
</style>
</head>
<body>
<div id="content"></div>
<script>
(function() {
  mermaid.initialize({ startOnLoad: false, theme: "%%MERMAID_THEME%%" });

  var md = window.markdownit({ html: true, linkify: true, typographer: true });

  function stripFrontMatter(text) {
    var match = text.match(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/);
    return match ? text.slice(match[0].length) : text;
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
    var html = md.render(stripFrontMatter(text));
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

  source.addEventListener("content", function(e) {
    var d = JSON.parse(e.data);
    renderMarkdown(d.content);
  });

  source.addEventListener("scroll", function(e) {
    var d = JSON.parse(e.data);
    var line = d.line;
    var best = null;
    var bestDist = Infinity;
    container.querySelectorAll("[data-source-line]").forEach(function(el) {
      var sl = parseInt(el.getAttribute("data-source-line"), 10);
      var dist = Math.abs(sl - line);
      if (dist < bestDist) {
        bestDist = dist;
        best = el;
      }
    });
    if (best) {
      best.scrollIntoView({ behavior: "smooth", block: "center" });
    }
  });
})();
</script>
</body>
</html>
]]

function M.render(opts)
  local css = opts.css or ""
  local mermaid_theme = opts.mermaid and opts.mermaid.theme or "default"
  local html = TEMPLATE:gsub("%%%%CSS%%%%", css:gsub("%%", "%%%%")):gsub("%%%%MERMAID_THEME%%%%", mermaid_theme)
  return html
end

return M
