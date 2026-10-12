-- Terminal preview: headless Chromium screenshots of the preview page, drawn via kitty graphics placeholders.
local M = {}

local uv = vim.uv or vim.loop

-- Diacritic N encodes row/column N-1 of a placeholder cell (kitty gen/rowcolumn-diacritics.txt).
local DIACRITIC_CODEPOINTS = {
  0x0305,
  0x030D,
  0x030E,
  0x0310,
  0x0312,
  0x033D,
  0x033E,
  0x033F,
  0x0346,
  0x034A,
  0x034B,
  0x034C,
  0x0350,
  0x0351,
  0x0352,
  0x0357,
  0x035B,
  0x0363,
  0x0364,
  0x0365,
  0x0366,
  0x0367,
  0x0368,
  0x0369,
  0x036A,
  0x036B,
  0x036C,
  0x036D,
  0x036E,
  0x036F,
  0x0483,
  0x0484,
  0x0485,
  0x0486,
  0x0487,
  0x0592,
  0x0593,
  0x0594,
  0x0595,
  0x0597,
  0x0598,
  0x0599,
  0x059C,
  0x059D,
  0x059E,
  0x059F,
  0x05A0,
  0x05A1,
  0x05A8,
  0x05A9,
  0x05AB,
  0x05AC,
  0x05AF,
  0x05C4,
  0x0610,
  0x0611,
  0x0612,
  0x0613,
  0x0614,
  0x0615,
  0x0616,
  0x0617,
  0x0657,
  0x0658,
  0x0659,
  0x065A,
  0x065B,
  0x065D,
  0x065E,
  0x06D6,
  0x06D7,
  0x06D8,
  0x06D9,
  0x06DA,
  0x06DB,
  0x06DC,
  0x06DF,
  0x06E0,
  0x06E1,
  0x06E2,
  0x06E4,
  0x06E7,
  0x06E8,
  0x06EB,
  0x06EC,
  0x0730,
  0x0732,
  0x0733,
  0x0735,
  0x0736,
  0x073A,
  0x073D,
  0x073F,
  0x0740,
  0x0741,
  0x0743,
  0x0745,
  0x0747,
  0x0749,
  0x074A,
  0x07EB,
  0x07EC,
  0x07ED,
  0x07EE,
  0x07EF,
  0x07F0,
  0x07F1,
  0x07F3,
  0x0816,
  0x0817,
  0x0818,
  0x0819,
  0x081B,
  0x081C,
  0x081D,
  0x081E,
  0x081F,
  0x0820,
  0x0821,
  0x0822,
  0x0823,
  0x0825,
  0x0826,
  0x0827,
  0x0829,
  0x082A,
  0x082B,
  0x082C,
  0x082D,
  0x0951,
  0x0953,
  0x0954,
  0x0F82,
  0x0F83,
  0x0F86,
  0x0F87,
  0x135D,
  0x135E,
  0x135F,
  0x17DD,
  0x193A,
  0x1A17,
  0x1A75,
  0x1A76,
  0x1A77,
  0x1A78,
  0x1A79,
  0x1A7A,
  0x1A7B,
  0x1A7C,
  0x1B6B,
  0x1B6D,
  0x1B6E,
  0x1B6F,
  0x1B70,
  0x1B71,
  0x1B72,
  0x1B73,
  0x1CD0,
  0x1CD1,
  0x1CD2,
  0x1CDA,
  0x1CDB,
  0x1CE0,
  0x1DC0,
  0x1DC1,
  0x1DC3,
  0x1DC4,
  0x1DC5,
  0x1DC6,
  0x1DC7,
  0x1DC8,
  0x1DC9,
  0x1DCB,
  0x1DCC,
  0x1DD1,
  0x1DD2,
  0x1DD3,
  0x1DD4,
  0x1DD5,
  0x1DD6,
  0x1DD7,
  0x1DD8,
  0x1DD9,
  0x1DDA,
  0x1DDB,
  0x1DDC,
  0x1DDD,
  0x1DDE,
  0x1DDF,
  0x1DE0,
  0x1DE1,
  0x1DE2,
  0x1DE3,
  0x1DE4,
  0x1DE5,
  0x1DE6,
  0x1DFE,
  0x20D0,
  0x20D1,
  0x20D4,
  0x20D5,
  0x20D6,
  0x20D7,
  0x20DB,
  0x20DC,
  0x20E1,
  0x20E7,
  0x20E9,
  0x20F0,
  0x2CEF,
  0x2CF0,
  0x2CF1,
  0x2DE0,
  0x2DE1,
  0x2DE2,
  0x2DE3,
  0x2DE4,
  0x2DE5,
  0x2DE6,
  0x2DE7,
  0x2DE8,
  0x2DE9,
  0x2DEA,
  0x2DEB,
  0x2DEC,
  0x2DED,
  0x2DEE,
  0x2DEF,
  0x2DF0,
  0x2DF1,
  0x2DF2,
  0x2DF3,
  0x2DF4,
  0x2DF5,
  0x2DF6,
  0x2DF7,
  0x2DF8,
  0x2DF9,
  0x2DFA,
  0x2DFB,
  0x2DFC,
  0x2DFD,
  0x2DFE,
  0x2DFF,
  0xA66F,
  0xA67C,
  0xA67D,
  0xA6F0,
  0xA6F1,
  0xA8E0,
  0xA8E1,
  0xA8E2,
  0xA8E3,
  0xA8E4,
  0xA8E5,
  0xA8E6,
  0xA8E7,
  0xA8E8,
  0xA8E9,
  0xA8EA,
  0xA8EB,
  0xA8EC,
  0xA8ED,
  0xA8EE,
  0xA8EF,
  0xA8F0,
  0xA8F1,
  0xAAB0,
  0xAAB2,
  0xAAB3,
  0xAAB7,
  0xAAB8,
  0xAABE,
  0xAABF,
  0xAAC1,
  0xFE20,
  0xFE21,
  0xFE22,
  0xFE23,
  0xFE24,
  0xFE25,
  0xFE26,
  0x10A0F,
  0x10A38,
  0x1D185,
  0x1D186,
  0x1D187,
  0x1D188,
  0x1D189,
  0x1D1AA,
  0x1D1AB,
  0x1D1AC,
  0x1D1AD,
  0x1D242,
  0x1D243,
  0x1D244,
}
local PLACEHOLDER_CODEPOINT = 0x10EEEE
local ROWS_PER_TILE = 200 -- must stay below #DIACRITIC_CODEPOINTS
local MAX_TILES_PER_VIEWER = 64
local IMAGE_ID_BASE = 0xA0D000
local DEFAULT_CELL = { width = 10, height = 20 }
local RESIZE_DEBOUNCE_MS = 200
-- Render-progress polling (window.__mdviewRender from common.js) used to capture as soon as a render settles.
local RENDER_POLL_MS = 50
local RENDER_TIMEOUT_MS = 3000
local RENDER_PROGRESS_JS =
  "window.__mdviewRender ? [window.__mdviewRender.done, window.__mdviewRender.pending] : [0, 0]"
