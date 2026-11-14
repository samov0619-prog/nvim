-- Run: nvim -n --headless -u NONE -i NONE -l tests/git-link.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.o.hidden = true
local link = require("config.git-link")
local system = vim.system
local raw = "git@github.com:team/project.git"
local remote_name = "origin"
local commands = {}
local ssh_failure = false
local upstream_commit, revision_fixture
local upstream_available, detached, no_remote = true, false, false
-- Real local Git reads by default; remote/SSH configuration and explicitly
-- marked revision scenarios are fixtures. No network,
-- checkout changes, fixture commits, or interaction with the real clipboard.
vim.system = function(command, opts)
  commands[#commands + 1] = command
  if command[1] == "ssh" then
    assert(#command == 7 and vim.deep_equal(vim.list_slice(command, 1, 6),
      { "ssh", "-G", "-T", "-o", "CanonicalizeHostname=no", "--" }))
    if ssh_failure then
      return { wait = function() return { code = 255, stdout = "", stderr = "Invalid SSH configuration" } end }
    end
    local host = command[7]:gsub("^.*@", "")
    if host == "github.com-samov" then host = "github.com" end
    return { wait = function() return { code = 0, stdout = "host alias\nhostname " .. host .. "\n", stderr = "" } end }
  end
  assert(opts.env.GIT_NO_LAZY_FETCH == "1", "Git reads must never lazily fetch missing objects")
  local function response(code, stdout)
    return { wait = function() return { code = code, stdout = stdout or "", stderr = "fixture failure" } end }
  end
  if command[4] == "symbolic-ref" and detached then return response(1) end
  if command[4] == "config" and no_remote then return response(1) end
  if command[4] == "rev-parse" and command[6] == "@{upstream}^{commit}" then
    if not upstream_available then return response(128) end
    return response(0, (revision_fixture and revision_fixture.upstream or upstream_commit) .. "\n")
  end
  if revision_fixture then
    if command[4] == "rev-parse" and command[6] == "HEAD" then return response(0, revision_fixture.head .. "\n") end
    if command[4] == "merge-base" then
      assert(command[5] == revision_fixture.head and command[6] == revision_fixture.upstream)
      if revision_fixture.unrelated then return response(1) end
      return response(0, revision_fixture.upstream .. "\n")
    end
    if command[4] == "show" then
      assert(command[5]:sub(1, 41) == revision_fixture.upstream .. ":")
      if revision_fixture.missing_file then return response(128) end
      return response(0, revision_fixture.blob)
    end
  end
  local value
  if command[4] == "config" then value = remote_name end
  if command[4] == "remote" then
    assert(command[5] == "get-url" and command[6] == remote_name)
    value = raw
  end
  if value then return { wait = function() return { code = 0, stdout = value .. "\n", stderr = "" } end } end
  return system(command, opts)
end
vim.env.GLBPATT = nil
local file = root .. "/lua/config/mapping.lua"
local commit = system({ "git", "-C", root, "rev-parse", "HEAD" }, { text = true }):wait().stdout:gsub("\n$", "")
upstream_commit = commit
local source = system({ "git", "-C", root, "show", commit .. ":lua/config/mapping.lua" }, { text = true }):wait()
assert(source.code == 0)
local published = vim.split(source.stdout:gsub("\n$", ""), "\n", { plain = true })
local function url(first, last) return link.url(file, first, last, published) end
local github = "https://github.com/team/project/blob/" .. commit .. "/lua/config/mapping.lua"
assert(url(3) == "[mapping.lua:3](" .. github .. "#L3)")
assert(url(5, 2) == "[mapping.lua:2-5](" .. github .. "#L2-L5)")
assert(url(3, 3) == "[mapping.lua:3](" .. github .. "#L3)")
assert(url() == "[mapping.lua](" .. github .. ")")
raw = "git@github.com-samov:team/project.git"
assert(url(15) == "[mapping.lua:15](" .. github .. "#L15)", "SCP-style SSH aliases must use the configured HostName")
raw = "ssh://git@github.com-samov:2222/team/project.git"
assert(url(15) == "[mapping.lua:15](" .. github .. "#L15)", "SSH URL aliases must use the configured HostName")
ssh_failure = true
local ok, err = pcall(url, 15)
assert(not ok and err:find("Invalid SSH configuration", 1, true), "SSH configuration errors must be reported")
ssh_failure = false
raw = "https://github.com-samov/team/project.git"
assert(not pcall(url, 15), "HTTP hosts must not be resolved through SSH configuration")

