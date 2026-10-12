local terminal = require("md-view.terminal")

describe("terminal.check_requirements", function()
  local orig_notify, orig_executable, orig_system
  local orig_env = {}
  local env_keys = { "TMUX", "TERM", "TERM_PROGRAM", "KITTY_WINDOW_ID", "GHOSTTY_RESOURCES_DIR", "WEZTERM_PANE" }
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
end)