local KITTY_TERMINALS = { "kitty", "ghostty", "wezterm" }
local BROWSER_CANDIDATES = {
  "chrome-headless-shell",
  "chromium",
  "chromium-browser",
  "google-chrome-stable",
  "google-chrome",
  "brave-browser",
}
-- Hides screenshot-unfriendly UI, then reports page height, source-line offsets and notation errors.
local METRICS_JS = [[
(() => {
  if (!document.getElementById("md-view-terminal-style")) {
    const style = document.createElement("style");
    style.id = "md-view-terminal-style";
    // only UI no option can turn off; notation errors are reported via vim.notify instead
    style.textContent = ".copy-btn, .vega-embed details, .mermaid-modal-overlay, "
      + ".notation-error, .notation-popup, .notation-fab "
      + "{ display: none !important; }";
    document.head.appendChild(style);
  }

  const lines = [];

  document.querySelectorAll("[data-source-line]").forEach((el) => {
    lines.push([parseInt(el.getAttribute("data-source-line"), 10), el.getBoundingClientRect().top + window.scrollY]);
  });

  const errors = (window.__mdviewRender && window.__mdviewRender.errors) || [];

  return { height: document.documentElement.scrollHeight, lines: lines, errors: errors };
})()
]]

local placeholder = vim.fn.nr2char(PLACEHOLDER_CODEPOINT)
local diacritics = vim.tbl_map(vim.fn.nr2char, DIACRITIC_CODEPOINTS)
local namespace = vim.api.nvim_create_namespace("md_view_terminal")