remote_name = "upstream"
raw = "https://user:password@gitlab.com/group/nested/project.git"
local gitlab = "https://gitlab.com/group/nested/project/-/blob/" .. commit .. "/lua/config/mapping.lua"
assert(url(2, 5) == "[mapping.lua:2-5](" .. gitlab .. "#L2-5)")
raw = "ssh://git@gitlab.com:2222/group/nested/project.git"
assert(url(2) == "[mapping.lua:2](" .. gitlab .. "#L2)")

raw = "ssh://git@code.example.com:2222/group/project.git"
assert(not pcall(url, 2), "Unknown hosts must not silently generate GitHub URLs")
vim.env.GLBPATT = "code%.example%.com"
local private = "https://code.example.com/group/project/-/blob/" .. commit .. "/lua/config/mapping.lua"
assert(url(2, 5) == "[mapping.lua:2-5](" .. private .. "#L2-5)")
raw = "https://user:password@code.example.com:8443/group/project.git"
assert(url(2) == "[mapping.lua:2](https://code.example.com:8443/group/project/-/blob/" .. commit
  .. "/lua/config/mapping.lua#L2)")
raw = "/local/repository"
assert(not pcall(url, 2), "Local-only remotes have no browser URL")

-- URL escaping coverage with a synthetic Git path; remaining reads stay real.
local integration_system = vim.system
local fixture_path = "dir/a #?%(тест).lua"
vim.system = function(command, opts)
  if command[4] == "ls-files" then
    assert(command[9] == ":(literal)mapping.lua")
    return { wait = function() return { code = 0, stdout = fixture_path .. "\0", stderr = "" } end }
  end
  if command[4] == "show" then
    return { wait = function() return { code = 0, stdout = "published\n", stderr = "" } end }
  end
  return integration_system(command, opts)
end
raw = "git@github.com:team/project.git"
vim.env.GLBPATT = nil
assert(link.url(file, 1, nil, { "published" }) == "[a #?%(тест).lua:1](https://github.com/team/project/blob/" .. commit
  .. "/dir/a%20%23%3F%25%28%D1%82%D0%B5%D1%81%D1%82%29.lua#L1)")
fixture_path = "dir/a[b]_`*.lua"
assert(link.url(file, 1, nil, { "published" }) == "[a\\[b\\]\\_\\`\\*.lua:1](https://github.com/team/project/blob/" .. commit
  .. "/dir/a%5Bb%5D_%60%2A.lua#L1)", "Markdown syntax in filenames must be escaped")
vim.system = integration_system

local copied, notices
vim.fn.setreg = function(register, value)
  assert(register == "+")
  copied = value
end
vim.notify = function(message, level) notices = { message, level } end
dofile(root .. "/lua/config/mapping.lua")
vim.cmd.edit(vim.fn.fnameescape(file))
vim.api.nvim_win_set_cursor(0, { 3, 0 })
vim.fn.maparg("<leader>gy", "n", false, true).callback()
assert(copied == "[mapping.lua:3](" .. github .. "#L3)")

vim.cmd.normal({ "vj", bang = true })
vim.fn.maparg("<leader>gy", "x", false, true).callback()
assert(copied == "[mapping.lua:3-4](" .. github .. "#L3-L4)", "Visual mapping must use the active selection")
vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
vim.api.nvim_win_set_cursor(0, { 4, 0 })
vim.cmd.normal({ "vk", bang = true })
vim.fn.maparg("<leader>gy", "x", false, true).callback()
assert(copied == "[mapping.lua:3-4](" .. github .. "#L3-L4)", "Backward visual selection must be sorted")
vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)

-- Real Git snapshot + unsaved buffer edits: R1 must map exact text, not just
-- copy current coordinates or save the buffer to obtain blame input.
local init = root .. "/init.lua"
local init_source = system({ "git", "-C", root, "show", commit .. ":init.lua" }, { text = true }):wait()
assert(init_source.code == 0)
local init_lines = vim.split(init_source.stdout:gsub("\n$", ""), "\n", { plain = true })
assert(#init_lines >= 3)
local init_github = "https://github.com/team/project/blob/" .. commit .. "/init.lua"
vim.cmd.edit(vim.fn.fnameescape(init))
local function set_lines(lines, row)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, { row or 1, 0 })
end
local function refused(fragment, visual)
  local before = copied
  link.copy(visual)
  assert(copied == before, "Refusal must preserve the clipboard")
  assert(notices[2] == vim.log.levels.WARN and notices[1]:find(fragment, 1, true), vim.inspect(notices))
