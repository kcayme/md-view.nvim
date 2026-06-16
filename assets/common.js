function safeParse(raw) {
  try {
    return JSON.parse(raw);
  } catch (e) {
    console.error("[safeParse] failed:", e);

    return null;
  }
}

var vizPromise = typeof Viz !== "undefined" ? Viz.instance() : null;

var md = window
  .markdownit({
    html: true,
    linkify: true,
    typographer: true,
    highlight: function (str, lang) {
      if (typeof hljs !== "undefined" && lang && hljs.getLanguage(lang)) {
        try {
          return hljs.highlight(str, { language: lang }).value;
        } catch (_) {}
      }
      return "";
    },
  })
  .use(window.markdownitTaskLists);

if (typeof texmath !== "undefined" && typeof katex !== "undefined") {
  md.use(texmath, { engine: katex, delimiters: "dollars" });
}

var notationMap = {
  mermaid: { wrapper: "mermaid-wrapper", tag: "pre", cls: "mermaid" },
};
if (typeof katex !== "undefined") {
  notationMap["math"] = { wrapper: "katex-wrapper", tag: "code", cls: "katex-source", hide: true };
}
if (typeof Viz !== "undefined") {
  notationMap["dot"] = { wrapper: "graphviz-wrapper", tag: "code", cls: "graphviz-source", hide: true };
  notationMap["graphviz"] = { wrapper: "graphviz-wrapper", tag: "code", cls: "graphviz-source", hide: true };
}
if (typeof WaveDrom !== "undefined") {
  notationMap["wavedrom"] = { wrapper: "wavedrom-wrapper", tag: "code", cls: "wavedrom-source", hide: true };
}
if (typeof nomnoml !== "undefined") {
  notationMap["nomnoml"] = { wrapper: "nomnoml-wrapper", tag: "code", cls: "nomnoml-source", hide: true };
}
if (typeof ABCJS !== "undefined") {
  notationMap["abc"] = { wrapper: "abc-wrapper", tag: "code", cls: "abc-source", hide: true };
}
if (typeof vegaEmbed !== "undefined") {
  notationMap["vega-lite"] = { wrapper: "vegalite-wrapper", tag: "code", cls: "vegalite-source", hide: true };
}

var defaultFence =
  md.renderer.rules.fence ||
  function (tokens, idx, options, env, self) {
    return self.renderToken(tokens, idx, options);
  };

md.renderer.rules.fence = function (tokens, idx, options, env, self) {
  var token = tokens[idx];
  var lang = token.info.trim();
  var notation = notationMap[lang];
  if (notation) {
    var line = token.map ? token.map[0] : "";
    var style = notation.hide ? ' style="display:none"' : "";
    return (
      '<div class="' +
      notation.wrapper +
      '" data-source-line="' +
      line +
      '">' +
      "<" +
      notation.tag +
      ' class="' +
      notation.cls +
      '"' +
      style +
      ">" +
      md.utils.escapeHtml(token.content) +
      "</" +
      notation.tag +
      ">" +
      "</div>"
    );
  }
  return defaultFence(tokens, idx, options, env, self);
};

