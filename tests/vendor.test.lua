describe("vendor", function()
  describe("vendor_dir", function()
    it("returns XDG data path with plugin subdir", function()
      local orig_stdpath = vim.fn.stdpath
      vim.fn.stdpath = function(what)
        if what == "data" then
          return "/mock/data"
        end
        return orig_stdpath(what)
      end
      local v = require("md-view.vendor")
      local result = v.vendor_dir()
      vim.fn.stdpath = orig_stdpath
      assert.are.equal("/mock/data/md-view.nvim/vendor", result)
    end)
  end)

  describe("is_available", function()
    after_each(function()
      package.loaded["md-view.vendor"] = nil
    end)

    it("returns false when vendor dir does not exist", function()
      local uv = vim.uv or vim.loop
      local orig_fs_stat = uv.fs_stat
      uv.fs_stat = function(_path)
        return nil -- simulate missing file
      end
      local v = require("md-view.vendor")
      local result = v.is_available()
      uv.fs_stat = orig_fs_stat
      assert.is_false(result)
    end)

    it("returns true when all vendor files exist", function()
      local uv = vim.uv or vim.loop
      local orig_fs_stat = uv.fs_stat
      uv.fs_stat = function(_path)
        return { size = 100 } -- simulate file exists
      end
      local v = require("md-view.vendor")
      local result = v.is_available()
      uv.fs_stat = orig_fs_stat
      assert.is_true(result)
    end)

    it("returns false when uv.fs_stat returns an error string", function()
      local uv = vim.uv or vim.loop
      local orig_fs_stat = uv.fs_stat
      uv.fs_stat = function(_path)
        return nil, "ENOENT: no such file or directory"
      end
      local v = require("md-view.vendor")
      local result = v.is_available()
      uv.fs_stat = orig_fs_stat
      assert.is_false(result)
    end)
  end)

  describe("fetch", function()
    local orig_executable, orig_util, orig_mkdir, orig_jobstart

    after_each(function()
      if orig_executable then
        vim.fn.executable = orig_executable
        orig_executable = nil
      end
      if orig_util then
        package.loaded["md-view.util"] = orig_util
        orig_util = nil
      end
      if orig_mkdir then
        vim.fn.mkdir = orig_mkdir
        orig_mkdir = nil
      end
      if orig_jobstart then
        vim.fn.jobstart = orig_jobstart
        orig_jobstart = nil
      end
      -- Force reload to reset module-level `fetching` flag
      package.loaded["md-view.vendor"] = nil
    end)

    it("notifies ERROR when curl is not found", function()
      local notify_calls = {}
      orig_util = package.loaded["md-view.util"]
      package.loaded["md-view.util"] = {
        notify = function(opts, msg, level)
          table.insert(notify_calls, { opts = opts, msg = msg, level = level })
        end,
      }
      package.loaded["md-view.vendor"] = nil
      local v = require("md-view.vendor")

      orig_executable = vim.fn.executable
      vim.fn.executable = function(cmd)
        if cmd == "curl" then
          return 0
        end
        return orig_executable(cmd)
      end

      v.fetch()

      local found = false
      for _, call in ipairs(notify_calls) do
        if call.level == vim.log.levels.ERROR and call.msg:find("curl") then
          found = true
          break
        end
      end
      assert.is_true(found, "expected ERROR notify mentioning curl")
    end)

    it("notifies WARN when fetch already in progress", function()
      local notify_calls = {}
      orig_util = package.loaded["md-view.util"]
      package.loaded["md-view.util"] = {
        notify = function(opts, msg, level)
          table.insert(notify_calls, { opts = opts, msg = msg, level = level })
        end,
      }
      package.loaded["md-view.vendor"] = nil
      local v = require("md-view.vendor")

      orig_executable = vim.fn.executable
      orig_mkdir = vim.fn.mkdir
      orig_jobstart = vim.fn.jobstart
      vim.fn.executable = function(cmd)
        if cmd == "curl" then
          return 1
        end
        return orig_executable(cmd)
      end
      vim.fn.mkdir = function(_path, _flags)
        return 1
      end
      vim.fn.jobstart = function(_cmd, _opts)
        return 1
      end

      -- First call sets fetching = true
      v.fetch()
      -- Second call should hit the guard
      v.fetch()

      local found = false
      for _, call in ipairs(notify_calls) do
        if call.level == vim.log.levels.WARN and call.msg:find("already in progress") then
          found = true
          break
        end
      end
      assert.is_true(found, "expected WARN notify about fetch already in progress")
    end)

    it("notifies ERROR when vendor dir cannot be created", function()
      local notify_calls = {}
      orig_util = package.loaded["md-view.util"]
      package.loaded["md-view.util"] = {
        notify = function(opts, msg, level)
          table.insert(notify_calls, { opts = opts, msg = msg, level = level })
        end,
      }
      package.loaded["md-view.vendor"] = nil
      local v = require("md-view.vendor")

      orig_executable = vim.fn.executable
      orig_mkdir = vim.fn.mkdir
      vim.fn.executable = function(cmd)
        if cmd == "curl" then
          return 1
        end
        return orig_executable(cmd)
      end
      vim.fn.mkdir = function(_path, _flags)
        return 0 -- simulate failure
      end

      v.fetch()

      local found = false
      for _, call in ipairs(notify_calls) do
        if call.level == vim.log.levels.ERROR and call.msg:find("vendor dir") then
          found = true
          break
        end
      end
      assert.is_true(found, "expected ERROR notify about vendor dir creation failure")
    end)

    it("spawns 19 jobstart calls when curl is available (17 static + 2 default theme files)", function()
      local v = require("md-view.vendor")
      orig_executable = vim.fn.executable
      orig_mkdir = vim.fn.mkdir
      orig_jobstart = vim.fn.jobstart

      local job_count = 0
      vim.fn.executable = function(cmd)
        if cmd == "curl" then
          return 1
        end
        return orig_executable(cmd)
      end
      vim.fn.mkdir = function(_path, _flags)
        return 1 -- success
      end
      vim.fn.jobstart = function(_cmd, _opts)
        job_count = job_count + 1
        return job_count
      end

      v.fetch()

      assert.are.equal(19, job_count)
    end)

    it("uses default highlight theme vs2015 when no opts given", function()
      local v = require("md-view.vendor")
      orig_executable = vim.fn.executable
      orig_mkdir = vim.fn.mkdir
      orig_jobstart = vim.fn.jobstart

      local curl_urls = {}
      vim.fn.executable = function(cmd)
        if cmd == "curl" then
          return 1
        end
        return orig_executable(cmd)
      end
      vim.fn.mkdir = function(_path, _flags)
        return 1
      end
      vim.fn.jobstart = function(cmd, _opts)
        -- cmd is { "curl", "-fsSL", "-o", dest, url }
        table.insert(curl_urls, cmd[5])
        return #curl_urls
      end

      v.fetch()

      local found = false
      for _, url in ipairs(curl_urls) do
        if url:find("vs2015%.min%.css") then
          found = true
          break
        end
      end
      assert.is_true(found, "expected vs2015.min.css URL in curl calls")
    end)

    it("uses custom highlight theme when specified in opts", function()
      local v = require("md-view.vendor")
      orig_executable = vim.fn.executable
      orig_mkdir = vim.fn.mkdir
      orig_jobstart = vim.fn.jobstart

      local curl_urls = {}
      vim.fn.executable = function(cmd)
        if cmd == "curl" then
          return 1
        end
        return orig_executable(cmd)
      end
      vim.fn.mkdir = function(_path, _flags)
        return 1
      end
      vim.fn.jobstart = function(cmd, _opts)
        table.insert(curl_urls, cmd[5])
        return #curl_urls
      end

      v.fetch({ highlight_theme = "github" })

      local found = false
      for _, url in ipairs(curl_urls) do
        if url:find("github%.min%.css") then
          found = true
          break
        end
      end
      assert.is_true(found, "expected github.min.css URL in curl calls")
    end)

    it("falls back to vs2015 when highlight_theme sanitizes to empty string", function()
      local v = require("md-view.vendor")
      orig_executable = vim.fn.executable
      orig_mkdir = vim.fn.mkdir
      orig_jobstart = vim.fn.jobstart

      local css_url = nil
      vim.fn.executable = function(cmd)
        if cmd == "curl" then
          return 1
        end
        return orig_executable(cmd)
      end
      vim.fn.mkdir = function(_path, _flags)
        return 1
      end
      vim.fn.jobstart = function(cmd, _opts)
        local dest = cmd[4]
        -- dest is now highlight-theme-{name}.min.css
        if dest and dest:find("highlight%-theme%-") then
          css_url = cmd[5]
        end
        return 1
      end

      -- "!!!" sanitizes to "" which should fall back to "vs2015"
      v.fetch({ highlight_theme = "!!!" })

      assert.is_not_nil(css_url, "expected a highlight-theme CSS curl call")
      assert.truthy(css_url:find("vs2015"), "URL should contain fallback theme vs2015")
    end)

    it("sanitizes malicious highlight_theme to safe characters", function()
      local v = require("md-view.vendor")
      orig_executable = vim.fn.executable
      orig_mkdir = vim.fn.mkdir
      orig_jobstart = vim.fn.jobstart

      local css_url = nil
      vim.fn.executable = function(cmd)
        if cmd == "curl" then
          return 1
        end
        return orig_executable(cmd)
      end
      vim.fn.mkdir = function(_path, _flags)
        return 1
      end
      vim.fn.jobstart = function(cmd, _opts)
        local url = cmd[5]
        -- The highlight-theme CSS is identified by its destination filename
        local dest = cmd[4]
        -- dest is now highlight-theme-{name}.min.css
        if dest and dest:find("highlight%-theme%-") then
          css_url = url
        end
        return 1
      end

      -- "../../etc/passwd" → gsub removes non [%w_%-] → "etcpasswd"
      v.fetch({ highlight_theme = "../../etc/passwd" })

      assert.is_not_nil(css_url, "expected a highlight-theme CSS curl call")
      -- The sanitized theme name should not contain path traversal sequences
      assert.is_falsy(css_url:find("%.%."), "URL should not contain path traversal")
      assert.is_falsy(css_url:find("/etc/passwd"), "URL should not reference /etc/passwd")
      -- The sanitized result "etcpasswd" should appear in the URL
      assert.truthy(css_url:find("etcpasswd"), "URL should contain sanitized theme name")
    end)
  end)
end)
