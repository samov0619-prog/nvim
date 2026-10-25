-- Run: nvim -n --headless -u NONE -i NONE -l tests/code-review.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
for _, plugin in ipairs({ "diffview.nvim", "plenary.nvim", "conform.nvim", "nvim-lint" }) do
  vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/" .. plugin)
end
vim.o.hidden, vim.o.swapfile, vim.o.backup, vim.o.writebackup = true, false, false, false
vim.o.spell = true
vim.o.lines, vim.o.columns = 55, 180
vim.g.mapleader = " "
local api = vim.api
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p")
local notices = {}
vim.notify = function(message) notices[#notices + 1] = tostring(message) end
local function wait(predicate, label)
  assert(vim.wait(10000, predicate, 10), label .. "\n" .. vim.inspect(notices))
end
local function settle() vim.wait(80, function() return false end) end
local function git(args, stdin)
  local command = { "git", "-C", directory, "-c", "user.name=Review Test", "-c", "user.email=review@example.test" }
  vim.list_extend(command, args)
  local result = vim.system(command, { text = true, stdin = stdin }):wait(5000)
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end
local path = directory .. "/file.txt"
git({ "init", "-q" })
vim.fn.writefile({ "base" }, path)
git({ "add", "file.txt" })
git({ "commit", "-qm", "base" })
vim.fn.writefile({ "changed" }, path)
git({ "add", "file.txt" })
git({ "commit", "-qm", "changed" })
vim.fn.writefile({ "working" }, path)
vim.cmd.cd(vim.fn.fnameescape(directory))
vim.cmd.edit(vim.fn.fnameescape(path))
vim.bo.filetype = "review"
local buf, ordinary_tab, ordinary_win = api.nvim_get_current_buf(), api.nvim_get_current_tabpage(), api.nvim_get_current_win()
local tools = require("config.code-tools")
assert(not tools.in_review() and not tools.in_review(0), "An ordinary file is not a review context before loading Diffview")
local checks = require("config.code-checks")
local pending, started, cancelled = {}, 0, 0
checks.format = function(_, snapshot, done)
  started = started + 1
  pending[#pending + 1] = { snapshot = snapshot, done = done }
  return function() cancelled = cancelled + 1 end
end
require("conform.log").set_handler(function() end)
local conform = require("conform")
local formatting, reply = 0, nil
conform.setup({ formatters_by_ft = { review = { "held" } }, formatters = {
  held = { inherit = false, format = function(_, _, _, callback) formatting = formatting + 1; reply = callback end },
} })
local code = require("config.code")
require("config.mapping")
local diagnostics = require("config.code-diagnostics")
diagnostics.setup()
wait(function() return started > 0 end, "Initial background check")
local initial = pending[#pending]
local visible = api.nvim_create_namespace("review-visible")
local disabled = api.nvim_create_namespace("review-user-disabled")
local marker = { { lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = "test marker" } }
vim.diagnostic.set(visible, buf, vim.deepcopy(marker))
vim.diagnostic.set(disabled, buf, vim.deepcopy(marker))
vim.diagnostic.enable(false, { bufnr = buf, ns_id = disabled })
dofile(root .. "/lua/plugins/diffview-nvim.lua")[1].config()
vim.cmd("runtime plugin/diffview.lua")
local lib = require("diffview.lib")
assert(not tools.in_review(), "Loading Diffview alone must not suppress an ordinary file")
local function open(command, minimum)
  vim.cmd(command)
  local view = lib.get_current_view()
  wait(function()
    local count = 0
    for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
      if vim.wo[win].diff and api.nvim_buf_get_name(api.nvim_win_get_buf(win)) ~= "diffview://null" then count = count + 1 end
    end
    return count >= minimum
  end, command .. " panes")
  settle()
  return view
end
local function quiet(minimum)
  local count = 0
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if vim.wo[win].diff then
      count = count + 1
      local b = api.nvim_win_get_buf(win)
      assert(tools.in_review(b) and not vim.wo[win].spell, "Every diff pane must be quiet")
      api.nvim_win_call(win, function()
        assert(vim.fn.maparg(" cf", "n") == "<Nop>" and vim.fn.maparg(" cx", "n") == "<Nop>")
        local tick = api.nvim_buf_get_changedtick(b)
        local running = code.is_running(b)
        code.format_file(); code.fix_file()
        assert(code.is_running(b) == running and tick == api.nvim_buf_get_changedtick(b))
      end)
      vim.diagnostic.set(visible, b, vim.deepcopy(marker))
      assert(not vim.diagnostic.is_enabled({ bufnr = b, ns_id = visible }))
      for name, ns in pairs(vim.diagnostic.get_namespace(visible).user_data) do
        if name ~= "location_ns" and name:match("_ns$") and type(ns) == "number" then
          assert(#api.nvim_buf_get_extmarks(b, ns, 0, -1, {}) == 0, "No diagnostic signs, underlines or virtual text")
        end
      end
    end
  end
  assert(count >= minimum)
end
local function ordinary()
  assert(api.nvim_get_current_tabpage() == ordinary_tab and api.nvim_get_current_buf() == buf)
  assert(not tools.in_review(buf) and vim.wo[ordinary_win].spell)
  assert(vim.diagnostic.is_enabled({ bufnr = buf, ns_id = visible }))
  assert(not vim.diagnostic.is_enabled({ bufnr = buf, ns_id = disabled }), "User-disabled namespace must stay disabled")
  assert(vim.fn.maparg(" cf", "n", false, true).buffer == 0 and vim.fn.maparg(" cx", "n", false, true).buffer == 0)
end
local view = open("DiffviewOpen", 2)
quiet(2)
assert(cancelled > 0 and not initial.snapshot.current(), "Entering review cancels and invalidates background checks")
local runs = started
diagnostics.refresh(buf, true)
settle()
assert(started == runs, "No background checks inside review")
local late = api.nvim_create_namespace("review-late-namespace")
vim.diagnostic.set(late, buf, vim.deepcopy(marker))
assert(not vim.diagnostic.is_enabled({ bufnr = buf, ns_id = late }), "New namespaces must also stay quiet")
local shared = false
for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do shared = shared or api.nvim_win_get_buf(win) == buf end
assert(shared, "The working side must share the ordinary buffer")
api.nvim_set_current_tabpage(ordinary_tab)
settle(); ordinary()
assert(started > runs and vim.diagnostic.is_enabled({ bufnr = buf, ns_id = late }), "Tab return resumes checks and diagnostics")
code.format_file()
assert(formatting == 1 and code.is_running(buf), "cf works while Diffview remains open")
api.nvim_set_current_tabpage(view.tabpage)
quiet(2)
reply(nil, { "late formatting" })
wait(function() return not code.is_running(buf) end, "Formatter unlock after entering review")
assert(api.nvim_buf_get_lines(buf, 0, -1, false)[1] == "working", "Late format cannot apply inside review")
-- gf must return to an existing ordinary file window while keeping the view.
for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
  if api.nvim_win_get_buf(win) == buf then
    api.nvim_set_current_win(win)
    vim.fn.maparg("gf", "n", false, true).callback()
    break
  end
end
settle(); ordinary()
assert(api.nvim_tabpage_is_valid(view.tabpage))
api.nvim_set_current_tabpage(view.tabpage)
vim.cmd.DiffviewClose()
settle(); ordinary()
print("PASS: all diff sides quiet; shared buffer, late namespaces, checks, cf/cx, late formatter, tab return, gf and close")

-- cf intentionally leaves unsaved edits. gf must focus/reuse that buffer,
-- including with 'nohidden', rather than :edit it again or replace other edits.
vim.o.hidden = false
vim.bo[buf].filetype = "review"
code.format_file()
assert(code.is_running(buf) and formatting == 2, "The fixture formatter must start")
reply(nil, { "formatted but unsaved" })
wait(function() return not code.is_running(buf) end, "Unsaved formatting before gf")
assert(vim.bo[buf].modified and vim.fn.readfile(path)[1] == "working")
api.nvim_win_set_cursor(ordinary_win, { 1, 4 })
local formatted_tick = api.nvim_buf_get_changedtick(buf)
local undo_sequence = vim.fn.undotree().seq_cur
local function follow_working_file()
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_buf(win) == buf then
      api.nvim_set_current_win(win)
      vim.fn.maparg("gf", "n", false, true).callback()
      settle()
      return
    end
  end
  error("Working side not found")
end
local function formatted_preserved()
  assert(api.nvim_get_current_buf() == buf and vim.bo[buf].modified)
  assert(api.nvim_buf_get_changedtick(buf) == formatted_tick and vim.fn.undotree().seq_cur == undo_sequence)
  assert(api.nvim_buf_get_lines(buf, 0, -1, false)[1] == "formatted but unsaved")
  assert(vim.fn.readfile(path)[1] == "working" and not vim.o.hidden)
  assert(not tools.in_review() and not vim.wo.diff and vim.wo.spell)
end
view = open("DiffviewOpen -- file.txt", 2)
local tabs = #api.nvim_list_tabpages()
follow_working_file()
formatted_preserved(); ordinary()
assert(api.nvim_get_current_win() == ordinary_win and #api.nvim_list_tabpages() == tabs)
assert(vim.deep_equal(api.nvim_win_get_cursor(ordinary_win), { 1, 4 }), "Focus must preserve the ordinary cursor")

local other_path = directory .. "/other.txt"
vim.fn.writefile({ "other saved" }, other_path)
vim.cmd("hide edit " .. vim.fn.fnameescape(other_path))
local other_buf = api.nvim_get_current_buf()
api.nvim_set_current_tabpage(view.tabpage)
follow_working_file()
formatted_preserved(); ordinary()
assert(#api.nvim_list_tabpages() == tabs, "An unmodified ordinary window should reuse the loaded target buffer")

vim.cmd("hide edit " .. vim.fn.fnameescape(other_path))
api.nvim_buf_set_lines(other_buf, 0, -1, false, { "other unsaved" })
api.nvim_set_current_tabpage(view.tabpage)
follow_working_file()
formatted_preserved()
local unsaved_tab = api.nvim_get_current_tabpage()
assert(unsaved_tab ~= ordinary_tab and unsaved_tab ~= view.tabpage and #api.nvim_list_tabpages() == tabs + 1)
assert(api.nvim_win_get_buf(ordinary_win) == other_buf and vim.bo[other_buf].modified)
assert(api.nvim_buf_get_lines(other_buf, 0, -1, false)[1] == "other unsaved")
assert(vim.fn.readfile(other_path)[1] == "other saved", "Neither file may be implicitly saved")
vim.o.hidden = true
api.nvim_set_current_tabpage(view.tabpage)
vim.cmd.DiffviewClose(); settle()
api.nvim_set_current_tabpage(unsaved_tab); vim.cmd.tabclose()
api.nvim_set_current_win(ordinary_win)
api.nvim_win_set_buf(ordinary_win, buf)
api.nvim_buf_delete(other_buf, { force = true })
api.nvim_buf_set_lines(buf, 0, -1, false, { "working" })
vim.bo[buf].modified = false
ordinary()
print("PASS: gf preserves unsaved formatting, cursor and undo; reuses hidden buffers; protects other modified files with nohidden")

-- With no reusable normal window, gf creates one and must shed inherited options.
vim.wo[ordinary_win].winfixbuf = true
view = open("DiffviewOpen", 2)
for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
  if api.nvim_win_get_buf(win) == buf then
    api.nvim_set_current_win(win)
    vim.fn.maparg("gf", "n", false, true).callback()
    break
  end
end
settle()
local new_tab = api.nvim_get_current_tabpage()
assert(new_tab ~= ordinary_tab and new_tab ~= view.tabpage and not tools.in_review(), vim.inspect({
  new_tab = new_tab, ordinary = ordinary_tab, review = view.tabpage, in_review = tools.in_review(),
  diff = vim.wo.diff, name = api.nvim_buf_get_name(0),
}))
assert(vim.wo.spell and not vim.wo.diff, "gf's new ordinary window must restore spell and shed diff options")
assert(not vim.wo.winhighlight:find("UserDiffview", 1, true), "No inherited review palette")
api.nvim_set_current_tabpage(view.tabpage)
vim.cmd.DiffviewClose(); settle()
if api.nvim_tabpage_is_valid(new_tab) then api.nvim_set_current_tabpage(new_tab); vim.cmd.tabclose() end
api.nvim_set_current_tabpage(ordinary_tab)
vim.wo[ordinary_win].winfixbuf = false
ordinary()
vim.wo[ordinary_win].spell = false
view = open("DiffviewOpen", 2)
quiet(2)
vim.cmd.DiffviewClose(); settle()
assert(not vim.wo[ordinary_win].spell, "An originally disabled spellcheck must stay disabled")
vim.wo[ordinary_win].spell = true
print("PASS: gf's new-window fallback sheds review options; disabled spellcheck stays disabled")

-- The actual dd mapping must toggle user intent, not the temporary review masks.
local function toggle_diagnostics()
  vim.fn.maparg(" dd", "n", false, true).callback()
end
view = open("DiffviewOpen", 2)
toggle_diagnostics() -- off inside Diffview
quiet(2)
api.nvim_set_current_tabpage(ordinary_tab); settle()
assert(not vim.diagnostic.is_enabled({ bufnr = buf, ns_id = visible }), "Leaving review must keep the user's global off choice")
api.nvim_set_current_tabpage(view.tabpage); settle()
toggle_diagnostics() -- on inside Diffview
quiet(2)
api.nvim_set_current_tabpage(ordinary_tab); settle()
assert(vim.diagnostic.is_enabled({ bufnr = buf, ns_id = visible }), "User on choice must resume diagnostics outside review")
toggle_diagnostics() -- off in ordinary tab while history buffers are still muted
assert(not vim.diagnostic.is_enabled({ bufnr = buf, ns_id = visible }), "Background review masks must not turn dd into enable-all")
api.nvim_set_current_tabpage(view.tabpage); settle(); quiet(2)
vim.cmd.DiffviewClose(); settle()
assert(not vim.diagnostic.is_enabled({ bufnr = buf, ns_id = visible }), "Closing review must preserve global off")
toggle_diagnostics()
assert(vim.diagnostic.is_enabled({ bufnr = buf, ns_id = visible }))
-- Like the previous global toggle, explicitly enabling all clears buffer masks.
vim.diagnostic.enable(false, { bufnr = buf, ns_id = disabled })
ordinary()
print("PASS: dd stays quiet inside review; tab return, background views and close preserve the user's global diagnostics choice")

-- Previously buffer-disabled diagnostics must never be enabled on detach.
vim.diagnostic.enable(false, { bufnr = buf })
view = open("DiffviewOpen", 2)
quiet(2)
vim.cmd.DiffviewClose(); settle()
assert(not vim.diagnostic.is_enabled({ bufnr = buf }))
vim.diagnostic.enable(true, { bufnr = buf })
vim.diagnostic.enable(false, { bufnr = buf, ns_id = disabled })
view = open("DiffviewFileHistory %", 2)
quiet(2)
vim.cmd.DiffviewClose(); settle(); ordinary()
print("PASS: history panes are quiet; initially disabled diagnostics remain disabled")

-- A real unmerged index exercises Diffview's editable RESULT and scratch preview.
local entries = {}
for stage, source in ipairs({ "base", "ours", "theirs" }) do
  local hash = git({ "hash-object", "-w", "--stdin" }, source .. "\n")
  entries[#entries + 1] = "100644 " .. hash .. " " .. stage .. "\tfile.txt\n"
end
git({ "update-index", "--force-remove", "file.txt" })
git({ "update-index", "--index-info" }, table.concat(entries))
vim.fn.writefile({ "<<<<<<< ours", "ours", "||||||| base", "base", "=======", "theirs", ">>>>>>> theirs" }, path)
vim.cmd("edit!")
view = open("DiffviewOpen", 3)
quiet(3)
vim.cmd.DiffviewClose(); settle(); ordinary()
require("merge_preview").open()
local panels = 0
for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
  local b = api.nvim_win_get_buf(win)
  if api.nvim_buf_get_name(b):match("^merge%-preview://") then
    panels = panels + 1
    assert(tools.in_review(b) and not vim.wo[win].spell)
    api.nvim_win_call(win, function() code.format_file(); code.fix_file() end)
    assert(not code.is_running(b))
  end
end
assert(panels == 3, "Isolated merge preview must have three quiet panes")
vim.fn.maparg("q", "n", false, true).callback()
settle(); ordinary()
print("PASS: conflicted Diffview and isolated merge RESULT/sides stay quiet; normal editor restored")
vim.fn.delete(directory, "rf")
assert(vim.v.errmsg == "", vim.v.errmsg)
print("All review-mode regression checks passed")