---@type table<integer, table> source bufnr -> session
local sessions = {}
-- One headless browser shared by every terminal preview (one tab each); killed with the last one.
local shared_browser = nil
-- The viewer (split or tmux pane) is shared too: previewing another buffer moves it to that buffer.
---@type { surface: table, target: string, owner: integer }|nil
local viewer = nil
---@type table<integer, integer[]> viewer bufnr -> kitty image ids on screen
local viewer_images = {}

local function term_write(data)
  if vim.env.TMUX then
    data = "\27Ptmux;" .. (data:gsub("\27", "\27\27")) .. "\27\\"
  end

  if vim.api.nvim_ui_send then
    vim.api.nvim_ui_send(data)
  else
    vim.fn.chansend(vim.v.stderr, data)
  end
end

-- Transmit a base64 PNG and create a virtual (placeholder) placement of cols x rows cells.
local function kitty_transmit(image_id, png_base64, cols, rows)
  local chunk_size = 4096
  local offset = 1

  while offset <= #png_base64 do
    local chunk = png_base64:sub(offset, offset + chunk_size - 1)
    local keys

    offset = offset + chunk_size

    local more = offset <= #png_base64 and 1 or 0

    if offset - chunk_size == 1 then
      keys = string.format("a=T,U=1,f=100,t=d,i=%d,c=%d,r=%d,q=2,m=%d", image_id, cols, rows, more)
    else
      keys = "q=2,m=" .. more
    end

    term_write("\27_G" .. keys .. ";" .. chunk .. "\27\\")
  end
end

local function kitty_delete(image_id)
  term_write(string.format("\27_Ga=d,d=I,i=%d,q=2\27\\", image_id))
end

-- Cell size in pixels from the parent TUI's tty, falling back to tmux, then a guess.
local function cell_size()
  local ok, size = pcall(function()
    local ffi = require("ffi")

    pcall(
      ffi.cdef,
      [[
      typedef struct { unsigned short row, col, xpixel, ypixel; } md_view_winsize;
      int open(const char *path, int flags);
      int close(int fd);
      int ioctl(int fd, unsigned long request, ...);
    ]]
    )

    local winsize = ffi.new("md_view_winsize")
    local fd = ffi.C.open("/proc/" .. uv.os_getppid() .. "/fd/0", 0)

    if fd < 0 then
      return nil
    end

    local rc = ffi.C.ioctl(fd, 0x5413, winsize) -- TIOCGWINSZ (Linux)

    ffi.C.close(fd)

    if rc ~= 0 or winsize.xpixel == 0 or winsize.col == 0 then
      return nil
    end

    return { width = math.floor(winsize.xpixel / winsize.col), height = math.floor(winsize.ypixel / winsize.row) }
  end)

  if ok and size then
    return size
  end

  if vim.env.TMUX then
    local out = vim.fn.system({ "tmux", "display", "-p", "#{client_cell_width} #{client_cell_height}" })
    local width, height = out:match("(%d+) (%d+)")

    if width and tonumber(width) > 0 then
      return { width = tonumber(width), height = tonumber(height) }
    end
  end

  return DEFAULT_CELL
end

