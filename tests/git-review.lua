-- Run: nvim -n --headless -u NONE -i NONE -l tests/git-review.lua
-- Provider APIs, remotes and fetch are fixtures; Diffview and local Git are real.
-- Commits/refs below belong only to the disposable fixture, never this repo.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
for _, plugin in ipairs({ "diffview.nvim", "plenary.nvim" }) do
  vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/" .. plugin)
end
vim.o.hidden, vim.o.swapfile, vim.o.backup, vim.o.writebackup = true, false, false, false
vim.o.lines, vim.o.columns = 55, 180
vim.g.mapleader = " "
local system, executable = vim.system, vim.fn.executable
local directory = vim.fn.tempname() .. " review repo"
vim.fn.mkdir(directory, "p")
local function local_git(args)
  local result = system(vim.list_extend({ "git", "-C", directory,
    "-c", "user.name=Review Fixture", "-c", "user.email=fixture@example.test" }, args), { text = true }):wait(5000)
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end
local_git({ "init", "-q" })
local file = directory .. "/file.txt"
vim.fn.writefile({ "base" }, file)
local_git({ "add", "." })
local_git({ "commit", "-qm", "fixture base" })
local base = local_git({ "rev-parse", "HEAD" })
vim.fn.writefile({ "request" }, file)
local_git({ "add", "." })
local_git({ "commit", "-qm", "fixture request" })
local tip = local_git({ "rev-parse", "HEAD" })
vim.fn.writefile({ "working" }, file)
vim.fn.writefile({ "staged" }, directory .. "/stage.txt")
local_git({ "add", "stage.txt" })
vim.cmd.cd(vim.fn.fnameescape(directory))
vim.cmd.edit(vim.fn.fnameescape(file))
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved" })
local work_buf, work_tab = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_tabpage()
vim.diagnostic.set(vim.api.nvim_create_namespace("git-review-test"), work_buf, {})
local before = { head = local_git({ "rev-parse", "HEAD" }), status = local_git({ "status", "--porcelain=v1" }),
  staged = local_git({ "diff", "--cached" }), index = vim.fn.readblob(directory .. "/.git/index") }

