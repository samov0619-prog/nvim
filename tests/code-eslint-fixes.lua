-- Run: nvim -n --headless -u NONE -i NONE -l tests/code-eslint-fixes.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/conform.nvim")
vim.o.hidden, vim.o.swapfile, vim.o.backup, vim.o.writebackup = true, false, false, false
require("conform.log").set_handler(function() end)
local api = vim.api
local directory = vim.fn.tempname()
local mason = vim.fn.stdpath("data") .. "/mason"
local eslint = mason .. "/packages/eslint_d/node_modules/eslint_d/node_modules/eslint"
assert(vim.uv.fs_stat(eslint), "Install eslint_d through Mason before running this test")
vim.fn.mkdir(directory .. "/.git", "p")
-- Give this test its own resolver base/daemon; never stop a user's daemon.
local local_eslint = directory .. "/node_modules/eslint"
vim.fn.mkdir(local_eslint, "p")
vim.fn.writefile(vim.fn.readfile(eslint .. "/package.json", "b"), local_eslint .. "/package.json", "b")
assert(vim.uv.fs_symlink(eslint .. "/lib", local_eslint .. "/lib", { dir = true }))
assert(vim.uv.fs_symlink(vim.fs.dirname(eslint) .. "/debug", directory .. "/node_modules/debug", { dir = true }))
vim.env.ESLINT_D_PPID = tostring(vim.fn.getpid())
vim.fn.writefile({ "{}" }, directory .. "/package.json")
vim.fn.writefile({ "{}" }, directory .. "/.prettierrc")
local trace = directory .. "/daemon.trace"
vim.fn.writefile({
  'import fs from "node:fs";',
  'const trace = ' .. vim.json.encode(trace) .. ';',
  'export default [{plugins:{regression:{rules:{delay:{create(){return {Program(){',
  'fs.appendFileSync(trace,"start\\n");',
  'Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,250);',
  'fs.appendFileSync(trace,"done\\n");',
  '}}}}}}},rules:{"regression/delay":"error","prefer-const":"error","no-undef":"error",semi:["error","always"]}}];',
}, directory .. "/eslint.config.mjs")
local notices = {}
vim.notify = function(message) notices[#notices + 1] = tostring(message) end
dofile(root .. "/lua/plugins/conform-nvim.lua")[1].config()
local code, tools = require("config.code"), require("config.code-tools")
local original = "let value=1\nmissing(value)\n"
local function contents(path)
  local file = assert(io.open(path, "rb"))
  local source = assert(file:read("*a"))
  assert(file:close())
  return source
end
local function write(path, source)
  local file = assert(io.open(path, "wb"))
  assert(file:write(source))
  assert(file:close())
end
local function text(bufnr) return table.concat(api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n") end
local function open(name, source)
  local path = directory .. "/" .. name .. ".js"
  write(path, source or original)
  vim.cmd.edit(vim.fn.fnameescape(path))
  vim.bo.filetype = "javascript"
  return api.nvim_get_current_buf(), path
end
local function wait(predicate, label)
  assert(vim.wait(10000, predicate, 5), label .. "\n" .. vim.inspect(notices))
end
local b, path = open("timeout")
local tool = tools.resolve(b).linter
assert(tool.fix_stdout and vim.tbl_contains(tool.fix_args, "--fix-to-stdout"))
assert(not vim.tbl_contains(tool.fix_args, "--fix"), "Daemon must never write the original file")
local system, defer = vim.system, vim.defer_fn
local warmup = vim.list_extend({ tool.cmd }, tool.args)
vim.list_extend(warmup, { "--format", "json", "--stdin", "--stdin-filename", path })
local response = system(warmup, { stdin = original, cwd = tool.cwd, env = tool.env, text = true }):wait(10000)
assert(response.code == 1 and response.signal == 0, vim.inspect(response))
assert(vim.json.decode(response.stdout)[1].messages[1])
vim.fn.delete(trace)

-- Wait until the real daemon is inside a slow rule before expiring its client.
local expire, started_client = nil, false
vim.defer_fn = function(callback, ms)
  if ms == 10000 and not expire then expire = callback end
  return defer(callback, ms)
end
vim.system = function(command, opts, callback)
  if vim.tbl_contains(command, "--fix-to-stdout") then
    started_client = true
    assert(not vim.tbl_contains(command, "--fix") and opts.stdin == original)
  end
  return system(command, opts, callback)
end
code.fix_file()
wait(function() return vim.fn.filereadable(trace) == 1 end, "Daemon must start executing the fix")
assert(started_client and expire)
expire()
wait(function() return not code.is_running(b) end, "Timed-out daemon client must release cx")
vim.system, vim.defer_fn = system, defer
wait(function()
  local _, count = contents(trace):gsub("done", "")
  return count >= 2
end, "Daemon must finish its dry-run passes after its client timed out")
vim.wait(100, function() return false end)
assert(contents(path) == original and text(b) == "let value = 1;\nmissing(value);")
assert(vim.bo[b].modified)
print("PASS: real eslint_d continues after timeout but cannot write the original; final formatting stays unsaved")

-- Hold a real successful reply: the daemon must not have changed the file,
-- and only the guarded editor callback may commit its returned fixes.
local pending
vim.system = function(command, opts, callback)
  if vim.tbl_contains(command, "--fix-to-stdout") then
    assert(not vim.tbl_contains(command, "--fix"))
    return system(command, opts, function(result) pending = { callback = callback, result = result } end)
  end
  return system(command, opts, callback)
end
local function fix_and_hold(name, source)
  pending = nil
  local bufnr, filename = open(name, source)
  code.fix_file()
  wait(function() return pending end, "Real daemon fix response")
  assert(pending.result.code == 0 and pending.result.signal == 0, vim.inspect(pending.result))
  assert(pending.result.stdout:find("const value", 1, true))
  assert(contents(filename) == (source or original), "Daemon wrote the original before the editor callback")
  return bufnr, filename
end
b, path = fix_and_hold("success")
local fixed = pending.result.stdout
pending.callback(pending.result)
wait(function() return not code.is_running(b) end, "Controlled fix and formatting")
assert(contents(path) == fixed and text(b) == "const value = 1;\nmissing(value);")
assert(vim.bo[b].modified, "Final Prettier formatting must remain unsaved")
print("PASS: real eslint_d returns safe partial fixes; guarded callback writes fixes before final unsaved formatting")

local bom = "\239\187\191"
b, path = fix_and_hold("bom-crlf", bom .. "let value=1\r\nmissing(value)\r\n")
fixed = pending.result.stdout
assert(fixed:sub(1, #bom) == bom and fixed:find("\r\n", 1, true), "Fix output must retain BOM and CRLF bytes")
pending.callback(pending.result)
wait(function() return not code.is_running(b) end, "BOM/CRLF fix and formatting")
assert(contents(path) == fixed and text(b) == "const value = 1;\nmissing(value);")
assert(vim.bo[b].modified and vim.bo[b].bomb and vim.bo[b].fileformat == "dos")
print("PASS: controlled fixes preserve BOM/CRLF bytes on disk; final formatting remains unsaved")

local nul_source = "let value=1 // comment\000missing(value)\n"
b, path = fix_and_hold("nul-comment", nul_source)
fixed = pending.result.stdout
assert(fixed == "const value=1; // comment\000missing(value)\n", "Fix input/output must preserve NUL bytes")
pending.callback(pending.result)
wait(function() return not code.is_running(b) end, "NUL-safe fix and formatting")
assert(contents(path) == fixed and api.nvim_buf_line_count(b) == 1)
assert(text(b) == "const value = 1; // comment\000missing(value)" and vim.bo[b].modified)
print("PASS: NUL inside a comment is preserved and cannot turn commented text into executable code")

b, path = fix_and_hold("nul-disk-change", nul_source)
local changed_source = nul_source:gsub("%z", "\n")
write(path, changed_source)
pending.callback(pending.result)
wait(function() return not code.is_running(b) end, "Byte-level external change cancellation")
assert(contents(path) == changed_source)
print("PASS: the disk guard distinguishes NUL from newline and preserves an external edit")

b, path = fix_and_hold("signalled")
pending.result.signal = 9
pending.callback(pending.result)
wait(function() return not code.is_running(b) end, "Signalled fixer cancellation and final formatting")
assert(contents(path) == original and text(b) == "let value = 1;\nmissing(value);")
assert(vim.bo[b].modified)
assert(table.concat(notices, "\n"):find("terminated by signal 9", 1, true))
print("PASS: a signalled fixer cannot commit source output, even with exit code zero")

b, path = fix_and_hold("typing")
api.nvim_buf_set_lines(b, 0, -1, false, { "// newer typing" })
pending.callback(pending.result)
wait(function() return not code.is_running(b) end, "Concurrent edit cancellation")
assert(contents(path) == original and text(b) == "// newer typing")
print("PASS: typing before the daemon reply prevents both disk writes and stale buffer edits")

b, path = fix_and_hold("disk-change")
vim.fn.writefile({ "// changed externally" }, path)
pending.callback(pending.result)
wait(function() return not code.is_running(b) end, "External file change cancellation")
assert(contents(path) == "// changed externally\n")
print("PASS: external disk changes are not overwritten by a daemon result")

b, path = fix_and_hold("renamed")
api.nvim_buf_set_name(b, directory .. "/different.js")
pending.callback(pending.result)
wait(function() return not code.is_running(b) end, "Renamed buffer cancellation")
assert(contents(path) == original and vim.fn.filereadable(directory .. "/different.js") == 0)
print("PASS: renaming the target cancels controlled application of daemon output")

vim.system = system
system({ tool.cmd, "stop" }, { cwd = tool.cwd, env = tool.env, text = true }):wait(5000)
vim.fn.delete(directory, "rf")
print("All daemon fix regression checks passed")
vim.cmd("qa!")
