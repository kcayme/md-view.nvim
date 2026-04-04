function safeParse(raw) {
  try { return JSON.parse(raw); } catch (_) { return null; }
}

var vizPromise = (typeof Viz !== 'undefined') ? Viz.instance() : null;

var md = window.markdownit({
  html: true, linkify: true, typographer: true,
  highlight: function(str, lang) {
    if (typeof hljs !== 'undefined' && lang && hljs.getLanguage(lang)) {
      try { return hljs.highlight(str, { language: lang }).value; } catch (_) {}
    }
    return "";
  }
}).use(window.markdownitTaskLists);

if (typeof texmath !== 'undefined' && typeof katex !== 'undefined') {
  md.use(texmath, { engine: katex, delimiters: 'dollars' });
}

var notationMap = {
  mermaid: { wrapper: "mermaid-wrapper", tag: "pre", cls: "mermaid" },
};
if (typeof katex !== 'undefined') {
  notationMap["math"] = { wrapper: "katex-wrapper", tag: "code", cls: "katex-source", hide: true };
}
if (typeof Viz !== 'undefined') {
  notationMap["dot"] = { wrapper: "graphviz-wrapper", tag: "code", cls: "graphviz-source", hide: true };
  notationMap["graphviz"] = { wrapper: "graphviz-wrapper", tag: "code", cls: "graphviz-source", hide: true };
}
if (typeof WaveDrom !== 'undefined') {
  notationMap["wavedrom"] = { wrapper: "wavedrom-wrapper", tag: "code", cls: "wavedrom-source", hide: true };
}
if (typeof nomnoml !== 'undefined') {
  notationMap["nomnoml"] = { wrapper: "nomnoml-wrapper", tag: "code", cls: "nomnoml-source", hide: true };
}
if (typeof ABCJS !== 'undefined') {
  notationMap["abc"] = { wrapper: "abc-wrapper", tag: "code", cls: "abc-source", hide: true };
}
if (typeof vegaEmbed !== 'undefined') {
  notationMap["vega-lite"] = { wrapper: "vegalite-wrapper", tag: "code", cls: "vegalite-source", hide: true };
}

var defaultFence = md.renderer.rules.fence || function(tokens, idx, options, env, self) {
  return self.renderToken(tokens, idx, options);
};