end
local inserted = vim.list_extend({ "-- local-only insertion" }, vim.deepcopy(init_lines))
set_lines(inserted, 3)
link.copy()
assert(copied == "[init.lua:2](" .. init_github .. "#L2)", "Unsaved insertion must shift links to published coordinates")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
refused("local changes")
vim.cmd.normal({ "vj", bang = true })
refused("local changes", true)
vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
local deleted = vim.deepcopy(init_lines)
table.remove(deleted, 1)
set_lines(deleted)
link.copy()
assert(copied == "[init.lua:2](" .. init_github .. "#L2)", "Unsaved deletion must shift links in the other direction")
local replaced = vim.deepcopy(init_lines)
replaced[1] = "-- local-only replacement"
set_lines(replaced)
refused("local changes")
local trailing = vim.list_extend(vim.deepcopy(init_lines), { "-- local-only trailing insertion" })
set_lines(trailing)
link.copy()
assert(copied == "[init.lua:1](" .. init_github .. "#L1)", "Edits after a selection must not prevent copying it")

-- R2: explicit revision/blob fixtures model HEAD ahead of an upstream snapshot.
-- Native diff, mapping callbacks and clipboard refusal are still exercised.
revision_fixture = {
  head = string.rep("a", 40), upstream = string.rep("b", 40),
  blob = "published first\npublished second\npublished third\n",
}
local published_github = "https://github.com/team/project/blob/" .. revision_fixture.upstream .. "/init.lua"
set_lines({ "committed but not pushed", "published first", "published second", "published third" }, 2)
link.copy()
assert(copied == "[init.lua:1](" .. published_github .. "#L1)", "Unchanged text must link to upstream, not unpublished HEAD")
vim.cmd.normal({ "vj", bang = true })
link.copy(true)
assert(copied == "[init.lua:1-2](" .. published_github .. "#L1-L2)")
vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
refused("local changes")

set_lines({ "published first", "published third" })
vim.cmd.normal({ "vj", bang = true })
refused("not contiguous", true)
vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
link.copy()
assert(copied == "[init.lua:3](" .. published_github .. "#L3)", "A single line after a deletion is still publishable")
set_lines({ "published first", "published second", "published third" })
upstream_available = false
refused("Upstream revision is unavailable")
upstream_available = true
no_remote = true
refused("No remote upstream")
no_remote = false
local previous_remote = remote_name
remote_name = "."
refused("No remote upstream")
remote_name = previous_remote
detached = true
refused("No remote upstream")
detached = false
revision_fixture.unrelated = true
refused("no available common ancestor")
revision_fixture.unrelated = false
revision_fixture.missing_file = true
refused("File is not present")
revision_fixture.missing_file = false
revision_fixture.blob = ""
set_lines({ "" })
refused("local changes")
revision_fixture = nil

local previous = copied
vim.cmd.enew()
link.copy()
assert(copied == previous and notices[2] == vim.log.levels.WARN)
vim.api.nvim_buf_set_name(0, root .. "/not-tracked-git-link-test.lua")
link.copy()
assert(copied == previous and notices[2] == vim.log.levels.WARN and notices[1]:find("not tracked", 1, true))
vim.bo.buftype = "nofile"
link.copy()
assert(copied == previous and notices[2] == vim.log.levels.WARN)

local allowed = { ["ls-files"] = true, ["rev-parse"] = true, show = true, ["merge-base"] = true,
  ["symbolic-ref"] = true, config = true, remote = true }
for _, command in ipairs(commands) do
  assert(command[1] == "ssh" or (command[1] == "git" and command[2] == "-C" and allowed[command[4]]))
end
print("PASS: unconditional Markdown labels, GitHub/GitLab URLs, SSH aliases/HTTPS remotes, escaping,")
print("normal/visual mappings, upstream revisions, unsaved edits, safe refusals, and local-only Git commands")