local function find_browser(configured)
  if configured then
    return vim.fn.executable(configured) == 1 and configured or nil
  end

  for _, name in ipairs(BROWSER_CANDIDATES) do
    if vim.fn.executable(name) == 1 then
      return name
    end
  end

  -- Playwright's cached headless shell (`npx playwright install chromium-headless-shell`)
  local cached = vim.fn.glob("~/.cache/ms-playwright/chromium_headless_shell-*/*/chrome-headless-shell", false, true)

  return cached[#cached]
end

-- Kitty graphics query replies never reach Lua through tmux, so identify the outer terminal by name.
local function supports_kitty_graphics()
  local names = { vim.env.TERM or "", vim.env.TERM_PROGRAM or "" }
  local joined

  if vim.env.KITTY_WINDOW_ID or vim.env.GHOSTTY_RESOURCES_DIR or vim.env.WEZTERM_PANE then
    return true
  end

  if vim.env.TMUX then
    table.insert(names, vim.fn.system({ "tmux", "display", "-p", "#{client_termname}" }))
  end

  joined = table.concat(names, " "):lower()

  for _, name in ipairs(KITTY_TERMINALS) do
    if joined:find(name, 1, true) then
      return true
    end
  end

  return false
end

-- Preflight: a missing browser or bad target stops the preview; the best-guess checks only warn.
---@return string|nil binary, string|nil target
local function check_requirements(options, target)
  local binary = find_browser(options.preview.terminal.browser)
  local passthrough

  if target ~= "split" and target ~= "tmux" then
    vim.notify(
      "[md-view] invalid terminal target '" .. tostring(target) .. "' (use split or tmux)",
      vim.log.levels.ERROR
    )

    return nil
  end

  if not binary then
    vim.notify(
      "[md-view] no headless Chromium-based browser found; install chromium or set preview.terminal.browser",
      vim.log.levels.ERROR
    )

    return nil
  end

  if target == "tmux" and not vim.env.TMUX then
    vim.notify("[md-view] not in a tmux session; opening the preview in a Neovim split instead", vim.log.levels.WARN)
    target = "split"
  end

  if not supports_kitty_graphics() then
    vim.notify(
      "[md-view] terminal not recognised as supporting the kitty graphics protocol (kitty, Ghostty, WezTerm);"
        .. " the preview may stay blank",
      vim.log.levels.WARN
    )
  end

  if vim.env.TMUX then
    passthrough = vim.trim(vim.fn.system({ "tmux", "show", "-gv", "allow-passthrough" }))

    if passthrough ~= "on" and passthrough ~= "all" then
      vim.notify(
        "[md-view] tmux allow-passthrough is off; images need `set -g allow-passthrough on` in tmux.conf",
        vim.log.levels.WARN
      )
    end
  end

  return binary, target
end

-- DevTools protocol over --remote-debugging-pipe: NUL-delimited JSON on fds 3 (in) and 4 (out).
local function cdp_spawn(binary, on_exit)
  local client = { next_id = 0, pending = {}, listeners = {}, chunks = {} }
  local devnull = uv.fs_open("/dev/null", "r+", 438)
  local profile_dir = vim.fn.tempname()

  client.to_browser = uv.new_pipe(false)
  client.from_browser = uv.new_pipe(false)
  client.handle = uv.spawn(binary, {
    args = {
      "--headless",
      "--remote-debugging-pipe",
      "--user-data-dir=" .. profile_dir,
      "--no-first-run",
      "--disable-gpu",
      "--hide-scrollbars",
      "--mute-audio",
      "about:blank",
    },
    stdio = { devnull, devnull, devnull, client.to_browser, client.from_browser },
  }, function()
    client.to_browser:close()
    client.from_browser:close()
    vim.schedule(function()
      vim.fn.delete(profile_dir, "rf")
      on_exit()
    end)
  end)

  uv.fs_close(devnull)

  if not client.handle then
    client.to_browser:close()
    client.from_browser:close()

    return nil
  end

  client.from_browser:read_start(function(err, chunk)
    if err or not chunk then
      return
    end

    -- ponytail: re-joins pending chunks per NUL; fine for a few MB of screenshots
    table.insert(client.chunks, chunk)

    if not chunk:find("\0", 1, true) then
      return
    end

    local data = table.concat(client.chunks)
    local messages = vim.split(data, "\0", { plain = true })

    client.chunks = { table.remove(messages) }

    vim.schedule(function()
      for _, raw in ipairs(messages) do
        local ok, message = pcall(vim.json.decode, raw)

        if ok and message.id and client.pending[message.id] then
          local callback = client.pending[message.id]

          client.pending[message.id] = nil
          callback(message.result, message.error)
        elseif ok and message.method then
          -- events are routed to the tab (CDP session) that emitted them
          local listeners = message.sessionId and client.listeners[message.sessionId]

          if listeners and listeners[message.method] then
            listeners[message.method](message.params)
          end
        end
      end
    end)
  end)

  return client
end

local function cdp_send(client, method, params, session_id, callback)
  if client.to_browser:is_closing() then
    return
  end

  client.next_id = client.next_id + 1
  client.pending[client.next_id] = callback or function() end
  client.to_browser:write(vim.json.encode({
    id = client.next_id,
    method = method,
    params = params or vim.empty_dict(),
    sessionId = session_id,
  }) .. "\0")
end

local function cdp_kill(client)
  if client and client.handle and not client.handle:is_closing() then
    client.handle:kill("sigterm")
  end
end

local function setup_viewer_window(win, buf)
  local win_opts = {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    statuscolumn = "",
    colorcolumn = "",
    wrap = false,
    list = false,
    spell = false,
    cursorline = false,
  }

  for name, value in pairs(win_opts) do
    vim.api.nvim_set_option_value(name, value, { win = win })
  end

  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("filetype", "md-view-terminal", { buf = buf })
end

-- ── Viewer side: runs in whichever Neovim draws the image (this one or the tmux pane's) ──

---@param buf integer
M.clear = function(buf)
  for _, image_id in ipairs(viewer_images[buf] or {}) do
    kitty_delete(image_id)
  end

  viewer_images[buf] = nil
end

---@param buf integer
---@param tiles { data: string, cols: integer, rows: integer }[]
M.show = function(buf, tiles)
  local lines = {}
  local groups = {}
  local image_ids = {}
  local win = vim.fn.bufwinid(buf)
  local view = win ~= -1 and vim.api.nvim_win_call(win, vim.fn.winsaveview) or nil

  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  M.clear(buf)

  for tile_index, tile in ipairs(tiles) do
    local image_id = IMAGE_ID_BASE + (buf % 1024) * MAX_TILES_PER_VIEWER + tile_index
    local group = "MdViewTerminalImage" .. image_id

    kitty_transmit(image_id, tile.data, tile.cols, tile.rows)
    vim.api.nvim_set_hl(0, group, { fg = string.format("#%06x", image_id) })
    table.insert(image_ids, image_id)

    for row = 1, tile.rows do
      local cells = {}

      for col = 1, tile.cols do
        cells[col] = placeholder .. diacritics[row] .. diacritics[col]
      end

      table.insert(lines, table.concat(cells))
      table.insert(groups, group)
    end
  end

  viewer_images[buf] = image_ids

  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)

  for index, group in ipairs(groups) do
    vim.api.nvim_buf_set_extmark(buf, namespace, index - 1, 0, { end_col = #lines[index], hl_group = group })
  end

  if view then
    vim.api.nvim_win_call(win, function()
      vim.fn.winrestview(view)
    end)
  end
end

---@param buf integer
---@param topline integer
M.scroll = function(buf, topline)
  local win = vim.fn.bufwinid(buf)

  if win == -1 then
    return
  end

  vim.api.nvim_win_call(win, function()
    local line = math.min(topline, vim.api.nvim_buf_line_count(buf))

    -- move the cursor too, or Neovim scrolls back to keep it visible
    vim.fn.winrestview({ topline = line, lnum = line })
  end)
end

-- Entry point for the tmux pane's Neovim: turn the current window into a viewer.
---@return integer viewer bufnr
M.viewer = function()
  local buf = vim.api.nvim_get_current_buf()

  vim.o.termguicolors = true
  vim.o.laststatus = 0
  vim.o.ruler = false
  vim.o.showmode = false
  vim.o.showcmd = false
  setup_viewer_window(vim.api.nvim_get_current_win(), buf)
  vim.keymap.set("n", "q", "<cmd>qa!<cr>", { buffer = buf })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      M.clear(buf)
    end,
  })

  return buf
end

-- ── Surfaces: where the viewer lives ─────────────────────────────────────

local function split_surface(on_close)
  local source_win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  local win

  vim.cmd("botright vsplit")
  win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  setup_viewer_window(win, buf)
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf })
  vim.api.nvim_set_current_win(source_win)
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      M.clear(buf)
      vim.schedule(on_close)
    end,
  })

  return {
    width = function()
      return vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_width(win) or 80
    end,
    height = function()
      return vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_height(win) or 24
    end,
    call = function(name, ...)
      M[name](buf, ...)
    end,
    close = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  }
