-- Run: nvim -n --headless -u NONE -i NONE -l tests/diffview-updates.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
for _, plugin in ipairs({ "diffview.nvim", "plenary.nvim" }) do
  vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/" .. plugin)
end
vim.o.hidden, vim.o.swapfile = true, false
vim.o.lines, vim.o.columns = 55, 180
local notices = {}
vim.notify = function(message) notices[#notices + 1] = tostring(message) end
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p")
local function git(args)
  local command = { "git", "-C", directory, "-c", "user.name=Update Test", "-c", "user.email=updates@example.test" }
  vim.list_extend(command, args)
  local result = vim.system(command, { text = true }):wait(5000)
  assert(result.code == 0, result.stderr)
end
git({ "init", "-q" })
for _, name in ipairs({ "a.txt", "b.txt", "c.txt" }) do vim.fn.writefile({ "base" }, directory .. "/" .. name) end
git({ "add", "." })
git({ "commit", "-qm", "base" })
for _, name in ipairs({ "a.txt", "b.txt", "c.txt" }) do vim.fn.writefile({ "changed" }, directory .. "/" .. name) end
vim.cmd.cd(vim.fn.fnameescape(directory))
vim.cmd.edit(vim.fn.fnameescape(directory .. "/a.txt"))
dofile(root .. "/lua/plugins/diffview-nvim.lua")[1].config()
require("diffview.config").get_config().watch_index = false
-- Initialize diagnostics as in a normal editing session (Neovim 0.12's
-- headless redraw can crash with a completely empty diagnostics registry).
vim.diagnostic.set(vim.api.nvim_create_namespace("updates-test"), 0, {})
vim.cmd("runtime plugin/diffview.lua")
vim.cmd("DiffviewOpen")
local view = require("diffview.lib").get_current_view()
local function wait(predicate, label) assert(vim.wait(10000, predicate, 10), label .. "\n" .. vim.inspect(notices)) end
wait(function() return view.initialized and view.cur_entry and view.cur_entry.opened end, "Initial Diffview")
vim.wait(200, function() return false end)
-- Model a synchronous Git job pumping the event loop during list mutation.
-- A nested refresh removes a.txt while the outer edit script still needs it.
local first = view.files.working[1]
local validate = first.validate_stage_buffers
local nested_done, outer_done = false, false
first.validate_stage_buffers = function(self, stat)
  self.validate_stage_buffers = validate
  vim.defer_fn(function()
    git({ "add", "a.txt" })
    view:update_files(function(err) assert(not err); nested_done = true end)
  end, 130)
  vim.wait(450, function() return false end)
  validate(self, stat)
end
view:update_files(function(err) assert(not err); outer_done = true end)
wait(function() return outer_done and nested_done end, "Reentrant refresh during validation")
assert(#view.files.working == 2 and #view.files.staged == 1)
git({ "restore", "--staged", "a.txt" })
local reset_done = false
view:update_files(function(err) assert(not err); reset_done = true end)
wait(function() return reset_done end, "Reset fixture staging")
local async = require("diffview.async")
local get = view.get_updated_files
local active, maximum, queries = 0, 0, 0
view.get_updated_files = async.wrap(function(self, callback)
  active, queries = active + 1, queries + 1
  maximum = math.max(maximum, active)
  get(self, function(err, files)
    vim.defer_fn(function()
      active = active - 1
      callback(err, files)
    end, 250)
  end)
end)
local completed = 0
local function done(err) assert(not err, vim.inspect(err)); completed = completed + 1 end
view:update_files(done)
vim.defer_fn(function()
  git({ "add", "a.txt" })
  view:update_files(done)
  view:update_files(done)
end, 130)
vim.defer_fn(function()
  git({ "add", "b.txt" })
  view:update_files(done)
end, 180)
wait(function() return completed == 4 end, "Every coalesced refresh callback must complete")
assert(maximum == 1, "Refreshes must not overlap: " .. maximum)
assert(queries == 2, "A burst during refresh should produce one follow-up query: " .. queries)
assert(#view.files.working == 1 and view.files.working[1].path == "c.txt")
assert(#view.files.staged == 2)
-- A failed Git query must release the queue and forward its error.
view.get_updated_files = async.wrap(function(_, callback) callback({ "expected query failure" }) end)
local failed
view:update_files(function(err) failed = err end)
wait(function() return failed ~= nil end, "Error callback")
assert(failed[1] == "expected query failure")
view.get_updated_files = get
local recovered = false
view:update_files(function(err) assert(not err); recovered = true end)
wait(function() return recovered end, "Refresh after a query failure")
-- The upstream debouncer is shared: different views must not replace each
-- other's callbacks. Closing an in-flight view must release the queue too.
vim.cmd("DiffviewOpen")
local second = require("diffview.lib").get_current_view()
assert(second ~= view)
wait(function() return second.initialized and second.cur_entry and second.cur_entry.opened end, "Second Diffview")
vim.wait(200, function() return false end)
local second_get, release = second.get_updated_files, nil
second.get_updated_files = async.wrap(function(self, callback)
  second_get(self, function(err, files)
    release = function() callback(err, files) end
  end)
end)
local closed_callbacks, other_done = 0, false
local function closed(err)
  assert(err and err[1]:find("cancelled", 1, true))
  closed_callbacks = closed_callbacks + 1
end
second:update_files(closed)
wait(function() return release ~= nil end, "Second view's in-flight query")
view:update_files(function(err) assert(not err); other_done = true end)
second:update_files(closed)
vim.cmd("DiffviewClose")
assert(require("diffview.lib").get_current_view() == view)
release()
wait(function() return closed_callbacks == 2 and other_done end, "Cross-view callbacks after in-flight close")
-- A queued refresh must not resurrect a closed view or lose its callbacks.
local cancelled = 0
for _ = 1, 2 do
  view:update_files(function(err)
    assert(err and err[1]:find("cancelled", 1, true))
    cancelled = cancelled + 1
  end)
end
vim.cmd("DiffviewClose")
wait(function() return cancelled == 2 end, "Closed-view callbacks")
vim.cmd.cd(vim.fn.fnameescape(root))
vim.fn.delete(directory, "rf")
print("PASS: reentrant/slow Diffview refreshes, callbacks, staging, query errors, multiple views, and in-flight close")
vim.cmd("qa!")
