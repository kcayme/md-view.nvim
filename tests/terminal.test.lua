local terminal = require("md-view.terminal")

describe("terminal.check_requirements", function()
  local orig_notify, orig_executable, orig_system, orig_glob
  local orig_env = {}
  local env_keys = {
    "TMUX",
    "TERM",
    "TERM_PROGRAM",
    "KITTY_WINDOW_ID",
    "GHOSTTY_RESOURCES_DIR",
    "WEZTERM_PANE",
    "PLAYWRIGHT_BROWSERS_PATH",
    "PUPPETEER_CACHE_DIR",
  }
  local notify_calls
  local tmux_replies

  local function options(browser)
    return { preview = { terminal = { browser = browser } } }
  end

  local function messages(level)
    local found = {}

    for _, call in ipairs(notify_calls) do
      if call.level == level then
        table.insert(found, call.msg)
      end
    end

    return found
  end

  before_each(function()
    orig_notify = vim.notify
    orig_executable = vim.fn.executable
    orig_system = vim.fn.system
    orig_glob = vim.fn.glob
    notify_calls = {}
    tmux_replies = { termname = "xterm-ghostty", passthrough = "on" }

    for _, key in ipairs(env_keys) do
      orig_env[key] = vim.env[key]
      vim.env[key] = nil
    end

    vim.notify = function(msg, level)
      table.insert(notify_calls, { msg = msg, level = level })
    end
    vim.fn.executable = function(name)
      return name == "fake-chromium" and 1 or 0
    end
    vim.fn.glob = function()
      return {}
    end
    vim.fn.system = function(cmd)
      if cmd[2] == "display" then
        return tmux_replies.termname .. "\n"
      end

      return tmux_replies.passthrough .. "\n"
    end
  end)

  after_each(function()
    vim.notify = orig_notify
    vim.fn.executable = orig_executable
    vim.fn.system = orig_system
    vim.fn.glob = orig_glob

    for _, key in ipairs(env_keys) do
      vim.env[key] = orig_env[key]
    end
  end)

  it("should pass silently when everything is available in ghostty", function()
    vim.env.TERM = "xterm-ghostty"

    local binary, target = terminal.check_requirements(options("fake-chromium"), "split")

    assert.are.equal("fake-chromium", binary)
    assert.are.equal("split", target)
    assert.are.same({}, notify_calls)
  end)

  it("should error and stop when no headless browser is found", function()
    vim.env.TERM = "xterm-ghostty"

    local binary = terminal.check_requirements(options("missing-browser"), "split")

    assert.is_nil(binary)
    assert.are.equal(1, #messages(vim.log.levels.ERROR))
    assert.truthy(messages(vim.log.levels.ERROR)[1]:find("headless", 1, true))
    assert.truthy(messages(vim.log.levels.ERROR)[1]:find("preview.terminal.browser", 1, true))
  end)

  it("should error and stop when the target is invalid", function()
    local binary = terminal.check_requirements(options("fake-chromium"), "float")

    assert.is_nil(binary)
    assert.truthy(messages(vim.log.levels.ERROR)[1]:find("float", 1, true))
  end)

  it("should warn and fall back to split when tmux is requested outside tmux", function()
    vim.env.TERM = "xterm-kitty"

    local binary, target = terminal.check_requirements(options("fake-chromium"), "tmux")

    assert.are.equal("fake-chromium", binary)
    assert.are.equal("split", target)
    assert.truthy(messages(vim.log.levels.WARN)[1]:find("tmux", 1, true))
  end)

  it("should warn when the terminal is not known to support kitty graphics", function()
    vim.env.TERM = "xterm-256color"

    local binary = terminal.check_requirements(options("fake-chromium"), "split")

    assert.are.equal("fake-chromium", binary)
    assert.truthy(messages(vim.log.levels.WARN)[1]:find("kitty graphics", 1, true))
  end)

  it("should detect the outer terminal through tmux", function()
    vim.env.TMUX = "/tmp/tmux-1000/default,1,0"
    vim.env.TERM = "tmux-256color"

    terminal.check_requirements(options("fake-chromium"), "tmux")

    assert.are.same({}, notify_calls)
  end)

  it("should warn when tmux allow-passthrough is off", function()
    vim.env.TMUX = "/tmp/tmux-1000/default,1,0"
    tmux_replies.passthrough = "off"

    terminal.check_requirements(options("fake-chromium"), "tmux")

    assert.are.equal(1, #messages(vim.log.levels.WARN))
    assert.truthy(messages(vim.log.levels.WARN)[1]:find("allow-passthrough", 1, true))
  end)

  it("should find Playwright's headless shell in the macOS cache", function()
    local shell = "/Users/me/Library/Caches/ms-playwright/chromium_headless_shell-1234/mac/chrome-headless-shell"

    vim.env.TERM = "xterm-ghostty"
    vim.fn.glob = function(pattern)
      return pattern:find("~/Library/Caches/ms-playwright", 1, true) and { shell } or {}
    end

    local binary = terminal.check_requirements(options(nil), "split")

    assert.are.equal(shell, binary)
  end)

  it("should fall back to the macOS Chrome app when nothing else is installed", function()
    local chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

    vim.env.TERM = "xterm-ghostty"
    vim.fn.executable = function(name)
      return name == chrome and 1 or 0
    end

    local binary = terminal.check_requirements(options(nil), "split")

    assert.are.equal(chrome, binary)
  end)

  it("should find Puppeteer's headless shell", function()
    local shell = "/Users/me/.cache/puppeteer/chrome-headless-shell/mac_arm-148.0/chrome-headless-shell-mac-arm64/chrome-headless-shell"

    vim.env.TERM = "xterm-ghostty"
    vim.fn.glob = function(pattern)
      return pattern:find("~/.cache/puppeteer", 1, true) and { shell } or {}
    end

    local binary = terminal.check_requirements(options(nil), "split")

    assert.are.equal(shell, binary)
  end)

  it("should search PLAYWRIGHT_BROWSERS_PATH instead of the default Playwright caches", function()
    local searched = {}

    vim.env.TERM = "xterm-ghostty"
    vim.env.PLAYWRIGHT_BROWSERS_PATH = "/opt/pw"
    vim.fn.glob = function(pattern)
      table.insert(searched, pattern)
      return pattern:find("/opt/pw/", 1, true) and { "/opt/pw/shell" } or {}
    end

    local binary = terminal.check_requirements(options(nil), "split")

    assert.are.equal("/opt/pw/shell", binary)
    assert.are.same({ "/opt/pw/chromium_headless_shell-*/*/chrome-headless-shell" }, searched)
  end)

  it("should search PUPPETEER_CACHE_DIR instead of the default Puppeteer cache", function()
    local searched = {}

    vim.env.TERM = "xterm-ghostty"
    vim.env.PUPPETEER_CACHE_DIR = "/opt/pptr"
    vim.fn.glob = function(pattern)
      table.insert(searched, pattern)
      return {}
    end

    terminal.check_requirements(options(nil), "split")

    assert.truthy(vim.tbl_contains(searched, "/opt/pptr/chrome-headless-shell/*/*/chrome-headless-shell"))
    assert.is_false(vim.tbl_contains(searched, "~/.cache/puppeteer/chrome-headless-shell/*/*/chrome-headless-shell"))
  end)

  it("should find Edge on PATH by its Linux package name", function()
    vim.env.TERM = "xterm-ghostty"
    vim.fn.executable = function(name)
      return name == "microsoft-edge-stable" and 1 or 0
    end

    local binary = terminal.check_requirements(options(nil), "split")

    assert.are.equal("microsoft-edge-stable", binary)
  end)

  it("should fall back to Chrome Canary when it is the only macOS app installed", function()
    local canary = "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary"

    vim.env.TERM = "xterm-ghostty"
    vim.fn.executable = function(name)
      return name == canary and 1 or 0
    end

    local binary = terminal.check_requirements(options(nil), "split")

    assert.are.equal(canary, binary)
  end)

  it("should find Edge installed in the user's Applications folder", function()
    local edge = vim.fn.expand("~/Applications") .. "/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"

    vim.env.TERM = "xterm-ghostty"
    vim.fn.executable = function(name)
      return name == edge and 1 or 0
    end

    local binary = terminal.check_requirements(options(nil), "split")

    assert.are.equal(edge, binary)
  end)
end)

describe("terminal.size_changed", function()
  local cell = { width = 10, height = 21 }

  it("should re-render when nothing has been captured yet", function()
    assert.is_true(terminal.size_changed(nil, 80, cell))
  end)

  it("should re-render when the viewer width changes", function()
    assert.is_true(terminal.size_changed({ cols = 80, cell = cell }, 60, cell))
  end)

  it("should re-render when the cell size changes (font zoom)", function()
    assert.is_true(terminal.size_changed({ cols = 80, cell = cell }, 80, { width = 12, height = 25 }))
  end)

  it("should not re-render when only the height changed", function()
    assert.is_false(terminal.size_changed({ cols = 80, cell = cell }, 80, { width = 10, height = 21 }))
  end)
end)

describe("terminal.resolve_scale", function()
  local orig_has

  before_each(function()
    orig_has = vim.fn.has
  end)

  after_each(function()
    vim.fn.has = orig_has
  end)

  local function on_mac(is_mac)
    vim.fn.has = function(feature)
      return feature == "mac" and (is_mac and 1 or 0) or orig_has(feature)
    end
  end

  it("should render at 2x on macOS when auto", function()
    on_mac(true)

    assert.are.equal(2, terminal.resolve_scale("auto"))
  end)

  it("should render at 1x elsewhere when auto", function()
    on_mac(false)

    assert.are.equal(1, terminal.resolve_scale("auto"))
  end)

  it("should keep an explicit scale", function()
    on_mac(true)

    assert.are.equal(1, terminal.resolve_scale(1))
  end)
end)