end

local function tmux_surface(on_ready, on_close)
  local socket = vim.fn.tempname() .. ".sock"
  local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
  local viewer_cmd = string.format(
    "nvim --clean --listen %s --cmd %s",
    vim.fn.shellescape(socket),
    vim.fn.shellescape("set rtp^=" .. plugin_root)
  )
  -- -t: split next to this Neovim's pane, not whichever pane the client has active
  local pane_id = vim.trim(
    vim.fn.system({ "tmux", "split-window", "-h", "-d", "-t", vim.env.TMUX_PANE, "-P", "-F", "#{pane_id}", viewer_cmd })
  )
  local timer = uv.new_timer()
  local attempts = 0

  if vim.v.shell_error ~= 0 or not pane_id:match("^%%%d+$") then
    timer:close()
    vim.notify("[md-view] tmux split-window failed: " .. pane_id, vim.log.levels.ERROR)

    return
  end

  timer:start(
    50,
    50,
    vim.schedule_wrap(function()
      local ok, channel = pcall(vim.fn.sockconnect, "pipe", socket, { rpc = true })
      local buf, width, height

      attempts = attempts + 1

      if not (ok and channel > 0) then
        if attempts > 100 then
          timer:stop()
          timer:close()
          vim.notify("[md-view] tmux viewer did not start", vim.log.levels.ERROR)
        end

        return
      end

      timer:stop()
      timer:close()

      buf = vim.rpcrequest(channel, "nvim_exec_lua", "return require('md-view.terminal').viewer()", {})
      width = vim.rpcrequest(channel, "nvim_win_get_width", 0)
      height = vim.rpcrequest(channel, "nvim_win_get_height", 0)

      on_ready({
        -- ponytail: pane size read once; re-query on tmux resize if it matters
        width = function()
          return width
        end,
        height = function()
          return height
        end,
        call = function(name, ...)
          local sent = pcall(
            vim.rpcnotify,
            channel,
            "nvim_exec_lua",
            "require('md-view.terminal')." .. name .. "(...)",
            { buf, ... }
          )

          if not sent then
            on_close()
          end
        end,
        close = function()
          pcall(
            vim.rpcnotify,
            channel,
            "nvim_exec_lua",
            "require('md-view.terminal').clear(...) vim.cmd('qa!')",
            { buf }
          )
          pcall(vim.fn.chanclose, channel)
          vim.fn.system({ "tmux", "kill-pane", "-t", pane_id })
        end,
      })
    end)
  )