function addSourceLine(origRule) {
  return function (tokens, idx, options, env, self) {
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
  "paragraph_open",
  "heading_open",
  "blockquote_open",
  "bullet_list_open",
  "ordered_list_open",
  "table_open",
  "code_block",
  "hr",
];

blockRules.forEach(function (rule) {
  md.renderer.rules[rule] = addSourceLine(md.renderer.rules[rule]);
});

var LOCAL_SRC_PASS = /^(https?:|data:|blob:|#)/i;
var LOCAL_MEDIA_EXT = /\.(png|jpe?g|gif|svg|webp|avif|bmp|ico|mp4|webm|mov|og[gva]|mp3|wav|flac)$/i;

// fileId: preview id for mux mode (/file?id=X&path=...) or null for direct mode (/file?path=...)
function rewriteLocalSrcs(root, fileId) {
  var prefix = fileId ? "/file?id=" + fileId + "&path=" : "/file?path=";

  root.querySelectorAll("img[src], video[src], audio[src], source[src]").forEach(function (el) {
    var src = el.getAttribute("src");

    if (src && !LOCAL_SRC_PASS.test(src)) {
      el.setAttribute("src", prefix + encodeURIComponent(src));
    }
  });

  root.querySelectorAll("a[href]").forEach(function (el) {
    var href = el.getAttribute("href");

    if (href && !LOCAL_SRC_PASS.test(href) && LOCAL_MEDIA_EXT.test(href)) {
      el.setAttribute("href", prefix + encodeURIComponent(href));
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

  lines.forEach(function (line) {
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

  rows.forEach(function (r) {
    html += "<tr><th>" + esc(r.key) + "</th><td>" + esc(r.value) + "</td></tr>";
  });

  html += "</table></div>";

  return { body: body, html: html };
}

function attachCopyButtons(container) {
  var blocks = container.querySelectorAll("pre:not([data-has-copy])");

  blocks.forEach(function (pre) {
    var iconCopy =
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="14" height="14" x="8" y="8" rx="2" ry="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/></svg>';
    var iconCheck =
      '<svg viewBox="0 0 24 24" fill="none" stroke="#3fb950" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>';
    var btn = document.createElement("button");
    var code = pre.querySelector("code");
    var wrapper = document.createElement("div");

    if (!code) return;

    pre.setAttribute("data-has-copy", "1");

    wrapper.className = "pre-wrap";
    pre.parentNode.insertBefore(wrapper, pre);
    wrapper.appendChild(pre);
    btn.className = "copy-btn";
    btn.innerHTML = iconCopy;
    btn.title = "Copy";

    btn.addEventListener("click", async function () {
      try {
        await navigator.clipboard.writeText(code.textContent);
      } catch (e) {
        console.error("[clipboard] failed:", e);

        return;
      }

      btn.innerHTML = '<span class="copy-label">Copied!</span>' + iconCheck;
      btn.classList.add("copied");

      setTimeout(function () {
        btn.classList.add("fading");

        setTimeout(function () {
          btn.innerHTML = iconCopy;
          btn.classList.remove("copied");
          btn.classList.remove("fading");
        }, 400);
      }, 1600);
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
  fab.innerHTML =
    '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#e45649" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>';

  var fabBadge = document.createElement("span");
  fabBadge.className = "notation-fab-badge";
  fabBadge.textContent = "0";
  fab.appendChild(fabBadge);
  document.body.appendChild(fab);

  popupClose.addEventListener("click", function () {
    popupEl.classList.remove("show");
  });

  fab.addEventListener("click", function () {
    popupEl.classList.toggle("show");
  });

  function notifyError(notation, src) {
    console.error("md-view: " + notation + " render error", src || "");

    errorEntries.push({ notation: notation, source: src || "" });

    if (errorFlushTimer) clearTimeout(errorFlushTimer);

    errorFlushTimer = setTimeout(function () {
      popupBody.textContent = "";

      errorEntries.forEach(function (entry) {
        var item = document.createElement("div");
        item.className = "notation-popup-item";

        var title = document.createElement("strong");

        title.textContent = entry.notation;
        item.appendChild(title);

        if (entry.source) {
          var preview = document.createElement("pre");

          preview.textContent = entry.source.length > 200 ? entry.source.slice(0, 200) + "\u2026" : entry.source;
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

    container.querySelectorAll("[data-source-line]").forEach(function (el) {
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

var ICON_ZOOM_IN =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/><line x1="11" y1="8" x2="11" y2="14"/><line x1="8" y1="11" x2="14" y2="11"/></svg>';
var ICON_ZOOM_OUT =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/><line x1="8" y1="11" x2="14" y2="11"/></svg>';
var ICON_ZOOM_RESET =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/></svg>';
var ICON_DOWNLOAD =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>';
var ICON_EXPAND =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 3 21 3 21 9"/><polyline points="9 21 3 21 3 15"/><line x1="21" y1="3" x2="14" y2="10"/><line x1="3" y1="21" x2="10" y2="14"/></svg>';

function makeMermaidToolBtn(iconMarkup, title) {
  var btn = document.createElement("button");
  btn.className = "mermaid-tool-btn";
  btn.title = title;
  btn.insertAdjacentHTML("afterbegin", iconMarkup);

  return btn;
}

function makeMermaidToolSep() {
  var sep = document.createElement("span");
  sep.className = "mermaid-tool-sep";
  return sep;
}

function downloadSvg(svgEl) {
  var serializer = new XMLSerializer();
  var svgStr = serializer.serializeToString(svgEl);
  var blob = new Blob([svgStr], { type: "image/svg+xml" });
  var url = URL.createObjectURL(blob);
  var a = document.createElement("a");
  a.href = url;
  a.download = "diagram.svg";
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

function openMermaidModal(svgEl) {
  var existing = document.querySelector(".mermaid-modal-overlay");
  if (existing) existing.remove();

  var overlay = document.createElement("div");
  overlay.className = "mermaid-modal-overlay";

  var modal = document.createElement("div");
  modal.className = "mermaid-modal";

  // Header
  var header = document.createElement("div");
  header.className = "mermaid-modal-header";

  var headerLeft = document.createElement("div");
  headerLeft.className = "mermaid-modal-header-left";

  var headerRight = document.createElement("div");
  headerRight.className = "mermaid-modal-header-right";

  // Body
  var body = document.createElement("div");
  body.className = "mermaid-modal-body";

  var clonedSvg = svgEl.cloneNode(true);
  body.appendChild(clonedSvg);

  // Footer
  var footer = document.createElement("div");
  footer.className = "mermaid-modal-footer";
  footer.textContent = "Esc to close · drag to pan · Ctrl+scroll to zoom · double-click to fit";

  modal.appendChild(header);
  modal.appendChild(body);
  modal.appendChild(footer);
  overlay.appendChild(modal);
  document.body.appendChild(overlay);

  // Zoom/pan state — independent of the inline view
  var state = { scale: 1, tx: 0, ty: 0 };
  var dragging = false;
  var lastX = 0;
  var lastY = 0;

  function applyModal() {
    clonedSvg.style.transformOrigin = "0 0";
    clonedSvg.style.transform =
      "translate(" + state.tx + "px, " + state.ty + "px) scale(" + state.scale + ")";
    label.textContent = Math.round(state.scale * 100) + "%";
  }

  function zoomToModal(newScale, anchorX, anchorY) {
    newScale = Math.max(0.2, Math.min(8, newScale));
    var ratio = newScale / state.scale;
    state.tx = anchorX - (anchorX - state.tx) * ratio;
    state.ty = anchorY - (anchorY - state.ty) * ratio;
    state.scale = newScale;
    applyModal();
  }

  function zoomStepModal(delta) {
    var rect = body.getBoundingClientRect();
    var next = Math.round((state.scale + delta) * 20) / 20;
    zoomToModal(next, rect.width / 2, rect.height / 2);
  }

  function fitToScreen() {
    var bodyRect = body.getBoundingClientRect();
    var vb = clonedSvg.viewBox && clonedSvg.viewBox.baseVal;
    var svgW = (vb && vb.width) || clonedSvg.clientWidth || 300;
    var svgH = (vb && vb.height) || clonedSvg.clientHeight || 200;
    var pad = 48;
    var fitScale = Math.min((bodyRect.width - pad) / svgW, (bodyRect.height - pad) / svgH);
    state.scale = fitScale;
    state.tx = (bodyRect.width - svgW * fitScale) / 2;
    state.ty = (bodyRect.height - svgH * fitScale) / 2;
    applyModal();
  }

  // Toolbar buttons
  var btnOut = makeMermaidToolBtn(ICON_ZOOM_OUT, "Zoom out");
  btnOut.addEventListener("click", function (e) { e.stopPropagation(); zoomStepModal(-0.05); });

  var label = document.createElement("span");
  label.className = "mermaid-tool-label";
  label.textContent = "100%";

  var btnIn = makeMermaidToolBtn(ICON_ZOOM_IN, "Zoom in");
  btnIn.addEventListener("click", function (e) { e.stopPropagation(); zoomStepModal(0.05); });

  var btnReset = makeMermaidToolBtn(ICON_ZOOM_RESET, "Fit to screen");
  btnReset.addEventListener("click", function (e) { e.stopPropagation(); fitToScreen(); });

  headerLeft.appendChild(btnOut);
  headerLeft.appendChild(label);
  headerLeft.appendChild(btnIn);
  headerLeft.appendChild(btnReset);

  var btnDownload = makeMermaidToolBtn(ICON_DOWNLOAD, "Download SVG");
  btnDownload.addEventListener("click", function (e) { e.stopPropagation(); downloadSvg(clonedSvg); });

  var btnClose = document.createElement("button");
  btnClose.className = "mermaid-modal-close";
  btnClose.title = "Close";
  btnClose.textContent = "×";

  headerRight.appendChild(btnDownload);
  headerRight.appendChild(btnClose);

  header.appendChild(headerLeft);
  header.appendChild(headerRight);

  // Open at 100% zoom, centered
  function initZoom() {
    var bodyRect = body.getBoundingClientRect();
    var vb = clonedSvg.viewBox && clonedSvg.viewBox.baseVal;
    var svgW = (vb && vb.width) || clonedSvg.clientWidth || 300;
    var svgH = (vb && vb.height) || clonedSvg.clientHeight || 200;
    state.scale = 1;
    state.tx = Math.max(0, (bodyRect.width - svgW) / 2);
    state.ty = Math.max(0, (bodyRect.height - svgH) / 2);
    applyModal();
  }
  requestAnimationFrame(initZoom);

  // Wheel zoom (Ctrl/Meta required)
  body.addEventListener("wheel", function (e) {
    if (!e.ctrlKey && !e.metaKey) return;
    e.preventDefault();
    var rect = body.getBoundingClientRect();
    var mx = e.clientX - rect.left;
    var my = e.clientY - rect.top;
    var factor = e.deltaY < 0 ? 1.15 : 1 / 1.15;
    zoomToModal(state.scale * factor, mx, my);
  }, { passive: false });

  // Drag pan
  body.addEventListener("pointerdown", function (e) {
    if (e.button !== 0) return;
    if (e.target.closest(".mermaid-modal-header")) return;
    dragging = true;
    lastX = e.clientX;
    lastY = e.clientY;
    body.setPointerCapture(e.pointerId);
    body.classList.add("mermaid-dragging");
    e.preventDefault();
  });

  body.addEventListener("pointermove", function (e) {
    if (!dragging) return;
    state.tx += e.clientX - lastX;
    state.ty += e.clientY - lastY;
    lastX = e.clientX;
    lastY = e.clientY;
    applyModal();
  });

  function endDragModal() {
    if (!dragging) return;
    dragging = false;
    body.classList.remove("mermaid-dragging");
  }

  body.addEventListener("pointerup", endDragModal);
  body.addEventListener("pointercancel", endDragModal);

  // Double-click to re-fit
  body.addEventListener("dblclick", function (e) {
    if (e.target.closest(".mermaid-modal-header")) return;
    fitToScreen();
  });

  // Close helpers
  function closeModal() {
    overlay.remove();
    document.removeEventListener("keydown", escHandler);
  }

  function escHandler(e) {
    if (e.key === "Escape") closeModal();
  }

  btnClose.addEventListener("click", closeModal);
  document.addEventListener("keydown", escHandler);

  // Clicking the backdrop (outside the modal box) closes
  overlay.addEventListener("click", function (e) {
    if (!modal.contains(e.target)) closeModal();
  });
}

// Adds wheel-zoom + drag-pan + double-click-reset and a VS Code-style floating
// toolbar (zoom-out, %, zoom-in, reset) to each rendered mermaid SVG.
// Wheel zoom requires Ctrl/Meta so page scroll still works over diagrams.
function enhanceMermaidZoom(container) {
  container
    .querySelectorAll(".mermaid-wrapper:not([data-zoom-enhanced]):not(.notation-error)")
    .forEach(function (wrapper) {
      var svg = wrapper.querySelector("svg");
      if (!svg) return;

      wrapper.setAttribute("data-zoom-enhanced", "1");
      wrapper.classList.add("mermaid-zoom");

      var state = { scale: 1, tx: 0, ty: 0 };
      var dragging = false;
      var lastX = 0;
      var lastY = 0;

      var toolbar = document.createElement("div");
      toolbar.className = "mermaid-toolbar";

      var btnOut = makeMermaidToolBtn(ICON_ZOOM_OUT, "Zoom out");

      var label = document.createElement("span");
      label.className = "mermaid-tool-label";
      label.textContent = "100%";

      var btnIn = makeMermaidToolBtn(ICON_ZOOM_IN, "Zoom in");
      var btnReset = makeMermaidToolBtn(ICON_ZOOM_RESET, "Reset");

      toolbar.appendChild(btnOut);
      toolbar.appendChild(label);
      toolbar.appendChild(btnIn);
      toolbar.appendChild(btnReset);

      toolbar.appendChild(makeMermaidToolSep());

      var btnDownload = makeMermaidToolBtn(ICON_DOWNLOAD, "Download SVG");
      btnDownload.addEventListener("click", function (e) {
        e.stopPropagation();
        downloadSvg(svg);
      });
      toolbar.appendChild(btnDownload);

      var btnExpand = makeMermaidToolBtn(ICON_EXPAND, "Expand");
      btnExpand.addEventListener("click", function (e) {
        e.stopPropagation();
        openMermaidModal(svg);
      });
      toolbar.appendChild(btnExpand);

      wrapper.appendChild(toolbar);

      function apply() {
        svg.style.transformOrigin = "0 0";
        svg.style.transform = "translate(" + state.tx + "px, " + state.ty + "px) scale(" + state.scale + ")";
        label.textContent = Math.round(state.scale * 100) + "%";
      }

      function zoomTo(newScale, anchorX, anchorY) {
        newScale = Math.max(0.2, Math.min(8, newScale));
        var ratio = newScale / state.scale;

        state.tx = anchorX - (anchorX - state.tx) * ratio;
        state.ty = anchorY - (anchorY - state.ty) * ratio;
        state.scale = newScale;
        apply();
      }

      function zoomStepCentered(delta) {
        var rect = wrapper.getBoundingClientRect();
        var next = Math.round((state.scale + delta) * 20) / 20;

        zoomTo(next, rect.width / 2, rect.height / 2);
      }

      function reset() {
        state.scale = 1;
        state.tx = 0;
        state.ty = 0;

        apply();
      }

      btnIn.addEventListener("click", function (e) {
        e.stopPropagation();
        zoomStepCentered(0.05);
      });

      btnOut.addEventListener("click", function (e) {
        e.stopPropagation();
        zoomStepCentered(-0.05);
      });

      btnReset.addEventListener("click", function (e) {
        e.stopPropagation();
        reset();
      });

      wrapper.addEventListener(
        "wheel",
        function (e) {
          if (!e.ctrlKey && !e.metaKey) return;

          e.preventDefault();

          var rect = wrapper.getBoundingClientRect();
          var mx = e.clientX - rect.left;
          var my = e.clientY - rect.top;
          var factor = e.deltaY < 0 ? 1.15 : 1 / 1.15;

          zoomTo(state.scale * factor, mx, my);
        },
        { passive: false }
      );

      wrapper.addEventListener("pointerdown", function (e) {
        if (e.button !== 0) return;
        if (e.target.closest(".mermaid-toolbar")) return;

        dragging = true;
        lastX = e.clientX;
        lastY = e.clientY;
        wrapper.setPointerCapture(e.pointerId);
        wrapper.classList.add("mermaid-dragging");
        e.preventDefault();
      });

      wrapper.addEventListener("pointermove", function (e) {
        if (!dragging) return;

        state.tx += e.clientX - lastX;
        state.ty += e.clientY - lastY;
        lastX = e.clientX;
        lastY = e.clientY;
        apply();
      });

      function endDrag() {
        if (!dragging) return;

        dragging = false;
        wrapper.classList.remove("mermaid-dragging");
      }

      wrapper.addEventListener("pointerup", endDrag);
      wrapper.addEventListener("pointercancel", endDrag);
      wrapper.addEventListener("dblclick", function (e) {
        if (e.target.closest(".mermaid-toolbar")) return;
        reset();
      });
    });
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

    mermaidNodes.forEach(function (el) {
      if (el.getAttribute("data-processed")) {
        el.removeAttribute("data-processed");
      }

      var wrapper = el.closest(".mermaid-wrapper");
      var line = wrapper ? wrapper.getAttribute("data-source-line") : null;

      if (line) mermaidSources[line] = el.textContent;
    });

    function fixMermaidErrors() {
      var hadError = false;

      container.querySelectorAll(".mermaid-wrapper").forEach(function (wrapper) {
        if (wrapper.querySelector(".error-icon")) {
          var line = wrapper.getAttribute("data-source-line");

          wrapper.textContent = mermaidSources[line] || "";
          wrapper.classList.add("notation-error");
          hadError = true;
        }
      });

      if (hadError) {
        container.querySelectorAll(".mermaid-wrapper.notation-error").forEach(function (wrapper) {
          var line = wrapper.getAttribute("data-source-line");

          onError("Mermaid", mermaidSources[line] || "");
        });
      }
    }

    if (typeof mermaid !== "undefined") {
      (async function () {
        try {
          await mermaid.run({ nodes: mermaidNodes });
          fixMermaidErrors();
          enhanceMermaidZoom(container);
        } catch (e) {
          fixMermaidErrors();
        }
      })();
    }

    if (typeof katex !== "undefined") {
      container.querySelectorAll(".katex-wrapper").forEach(function (el) {
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
        (async function () {
          var viz;

          try {
            viz = await vizPromise;
          } catch (e) {
            console.error("[graphviz] viz instance failed:", e);

            return;
          }

          graphvizEls.forEach(function (el) {
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
        })();
      }
    }

    if (typeof WaveDrom !== "undefined") {
      container.querySelectorAll(".wavedrom-wrapper:not([data-rendered])").forEach(function (el, idx) {
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

    if (typeof nomnoml !== "undefined") {
      container.querySelectorAll(".nomnoml-wrapper:not([data-rendered])").forEach(function (el) {
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

    if (typeof ABCJS !== "undefined") {
      container.querySelectorAll(".abc-wrapper:not([data-rendered])").forEach(function (el) {
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

    if (typeof vegaEmbed !== "undefined") {
      container.querySelectorAll(".vegalite-wrapper:not([data-rendered])").forEach(async function (el) {
        var sourceEl = el.querySelector(".vegalite-source");

        if (!sourceEl) return;

        var source = sourceEl.textContent;
        sourceEl.remove();
        el.setAttribute("data-rendered", "true");

        var spec;

        try {
          spec = JSON.parse(source);
        } catch (e) {
          el.textContent = source;
          el.classList.add("notation-error");
          onError("Vega-Lite", source);

          return;
        }

        try {
          await vegaEmbed(el, spec);
        } catch (e) {
          el.textContent = source;
          el.classList.add("notation-error");
          onError("Vega-Lite", source);
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

var ICON_TOC_CHEVRON_DOWN =
  '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6"/></svg>';
var ICON_TOC_CHEVRON_RIGHT =
  '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>';

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

    headings.forEach(function (h) {
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
    nodes.forEach(function (node) {
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

        toggleBtn.addEventListener("click", function (e) {
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
      labelBtn.addEventListener("click", function () {
        if (!currentContainer) return;

        var target = null;
        var bestDist = Infinity;

        currentContainer.querySelectorAll("[data-source-line]").forEach(function (el) {
          var sl = parseInt(el.getAttribute("data-source-line"), 10);
          var dist = Math.abs(sl - node.line);

          if (dist < bestDist) {
            bestDist = dist;
            target = el;
          }
        });

        if (target) {
          target.scrollIntoView({ behavior: "smooth", block: "start" });
        }

        tocBody.querySelectorAll(".toc-item").forEach(function (item) {
          item.classList.toggle("toc-active", parseInt(item.dataset.tocLine, 10) === node.line);
        });
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

    headingEls.forEach(function (el) {
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

    observer = new IntersectionObserver(
      function (entries) {
        if (currentPanelEl && !currentPanelEl.classList.contains("active")) return;

        entries.forEach(function (entry) {
          var line = parseInt(entry.target.getAttribute("data-source-line"), 10);

          activeLines[line] = entry.isIntersecting;
        });

        var activeLine = null;

        headings.forEach(function (h) {
          if (activeLines[h.line] && (activeLine === null || h.line < activeLine)) {
            activeLine = h.line;
          }
        });

        tocBody.querySelectorAll(".toc-item").forEach(function (item) {
          var line = parseInt(item.dataset.tocLine, 10);

          item.classList.toggle("toc-active", line === activeLine);
        });
      },
      { threshold: 0, rootMargin: "0px 0px -60% 0px" }
    );

    headingEls.forEach(function (el) {
      observer.observe(el);
    });
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
