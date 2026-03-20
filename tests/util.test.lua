local util = require("md-view.util")

describe("util", function()
  describe("table_len", function()
    it("returns 0 for empty table", function()
      assert.are.equal(0, util.table_len({}))
    end)

    it("counts all keys in a table", function()
      assert.are.equal(3, util.table_len({ a = 1, b = 2, c = 3 }))
    end)

    it("counts sequential keys", function()
      assert.are.equal(3, util.table_len({ 10, 20, 30 }))
    end)

    it("counts mixed keys", function()
      assert.are.equal(4, util.table_len({ 1, 2, x = "a", y = "b" }))
    end)
  end)

  describe("notify", function()
    local orig_notify
    local notify_calls

    before_each(function()
      orig_notify = vim.notify
      notify_calls = {}
      vim.notify = function(msg, level)
        table.insert(notify_calls, { msg = msg, level = level })
      end
    end)

    after_each(function()
      vim.notify = orig_notify
    end)

    it("calls vim.notify when silent is false", function()
      util.notify({ silent = false }, "hello")
      assert.are.equal(1, #notify_calls)
      assert.are.equal("hello", notify_calls[1].msg)
    end)

    it("calls vim.notify when silent is nil", function()
      util.notify({}, "hello")
      assert.are.equal(1, #notify_calls)
    end)

    it("does not call vim.notify when silent is true", function()
      util.notify({ silent = true }, "hello")
      assert.are.equal(0, #notify_calls)
    end)

    it("passes level to vim.notify", function()
      util.notify({ silent = false }, "oops", vim.log.levels.ERROR)
      assert.are.equal(vim.log.levels.ERROR, notify_calls[1].level)
    end)

    it("passes nil level when not provided", function()
      util.notify({ silent = false }, "info")
      assert.is_nil(notify_calls[1].level)
    end)
  end)
end)