end

-- ── Source side: capture loop, scroll sync, lifecycle ───────────────────

local function sync_scroll(session)
  local win = vim.fn.bufwinid(session.bufnr)
  local cursor_line, best_y, row

  if win == -1 or not session.line_map then
    return
  end

  cursor_line = vim.api.nvim_win_get_cursor(win)[1] - 1
  best_y = 0

  for _, entry in ipairs(session.line_map) do
    if entry[1] <= cursor_line then
      best_y = math.max(best_y, entry[2])
    end
  end

  row = math.floor(best_y * session.scale / session.cell.height)
  session.surface.call("scroll", math.max(1, row + 1 - math.floor(session.surface.height() / 3)))
end

-- Reports notation errors via vim.notify, once per distinct set so edits don't repeat the warning.
local function report_render_errors(session, errors)
  local lines = {}
  local signature

  for _, entry in ipairs(errors or {}) do
    local first_line = vim.trim((entry.source or ""):match("^[^\n]*") or "")

    if #first_line > 60 then
      first_line = first_line:sub(1, 60) .. "…"
    end

    table.insert(lines, "- " .. entry.notation .. (first_line ~= "" and (": " .. first_line) or ""))
  end

  signature = table.concat(lines, "\n")

  if signature == (session.error_signature or "") then
    return
  end

  session.error_signature = signature

  if #lines == 0 then
    return
  end

  vim.notify(
    string.format(
      "[md-view] %s: %d rendering error%s\n%s",
      vim.fn.fnamemodify(vim.api.nvim_buf_get_name(session.bufnr), ":t"),
      #lines,
      #lines == 1 and "" or "s",
      signature
    ),
    vim.log.levels.WARN
  )
end