local notices, commands, picker, select_callback = {}, {}, nil, nil
local raw, remotes = "git@github.com:team/project.git", "origin\n"
local mode, pages, failure, missing_cli, change_tab = "github", false, nil, false, false
vim.env.GLBPATT = nil
vim.notify = function(message) notices[#notices + 1] = tostring(message) end
vim.ui.select = function(_, _, callback) select_callback = callback end
package.loaded["fzf-lua"] = { fzf_exec = function(rows, opts) picker = { rows = rows, opts = opts } end }
vim.fn.executable = function(name)
  if name == "gh" or name == "glab" then return missing_cli and 0 or 1 end
  return executable(name)
end
local function item(id)
  if mode == "github" then
    return { number = id, title = "Fix\27[31m search\nline", user = { login = "alice" },
      base = { ref = "release/next" }, head = { ref = "fork-feature" }, draft = true,
      html_url = "https://github.com/team/project/pull/" .. id,
      body = id == 2 and vim.NIL or "Description\nsecond\27[2J line" }
  end
  return { iid = id, title = "GitLab change", author = { username = "bob" }, target_branch = "release/next",
    source_branch = "fork-feature", web_url = "https://gitlab.com/team/nested/project/-/merge_requests/" .. id,
    description = "GitLab description", draft = false }
end
local fetches = 0
vim.system = function(command, opts, callback)
  commands[#commands + 1] = vim.deepcopy(command)
  local code, output, stderr = 0, nil, "fixture failure"
  if command[1] == "gh" or command[1] == "glab" then
    assert(callback and command[2] == "api" and command[3] == "--hostname")
    local endpoint = command[5]
    if mode == "github" then
      assert(command[1] == "gh" and command[4] == "github.com")
      assert(endpoint:match("^repos/team/project/pulls"))
    else
      assert(command[1] == "glab" and command[4] == "gitlab.com")
      assert(endpoint:match("^projects/team%%2Fnested%%2Fproject/merge_requests"))
    end
    if failure == "api" then code, output, stderr = 1, "", "Authentication required"
    elseif failure == "json" then output = "not JSON"
    elseif endpoint:find("?", 1, true) then
      local data = {}
      if failure ~= "empty" then
        local count = pages and endpoint:match("page=1$") and 100 or 1
        for i = 1, count do data[#data + 1] = item(pages and endpoint:match("page=2$") and 101 or i) end
      end
      output = vim.json.encode(data)
    else
      output = vim.json.encode(item(tonumber(endpoint:match("/(%d+)$"))))
    end
  elseif command[1] == "ssh" then
    assert(command[2] == "-G", "SSH must not connect")
    output = "hostname " .. (mode == "github" and "github.com" or "gitlab.com") .. "\n"
  elseif command[1] == "git" then
    if command[4] == "remote" then
      output = command[5] == "get-url" and raw or remotes
    elseif command[4] == "fetch" then
      fetches = fetches + 1
      assert(opts.env.GIT_TERMINAL_PROMPT == "0" and opts.timeout == 60000)
      for _, flag in ipairs({ "--atomic", "--no-tags", "--no-prune", "--no-prune-tags", "--no-write-fetch-head", "--no-recurse-submodules",
        "--no-auto-maintenance", "--refmap=" }) do assert(vim.tbl_contains(command, flag), flag) end
      assert(command[13] == "--" and command[14] == "origin", vim.inspect(command))
      local target, base_ref = command[15]:match("^%+refs/heads/(.-):(refs/nvim%-review/.+/base)$")
      local source, head_ref = command[16]:match("^%+(.-):(refs/nvim%-review/.+/head)$")
      assert(target == "release/next", "Use freshly queried target, not main or local HEAD")
      assert(source == (mode == "github" and "refs/pull/1/head" or "refs/merge-requests/1/head"))
      if failure == "fetch" then code, output = 128, ""
      else
        local_git({ "update-ref", base_ref, base })
        local_git({ "update-ref", head_ref, tip })
        output = ""
      end
      if change_tab then vim.cmd.tabnew() end
    elseif command[4] == "merge-base" and failure == "ancestor" then code, output = 1, ""
    end
  end
  if output == nil then return system(command, opts, callback) end
  local result = { code = code, stdout = output, stderr = stderr }
  if callback then vim.schedule(function() callback(result) end) end
  return { wait = function() return result end }
end
local review = require("config.git-review")
dofile(root .. "/lua/plugins/diffview-nvim.lua")[1].config()
require("diffview.config").get_config().watch_index = false
vim.cmd("runtime plugin/diffview.lua")
local function wait(predicate, label)
  assert(vim.wait(10000, predicate, 10), label .. "\n" .. vim.inspect(notices))
end
local function notice(fragment)
  for _, value in ipairs(notices) do if value:find(fragment, 1, true) then return true end end
end
local function failed(kind, fragment)
  picker, notices, failure = nil, {}, kind
  review.open()
  wait(function() return notice(fragment) end, fragment)
  assert(not picker and vim.api.nvim_get_current_tabpage() == work_tab)
  failure = nil
end
failed("api", "Authentication required")
failed("json", "Invalid JSON")
failed("empty", "No open PRs/MRs")
missing_cli = true
failed(nil, "Install gh")
missing_cli = false
raw = "https://unknown.example/team/project.git"
failed(nil, "Unknown host")
raw = "git@github.com:team/project.git"
remotes = ""
failed(nil, "no remotes")
remotes = "origin\nupstream\n"
review.open()
wait(function() return select_callback ~= nil end, "Remote selection")
select_callback(nil)
assert(not picker and fetches == 0, "Cancel remote selection without fetching")
remotes = "origin\n"

pages, picker = true, nil
-- Exercise the registered mapping, not an unregistered helper.
vim.fn.maparg("<leader>gr", "n", false, true).callback()
wait(function() return picker ~= nil end, "Paginated list")
assert(#picker.rows == 101 and picker.rows[101]:match("^101\t"), "Load every API page")
local first_picker = picker
assert(not picker.rows[1]:find("\27", 1, true) and not picker.rows[1]:find("\n", 1, true), "Sanitize title controls")
assert(picker.rows[1]:find("alice", 1, true) and picker.rows[1]:find("release/next", 1, true))
assert(picker.opts.preview({ picker.rows[1] }):find("Description\nsecond", 1, true))
assert(not picker.opts.preview({ picker.rows[1] }):find("\27", 1, true), "Sanitize preview escapes")
assert(not picker.opts.preview({ picker.rows[2] }):find("vim.NIL", 1, true), "JSON null means an empty description")
picker.opts.actions.enter({})
assert(fetches == 0, "An empty selection does not fetch")
pages = false
local function choose()
  first_picker.opts.actions.enter({ first_picker.rows[1] })
end
for _, kind in ipairs({ "fetch", "ancestor" }) do
  failure, notices = kind, {}
  choose()
  wait(function() return notice("failed:") end, "Fetch/common-ancestor error")
  assert(vim.api.nvim_get_current_tabpage() == work_tab, "Failure must not open a view")
end
failure, notices = nil, {}
choose()
local lib = require("diffview.lib")
wait(function() local v = lib.get_current_view(); return v and v.cur_entry and v.cur_entry.opened end, "Real Diffview")
local view = lib.get_current_view()
assert(vim.t.git_review_readonly, "Mark only the new review tab")
assert(view.left.commit == base and view.right.commit == tip, "Use immutable merge-base and head")
local RevType = require("diffview.vcs.rev").RevType
assert(view.left.type == RevType.COMMIT and view.right.type == RevType.COMMIT,
  "Both sides must stay historical even when tip equals local HEAD")
local snapshots = 0
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_get_name(buf):match("^diffview://") and vim.api.nvim_buf_is_loaded(buf)
      and vim.bo[buf].filetype ~= "DiffviewFiles" then
    assert(not vim.bo[buf].modifiable, "Snapshot buffers must be nonmodifiable")
    snapshots = snapshots + 1
  end
end
assert(snapshots >= 2, "Both revision buffers must be loaded")
view.panel:focus()
for _, key in ipairs({ "S", "U" }) do
  local mapping = vim.fn.maparg(key, "n", false, true)
  assert(mapping.callback, "Guard must be installed on actual file-panel mapping")
  mapping.callback()
end
assert(notice("review is read-only"))
assert(local_git({ "rev-parse", "HEAD" }) == before.head)
assert(local_git({ "status", "--porcelain=v1" }) == before.status)
assert(local_git({ "diff", "--cached" }) == before.staged)
assert(vim.deep_equal(vim.fn.readblob(directory .. "/.git/index"), before.index), "Preserve index bytes")
assert(vim.fn.readfile(file)[1] == "working" and vim.api.nvim_buf_get_lines(work_buf, 0, -1, false)[1] == "unsaved")
assert(vim.bo[work_buf].modified and vim.fn.filereadable(directory .. "/.git/FETCH_HEAD") == 0)
vim.cmd("DiffviewClose")
assert(vim.api.nvim_get_current_tabpage() == work_tab and not vim.t.git_review_readonly)
-- Ordinary Diffview keeps the documented bulk actions.
local actions, called = require("diffview.actions"), false
local stage = actions.stage_all
actions.stage_all = function() called = true end
review.index_action("stage_all")()
actions.stage_all = stage
assert(called)

-- A GitLab fork MR uses the target project's refs, including nested namespaces.
mode, raw, picker, notices = "gitlab", "https://gitlab.com/team/nested/project.git", nil, {}
review.open("origin")
wait(function() return picker ~= nil end, "GitLab MR list")
assert(picker.rows[1]:find("bob", 1, true) and picker.opts.prompt == "MR> ")
assert(picker.opts.preview({ picker.rows[1] }):find("GitLab description", 1, true))
change_tab = true
picker.opts.actions.enter({ picker.rows[1] })
wait(function() return notice("active tab changed") end, "Do not steal focus after async fetch")
assert(not lib.get_current_view())
vim.cmd.tabclose()
assert(vim.api.nvim_get_current_tabpage() == work_tab)
-- Exercise the actual FzfLua content pipeline and action dispatch too. The
-- terminal UI is replaced, but serialization, fzf filtering and Diffview are real.
change_tab = false
package.loaded["fzf-lua"] = nil
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/fzf-lua")
local fzf, core = require("fzf-lua"), require("fzf-lua.core")
fzf.setup({})
local wrap, serialized, options = core.fzf_wrap, nil, nil
core.fzf_wrap = function(command, opts)
  local result
  system({ "sh", "-c", command }, {
    text = true, env = { FZF_LUA_SERVER = vim.g.fzf_lua_server },
  }, function(value) result = value end)
  wait(function() return result ~= nil end, "FzfLua pipeline")
  assert(result.code == 0, result.stderr)
  serialized, options = result.stdout, opts
end
review.open()
wait(function() return serialized ~= nil end, "Real picker serialization")
core.fzf_wrap = wrap
local filtered = system({ "fzf", "--filter", "bob" }, { text = true, stdin = serialized }):wait(5000)
assert(filtered.code == 0 and filtered.stdout:find("GitLab change", 1, true), "Search authors through real fzf")
require("fzf-lua.actions").act({ "enter", vim.trim(filtered.stdout) }, options)
wait(function() local v = lib.get_current_view(); return v and v.cur_entry and v.cur_entry.opened end, "Real FzfLua Enter to Diffview")
assert(vim.t.git_review_readonly and lib.get_current_view().right.type == RevType.COMMIT)
vim.cmd("DiffviewClose")
vim.system, vim.fn.executable = system, executable
vim.cmd.cd(vim.fn.fnameescape(root))
vim.fn.delete(directory, "rf")
print("PASS: paginated GitHub/GitLab fixtures, real FzfLua pipeline/fzf/Enter, auth/errors/cancel, isolated fetch, real read-only Diffview and preserved work/index")
vim.cmd("qa!")