md.renderer.rules.fence = function(tokens, idx, options, env, self) {
  var token = tokens[idx];
  var lang = token.info.trim();
  var notation = notationMap[lang];
  if (notation) {
    var line = token.map ? token.map[0] : "";
    var style = notation.hide ? ' style="display:none"' : '';
    return '<div class="' + notation.wrapper + '" data-source-line="' + line + '">' +
      '<' + notation.tag + ' class="' + notation.cls + '"' + style + '>' +
      md.utils.escapeHtml(token.content) +
      '</' + notation.tag + '>' + '</div>';
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

var LOCAL_SRC_PASS = /^(https?:|data:|blob:|#)/i;
var LOCAL_MEDIA_EXT = /\.(png|jpe?g|gif|svg|webp|avif|bmp|ico|mp4|webm|mov|og[gva]|mp3|wav|flac)$/i;

// fileId: preview id for mux mode (/file?id=X&path=...) or null for direct mode (/file?path=...)
function rewriteLocalSrcs(root, fileId) {
  var prefix = fileId ? '/file?id=' + fileId + '&path=' : '/file?path=';
  root.querySelectorAll('img[src], video[src], audio[src], source[src]').forEach(function(el) {
    var src = el.getAttribute('src');
    if (src && !LOCAL_SRC_PASS.test(src)) {
      el.setAttribute('src', prefix + encodeURIComponent(src));
    }
  });
  root.querySelectorAll('a[href]').forEach(function(el) {
    var href = el.getAttribute('href');
    if (href && !LOCAL_SRC_PASS.test(href) && LOCAL_MEDIA_EXT.test(href)) {
      el.setAttribute('href', prefix + encodeURIComponent(href));
    }
  });
}

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

function attachCopyButtons(container) {
  var blocks = container.querySelectorAll("pre:not([data-has-copy])");
  blocks.forEach(function(pre) {
    var code = pre.querySelector("code");
    if (!code) return;
    pre.setAttribute("data-has-copy", "1");
    var wrapper = document.createElement("div");
    wrapper.className = "pre-wrap";
    pre.parentNode.insertBefore(wrapper, pre);
    wrapper.appendChild(pre);
    var btn = document.createElement("button");
    btn.className = "copy-btn";
    var iconCopy = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="14" height="14" x="8" y="8" rx="2" ry="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/></svg>';
    var iconCheck = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#3fb950" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>';
    btn.innerHTML = iconCopy;
    btn.title = "Copy";
    btn.addEventListener("click", function() {
      navigator.clipboard.writeText(code.textContent).then(function() {
        btn.innerHTML = '<span class="copy-label">Copied!</span>' + iconCheck;
        btn.classList.add("copied");
        setTimeout(function() {
          btn.classList.add("fading");
          setTimeout(function() {
            btn.innerHTML = iconCopy;
            btn.classList.remove("copied");
            btn.classList.remove("fading");
          }, 400);
        }, 1600);
      });
    });
    var col = document.createElement("div");
    col.className = "copy-col";
    col.appendChild(btn);
    wrapper.appendChild(col);
  });
}

// Creates notation error popup + FAB, appended to document.body.
// Returns { notifyError(notation, source), clearErrors() }.
function makeErrorUI() {
  var errorEntries = [];
  var errorFlushTimer = null;

  var popupEl = document.createElement("div");
  popupEl.className = "notation-popup";
  var popupHeader = document.createElement("div");
  popupHeader.className = "notation-popup-header";
  var popupTitle = document.createElement("span");
  popupTitle.textContent = "Rendering Errors";
  var popupClose = document.createElement("button");
  popupClose.textContent = "\u00d7";
  popupHeader.appendChild(popupTitle);
  popupHeader.appendChild(popupClose);
  var popupBody = document.createElement("div");
  popupBody.className = "notation-popup-body";
  popupEl.appendChild(popupHeader);
  popupEl.appendChild(popupBody);
  document.body.appendChild(popupEl);

  var fab = document.createElement("button");
  fab.className = "notation-fab";
  fab.style.display = "none";
  fab.innerHTML = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#e45649" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>';
  var fabBadge = document.createElement("span");
  fabBadge.className = "notation-fab-badge";
  fabBadge.textContent = "0";
  fab.appendChild(fabBadge);
  document.body.appendChild(fab);

  popupClose.addEventListener("click", function() { popupEl.classList.remove("show"); });
  fab.addEventListener("click", function() { popupEl.classList.toggle("show"); });

  function notifyError(notation, src) {
    console.error("md-view: " + notation + " render error", src || "");
    errorEntries.push({ notation: notation, source: src || "" });
    if (errorFlushTimer) clearTimeout(errorFlushTimer);
    errorFlushTimer = setTimeout(function() {
      popupBody.textContent = "";
      errorEntries.forEach(function(entry) {
        var item = document.createElement("div");
        item.className = "notation-popup-item";
        var title = document.createElement("strong");
        title.textContent = entry.notation;
        item.appendChild(title);
        if (entry.source) {
          var preview = document.createElement("pre");
          preview.textContent = entry.source.length > 200
            ? entry.source.slice(0, 200) + "\u2026"
            : entry.source;
          item.appendChild(preview);
        }
        popupBody.appendChild(item);
      });
      fabBadge.textContent = errorEntries.length;
      fab.style.display = "";
    }, 100);
  }

  function clearErrors() {
    errorEntries = [];
    fab.style.display = "none";
    popupEl.classList.remove("show");
  }

  return { notifyError: notifyError, clearErrors: clearErrors };
}

// Scrolls to the closest element matching a scroll data event.
// data.percent: 0-1 fraction of document height
// data.line: source line number to scroll nearest annotated element into view
function scrollToSource(container, data) {
  if (data.percent != null) {
    var maxScroll = document.documentElement.scrollHeight - window.innerHeight;
    window.scrollTo({ top: data.percent * maxScroll, behavior: "smooth" });
  } else if (data.line != null) {
    var best = null;
    var bestDist = Infinity;
    container.querySelectorAll("[data-source-line]").forEach(function(el) {
      var sl = parseInt(el.getAttribute("data-source-line"), 10);
      var dist = Math.abs(sl - data.line);
      if (dist < bestDist) {
        bestDist = dist;
        best = el;
      }
    });
    if (best) {
      best.scrollIntoView({ behavior: "smooth", block: "center" });
    }
  }
}

// Returns a renderMarkdown(text) function.
// container: DOM element to render into
// fileId: preview id for mux mode, or null for direct mode
// onError(notation, source): called when a notation render fails
// onClearErrors(): called at start of each render
function makeRenderer(container, fileId, onError, onClearErrors) {
  var lastContent = null;

  function _render(text) {
    onClearErrors();
    var fm = parseFrontMatter(text);
    var html = fm.html + md.render(fm.body);
    var tmp = document.createElement("div");
    // Safe: content is the user's own local markdown buffer, served only on 127.0.0.1
    tmp.innerHTML = html;
    rewriteLocalSrcs(tmp, fileId);
    morphdom(container, tmp, { childrenOnly: true });

    var mermaidNodes = container.querySelectorAll("pre.mermaid");
    var mermaidSources = {};
    mermaidNodes.forEach(function(el) {
      if (el.getAttribute("data-processed")) {
        el.removeAttribute("data-processed");
      }
      var wrapper = el.closest(".mermaid-wrapper");
      var line = wrapper ? wrapper.getAttribute("data-source-line") : null;
      if (line) mermaidSources[line] = el.textContent;
    });
    function fixMermaidErrors() {
      var hadError = false;
      container.querySelectorAll(".mermaid-wrapper").forEach(function(wrapper) {
        if (wrapper.querySelector(".error-icon")) {
          var line = wrapper.getAttribute("data-source-line");
          wrapper.textContent = mermaidSources[line] || "";
          wrapper.classList.add("notation-error");
          hadError = true;
        }
      });
      if (hadError) {
        container.querySelectorAll(".mermaid-wrapper.notation-error").forEach(function(wrapper) {
          var line = wrapper.getAttribute("data-source-line");
          onError("Mermaid", mermaidSources[line] || "");
        });
      }
    }
    if (typeof mermaid !== 'undefined') {
      try {
        mermaid.run({ nodes: mermaidNodes }).then(fixMermaidErrors).catch(fixMermaidErrors);
      } catch (e) {
        fixMermaidErrors();
      }
    }

    if (typeof katex !== 'undefined') {
      container.querySelectorAll(".katex-wrapper").forEach(function(el) {
        if (!el.getAttribute("data-rendered")) {
          var sourceEl = el.querySelector(".katex-source");
          if (sourceEl) {
            var source = sourceEl.textContent;
            sourceEl.remove();
            try {
              katex.render(source, el, { displayMode: true, throwOnError: true });
            } catch (e) {
              el.textContent = source;
              el.classList.add("notation-error");
              onError("KaTeX", source);
            }
          }
          el.setAttribute("data-rendered", "true");
        }
      });
    }

    if (vizPromise) {
      var graphvizEls = container.querySelectorAll(".graphviz-wrapper:not([data-rendered])");
      if (graphvizEls.length > 0) {
        vizPromise.then(function(viz) {
          graphvizEls.forEach(function(el) {
            if (el.getAttribute("data-rendered")) return;
            var sourceEl = el.querySelector(".graphviz-source");
            if (sourceEl) {
              var source = sourceEl.textContent;
              sourceEl.remove();
              try {
                var svg = viz.renderSVGElement(source);
                el.appendChild(svg);
              } catch (e) {
                el.textContent = source;
                el.classList.add("notation-error");
                onError("Graphviz", source);
              }
            }
            el.setAttribute("data-rendered", "true");
          });
        });
      }
    }

    if (typeof WaveDrom !== 'undefined') {
      container.querySelectorAll(".wavedrom-wrapper:not([data-rendered])").forEach(function(el, idx) {
        var sourceEl = el.querySelector(".wavedrom-source");
        if (sourceEl) {
          var source = sourceEl.textContent;
          sourceEl.remove();
          try {
            var json = JSON.parse(source);
            var divId = "wdg_" + Date.now() + "_" + idx;
            var div = document.createElement("div");
            div.id = divId + "0";
            el.appendChild(div);
            WaveDrom.RenderWaveForm(0, json, divId);
          } catch (e) {
            el.textContent = source;
            el.classList.add("notation-error");
            onError("WaveDrom", source);
          }
          el.setAttribute("data-rendered", "true");
        }
      });
    }

    if (typeof nomnoml !== 'undefined') {
      container.querySelectorAll(".nomnoml-wrapper:not([data-rendered])").forEach(function(el) {
        var sourceEl = el.querySelector(".nomnoml-source");
        if (sourceEl) {
          var source = sourceEl.textContent;
          sourceEl.remove();
          try {
            el.innerHTML = nomnoml.renderSvg(source);
          } catch (e) {
            el.textContent = source;
            el.classList.add("notation-error");
            onError("Nomnoml", source);
          }
          el.setAttribute("data-rendered", "true");
        }
      });
    }

    if (typeof ABCJS !== 'undefined') {
      container.querySelectorAll(".abc-wrapper:not([data-rendered])").forEach(function(el) {
        var sourceEl = el.querySelector(".abc-source");
        if (sourceEl) {
          var source = sourceEl.textContent;
          sourceEl.remove();
          try {
            var renderDiv = document.createElement("div");
            el.appendChild(renderDiv);
            ABCJS.renderAbc(renderDiv, source);
          } catch (e) {
            el.textContent = source;
            el.classList.add("notation-error");
            onError("ABC", source);
          }
          el.setAttribute("data-rendered", "true");
        }
      });
    }

    if (typeof vegaEmbed !== 'undefined') {
      container.querySelectorAll(".vegalite-wrapper:not([data-rendered])").forEach(function(el) {
        var sourceEl = el.querySelector(".vegalite-source");
        if (sourceEl) {
          var source = sourceEl.textContent;
          sourceEl.remove();
          try {
            vegaEmbed(el, JSON.parse(source)).catch(function() {
              el.textContent = source;
              el.classList.add("notation-error");
              onError("Vega-Lite", source);
            });
          } catch (e) {
            el.textContent = source;
            el.classList.add("notation-error");
            onError("Vega-Lite", source);
          }
          el.setAttribute("data-rendered", "true");
        }
      });
    }

    attachCopyButtons(container);
  }

  return function renderMarkdown(text) {
    if (text === lastContent) return;
    lastContent = text;
    _render(text);
  };
}

var ICON_TOC_CHEVRON_DOWN = '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6"/></svg>';
var ICON_TOC_CHEVRON_RIGHT = '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>';

// Creates a table-of-contents controller bound to tocEl.
// opts: { maxDepth: number }
// Returns: { update(container, panelEl?), destroy() }
//   update(container, panelEl) — extracts headings from container, rebuilds TOC,
//     sets up IntersectionObserver. panelEl is the optional .hub-panel div; when
//     provided the observer skips active-state updates unless panelEl is active.
//   destroy() — disconnects observer, clears tocEl body. Call when a panel is removed.
function makeToc(tocEl, opts) {
  var maxDepth = (opts && opts.maxDepth) || 6;
  var collapsed = {};
  var observer = null;
  var currentContainer = null;
  var currentPanelEl = null;

  var tocBody = tocEl.querySelector(".toc-body");

  function buildTree(headings) {
    var root = { children: [], level: 0 };
    var stack = [root];
    headings.forEach(function(h) {
      var node = { level: h.level, text: h.text, line: h.line, children: [] };
      while (stack.length > 1 && stack[stack.length - 1].level >= h.level) {
        stack.pop();
      }
      stack[stack.length - 1].children.push(node);
      stack.push(node);
    });
    return root.children;
  }

  function renderTree(nodes) {
    nodes.forEach(function(node) {
      var hasChildren = node.children.length > 0;
      var isCollapsed = !!collapsed[node.line];
      var indent = (node.level - 1) * 12;

      var item = document.createElement("div");
      item.className = "toc-item";
      item.dataset.tocLine = node.line;
      item.style.paddingLeft = indent + "px";

      var toggleBtn = document.createElement("button");
      toggleBtn.className = "toc-toggle";
      if (hasChildren) {
        toggleBtn.innerHTML = isCollapsed ? ICON_TOC_CHEVRON_RIGHT : ICON_TOC_CHEVRON_DOWN;
        toggleBtn.addEventListener("click", function(e) {
          e.stopPropagation();
          collapsed[node.line] = !collapsed[node.line];
          update(currentContainer, currentPanelEl);
        });
      } else {
        toggleBtn.style.visibility = "hidden";
      }

      var labelBtn = document.createElement("button");
      labelBtn.className = "toc-label";
      labelBtn.textContent = node.text;
      labelBtn.title = node.text;
      labelBtn.addEventListener("click", function() {
        if (currentContainer) {
          scrollToSource(currentContainer, { line: node.line });
        }
      });

      item.appendChild(toggleBtn);
      item.appendChild(labelBtn);
      tocBody.appendChild(item);

      if (hasChildren && !isCollapsed) {
        renderTree(node.children);
      }
    });
  }

  function update(container, panelEl) {
    currentContainer = container;
    currentPanelEl = panelEl || null;

    if (observer) {
      observer.disconnect();
      observer = null;
    }

    tocBody.innerHTML = "";

    var selector = [];
    for (var i = 1; i <= maxDepth; i++) {
      selector.push("h" + i);
    }

    var headingEls = container.querySelectorAll(selector.join(","));
    var headings = [];
    headingEls.forEach(function(el) {
      var line = parseInt(el.getAttribute("data-source-line"), 10);
      if (isNaN(line)) return;
      headings.push({
        level: parseInt(el.tagName[1], 10),
        text: el.textContent.trim(),
        line: line,
      });
    });

    if (headings.length === 0) return;

    var tree = buildTree(headings);
    renderTree(tree);

    var activeLines = {};
    observer = new IntersectionObserver(function(entries) {
      if (currentPanelEl && !currentPanelEl.classList.contains("active")) return;
      entries.forEach(function(entry) {
        var line = parseInt(entry.target.getAttribute("data-source-line"), 10);
        activeLines[line] = entry.isIntersecting;
      });
      var activeLine = null;
      headings.forEach(function(h) {
        if (activeLines[h.line] && (activeLine === null || h.line < activeLine)) {
          activeLine = h.line;
        }
      });
      tocBody.querySelectorAll(".toc-item").forEach(function(item) {
        var line = parseInt(item.dataset.tocLine, 10);
        item.classList.toggle("toc-active", line === activeLine);
      });
    }, { threshold: 0, rootMargin: "0px 0px -60% 0px" });

    headingEls.forEach(function(el) { observer.observe(el); });
  }

  function destroy() {
    if (observer) {
      observer.disconnect();
      observer = null;
    }
    tocBody.innerHTML = "";
  }

  return { update: update, destroy: destroy };
}