local function capture(session)
  local client = session.browser
  local target = session.target_session
  local cell = session.cell
  local css_width = math.floor(session.surface.width() * cell.width / session.scale)
  local tiles = {}

  if session.capturing then
    session.dirty = true

    return
  end

  session.capturing = true

  local function finish()
    session.capturing = false

    if session.dirty then
      session.dirty = false
      capture(session)
    end
  end

  local function capture_tiles(total_rows, start_row)
    local rows = math.min(ROWS_PER_TILE, total_rows - start_row)

    if rows <= 0 then
      session.surface.call("show", tiles)
      sync_scroll(session)
      finish()

      return
    end

    cdp_send(
      client,
      "Page.captureScreenshot",
      {
        format = "png",
        captureBeyondViewport = true,
        clip = {
          x = 0,
          y = start_row * cell.height / session.scale,
          width = css_width,
          height = rows * cell.height / session.scale,
          scale = 1,
        },
      },
      target,
      function(result, err)
        if err or not result then
          finish()

          return
        end

        table.insert(tiles, { data = result.data, cols = session.surface.width(), rows = rows })
        capture_tiles(total_rows, start_row + rows)
      end
    )
  end

  -- Shrink the viewport first so scrollHeight reflects the content, not the last viewport.
  cdp_send(
    client,
    "Emulation.setDeviceMetricsOverride",
    {
      width = css_width,
      height = 600,
      deviceScaleFactor = session.scale,
      mobile = false,
    },
    target,
    function()
      cdp_send(client, "Runtime.evaluate", { expression = METRICS_JS, returnByValue = true }, target, function(result)
        local metrics = result and result.result and result.result.value
        local page_height

        if not metrics then
          finish()

          return
        end

        page_height = metrics.height
        session.line_map = metrics.lines
        report_render_errors(session, metrics.errors)

        -- A viewport as tall as the page keeps the SSE scroll events from moving it.
        cdp_send(
          client,
          "Emulation.setDeviceMetricsOverride",
          {
            width = css_width,
            height = page_height,
            deviceScaleFactor = session.scale,
            mobile = false,
          },
          target,
          function()
            capture_tiles(math.ceil(page_height * session.scale / cell.height), 0)
          end
        )
      end)
    end
  )
end

-- Captures once a render newer than the last capture settles, or on timeout; a newer poll supersedes this one.
local function capture_when_rendered(session)
  local baseline = session.render_done or 0
  local started = uv.hrtime()
  local poll_id = (session.poll_id or 0) + 1

  session.poll_id = poll_id

  local function poll()
    if sessions[session.bufnr] ~= session or session.poll_id ~= poll_id then
      return
    end

    cdp_send(
      session.browser,
      "Runtime.evaluate",
      { expression = RENDER_PROGRESS_JS, returnByValue = true },
      session.target_session,
      function(result)
        local progress = result and result.result and result.result.value
        local rendered = progress and progress[1] > baseline and progress[2] == 0
        local timed_out = (uv.hrtime() - started) / 1e6 > RENDER_TIMEOUT_MS

        if session.poll_id ~= poll_id then
          return
        end

        if rendered or timed_out then
          session.render_done = progress and progress[1] or baseline
          capture(session)

          return
        end

        vim.defer_fn(poll, RENDER_POLL_MS)
      end
    )
  end

  poll()
end

---@param wait_for_render boolean poll render progress first (load/edit) instead of capturing directly (resize)
local function schedule_capture(session, delay_ms, wait_for_render)
  session.timer:stop()
  session.timer:start(
    delay_ms,
    0,
    vim.schedule_wrap(function()
      if sessions[session.bufnr] ~= session then
        return
      end

      if wait_for_render then
        capture_when_rendered(session)
      else
        capture(session)
      end
    end)
  )
end

local function acquire_browser(binary)
  if shared_browser and not shared_browser.to_browser:is_closing() then
    return shared_browser
  end

  shared_browser = cdp_spawn(binary, function()
    shared_browser = nil

    for bufnr in pairs(vim.deepcopy(sessions)) do
      M.close(bufnr)
    end
  end)

  return shared_browser
end

local function attach_page(session, url)
  local client = session.browser

  cdp_send(client, "Target.createTarget", { url = "about:blank" }, nil, function(created)
    if not created then
      return
    end

    cdp_send(client, "Target.attachToTarget", { targetId = created.targetId, flatten = true }, nil, function(attached)
      if not attached then
        return
      end

      session.target_id = created.targetId
      session.target_session = attached.sessionId
      client.listeners[attached.sessionId] = {
        ["Page.loadEventFired"] = function()
          schedule_capture(session, 0, true)
        end,
      }

      cdp_send(client, "Page.enable", nil, session.target_session, function()
        cdp_send(client, "Page.navigate", { url = url }, session.target_session)
      end)
    end)
  end)
