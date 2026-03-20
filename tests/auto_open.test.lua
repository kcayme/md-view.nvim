local config = require("md-view.config")

-- Stub preview.create to avoid real server startup
local preview = require("md-view.preview")
preview.create = function() end

local function augroup_exists(name)
  local ok = pcall(vim.api.nvim_get_autocmds, { group = name })
  return ok
end

describe("auto_open", function()
  after_each(function()
    config.options = nil
    pcall(vim.api.nvim_del_augroup_by_name, "md_view_auto_open")
  end)

  describe("setup", function()
    it("creates md_view_auto_open augroup when enable = true", function()
      local md_view = require("md-view")
      md_view.setup({ auto_open = { enable = true } })
      assert.is_true(augroup_exists("md_view_auto_open"))
    end)

    it("does not create augroup when enable = false", function()
      local md_view = require("md-view")
      md_view.setup({ auto_open = { enable = false } })
      assert.is_false(augroup_exists("md_view_auto_open"))
    end)

    it("re-setup with enable = false removes previously created augroup", function()
      local md_view = require("md-view")
      md_view.setup({ auto_open = { enable = true } })
      assert.is_true(augroup_exists("md_view_auto_open"))
      md_view.setup({ auto_open = { enable = false } })
      assert.is_false(augroup_exists("md_view_auto_open"))
    end)
  end)

  describe("M.open verbose param", function()
    it("does not notify when filetype not in list and verbose = false", function()
      local md_view = require("md-view")
      config.setup({ filetypes = { "markdown" } })
      vim.bo[vim.api.nvim_get_current_buf()].filetype = "lua"
      local notified = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.WARN and msg:find("not in filetypes") then
          notified = true
        end
      end
      md_view.open({ verbose = false })
      vim.notify = orig_notify
      assert.is_false(notified)
    end)

    it("notifies when filetype not in list and verbose defaults to config value", function()
      local md_view = require("md-view")
      config.setup({ filetypes = { "markdown" }, verbose = true })
      vim.bo[vim.api.nvim_get_current_buf()].filetype = "lua"
      local notified = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.WARN and msg:find("not in filetypes") then
          notified = true
        end
      end
      md_view.open()
      vim.notify = orig_notify
      assert.is_true(notified)
    end)
  end)

  describe("toggle_auto_open", function()
    local notify_msg
    local orig_notify

    before_each(function()
      notify_msg = nil
      orig_notify = vim.notify
      vim.notify = function(msg, level)
        notify_msg = { msg = msg, level = level }
      end
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
    end)

    after_each(function()
      vim.notify = orig_notify
      package.loaded["md-view"] = nil
      package.loaded["md-view.preview"] = nil
    end)

    it("enables auto-open when disabled, creates augroup, notifies", function()
      local md_view = require("md-view")
      md_view.setup({ auto_open = { enable = false }, verbose = true })
      md_view.toggle_auto_open()
      assert.is_true(config.options.auto_open.enable)
      assert.is_true(augroup_exists("md_view_auto_open"))
      assert.is_not_nil(notify_msg)
      assert.truthy(notify_msg.msg:find("auto%-open enable"))
    end)

    it("disables auto-open when enable, deletes augroup, notifies", function()
      local md_view = require("md-view")
      md_view.setup({ auto_open = { enable = true }, verbose = true })
      md_view.toggle_auto_open()
      assert.is_false(config.options.auto_open.enable)
      assert.is_false(augroup_exists("md_view_auto_open"))
      assert.is_not_nil(notify_msg)
      assert.truthy(notify_msg.msg:find("auto%-open disabled"))
    end)
  end)
end)
