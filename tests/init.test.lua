local M
local create_called
local notify_msg
local orig_notify

describe("md-view init", function()
  before_each(function()
    create_called = false
    notify_msg = nil
    orig_notify = vim.notify
    vim.notify = function(msg, level)
      notify_msg = { msg = msg, level = level }
    end
    package.loaded["md-view"] = nil
    package.loaded["md-view.preview"] = {
      create = function()
        create_called = true
      end,
      get = function()
        return nil
      end,
      destroy = function() end,
      get_active = function()
        return {}
      end,
    }
    M = require("md-view")
    M.setup({ filetypes = { "markdown" } })
    notify_msg = nil
  end)

  after_each(function()
    vim.notify = orig_notify
    package.loaded["md-view"] = nil
    package.loaded["md-view.preview"] = nil
    package.loaded["md-view.config"] = nil
    package.loaded["md-view.vendor"] = nil
  end)

  it("blocks preview when filetype is not in filetypes list", function()
    vim.bo.filetype = "lua"
    M.open()
    assert.is_false(create_called)
    assert.is_not_nil(notify_msg)
    assert.are.equal(vim.log.levels.WARN, notify_msg.level)
    assert.truthy(notify_msg.msg:find("lua"))
  end)

  it("allows preview when filetype is in filetypes list", function()
    vim.bo.filetype = "markdown"
    M.open()
    assert.is_true(create_called)
    assert.is_nil(notify_msg)
  end)

  it("allows preview when filetypes is empty (no restriction)", function()
    M.setup({ filetypes = {} })
    vim.bo.filetype = "lua"
    M.open()
    assert.is_true(create_called)
  end)

  it("toggle blocks preview when filetype is not in filetypes list", function()
    vim.bo.filetype = "lua"
    M.toggle()
    assert.is_false(create_called)
  end)

  it("should not notify when curl is absent and vendor is unavailable", function()
    package.loaded["md-view"] = nil
    package.loaded["md-view.preview"] = {
      create = function() end,
      get = function()
        return nil
      end,
      destroy = function() end,
      get_active = function()
        return {}
      end,
    }
    package.loaded["md-view.vendor"] = {
      is_available = function()
        return false
      end,
      fetch = function() end,
    }
    local orig_executable = vim.fn.executable
    vim.fn.executable = function(cmd)
      if cmd == "curl" then
        return 0
      end
      return orig_executable(cmd)
    end

    local notify_calls = {}
    local orig_notify_inner = orig_notify
    vim.notify = function(msg, level)
      table.insert(notify_calls, { msg = msg, level = level })
    end

    local m = require("md-view")
    m.setup({})

    vim.fn.executable = orig_executable
    vim.notify = orig_notify_inner
    package.loaded["md-view"] = nil
    package.loaded["md-view.preview"] = nil
    package.loaded["md-view.vendor"] = nil

    assert.are.equal(0, #notify_calls, "expected no notifications when curl is absent")
  end)
end)