end

local function register_source_autocmds(session, debounce_ms)
  local group = vim.api.nvim_create_augroup("md_view_terminal_" .. session.bufnr, { clear = true })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost" }, {
    group = group,
    buffer = session.bufnr,
    callback = function()
      -- md-view pushes the edit after its own debounce; then wait for the page to render it
      schedule_capture(session, debounce_ms, true)
    end,
  })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    buffer = session.bufnr,
    callback = function()
      sync_scroll(session)
    end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      schedule_capture(session, RESIZE_DEBOUNCE_MS, false)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = group,
    buffer = session.bufnr,
    callback = function()
      M.close(session.bufnr)
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      M.close(session.bufnr)
    end,
  })
end

---@param bufnr integer|nil
-- keep_surface: the viewer is being handed to another buffer, so leave it open.
local function close_session(bufnr, keep_surface)
  local session = sessions[bufnr]

  if not session then
    return
  end

  sessions[bufnr] = nil
  pcall(vim.api.nvim_del_augroup_by_name, "md_view_terminal_" .. bufnr)
  session.timer:stop()
  session.timer:close()

  if session.browser and session.target_id then
    session.browser.listeners[session.target_session] = nil
    cdp_send(session.browser, "Target.closeTarget", { targetId = session.target_id })
  end

  if not next(sessions) then
    cdp_kill(shared_browser)
    shared_browser = nil
  end

  if session.surface and not keep_surface then
    session.surface.close()

    if viewer and viewer.owner == bufnr then
      viewer = nil
    end
  end
end

---@param bufnr integer|nil
M.close = function(bufnr)
  close_session(bufnr or vim.api.nvim_get_current_buf(), false)
end

M.check_requirements = check_requirements

---@param target "split"|"tmux"
---@param bufnr integer
---@param start_server fun() starts this buffer's preview server without opening a browser
M.open = function(target, bufnr, start_server)
  local config = require("md-view.config")
  local options, binary, preview, url, session

  if not config.options then
    config.setup({})
  end

  options = config.options

  if sessions[bufnr] then
    require("md-view.util").notify(options, "[md-view] Terminal preview already open")

    return
  end

  binary, target = check_requirements(options, target)

  if not binary then
    return
  end

  if not require("md-view.preview").get_by_buffer(bufnr) then
    start_server()
  end

  preview = require("md-view.preview").get_by_buffer(bufnr)

  if not preview then
    return
  end

  -- hub previews render at /view; a buffer with its own browser server is screenshotted from that
  if preview.port then
    url = "http://" .. options.host .. ":" .. preview.port
  else
    url = string.format("http://%s:%d/view?id=%d", options.host, require("md-view.preview").get_mux().port, bufnr)
  end
  session = {
    bufnr = bufnr,
    cell = cell_size(),
    scale = options.preview.terminal.scale,
    timer = uv.new_timer(),
  }
  sessions[bufnr] = session

  local function on_surface(surface)
    if sessions[bufnr] ~= session then
      surface.close()

      return
    end

    session.surface = surface
    viewer = { surface = surface, target = target, owner = bufnr }
    session.browser = acquire_browser(binary)

    if not session.browser then
      vim.notify("[md-view] failed to start " .. binary, vim.log.levels.ERROR)
      M.close(bufnr)

      return
    end

    attach_page(session, url)
    register_source_autocmds(session, options.debounce_ms)
  end

  -- the viewer may have been handed to other buffers since it was created; close its current owner
  local function on_surface_closed()
    if viewer then
      M.close(viewer.owner)
    end
  end

  if viewer and viewer.target == target and sessions[viewer.owner] then
    local previous_owner = viewer.owner

    -- attach first so the shared browser stays up, then release the old buffer's session
    on_surface(viewer.surface)
    close_session(previous_owner, true)

    return
  end

  if viewer then
    M.close(viewer.owner)
  end

  if target == "tmux" then
    tmux_surface(on_surface, on_surface_closed)
  else
    on_surface(split_surface(on_surface_closed))
  end
end

return M
