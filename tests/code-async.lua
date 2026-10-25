-- Run: nvim -n --headless -u NONE -i NONE -l tests/code-async.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/conform.nvim")
vim.o.hidden, vim.o.swapfile, vim.o.backup, vim.o.writebackup = true, false, false, false
require("conform.log").set_handler(function() end)
local api = vim.api
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p")
local notices = {}
vim.notify = function(message) notices[#notices + 1] = tostring(message) end
local conform = require("conform")
local format = require("config.code-format")
local checks = require("config.code-checks")
local tools = require("config.code-tools")
local code = require("config.code")
local function wait(predicate, label)
  assert(vim.wait(6000, predicate, 10), label .. "\n" .. vim.inspect(notices))
end
local function open(name)
  local path = directory .. "/" .. name
  vim.fn.writefile({ "original" }, path)
  vim.cmd.edit(vim.fn.fnameescape(path))
  vim.bo.filetype = "review"
  return api.nvim_get_current_buf(), path
end
local function text(bufnr) return table.concat(api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n") end
local function killed(process)
  local result = process:wait(2000)
  assert(result.signal == 9 and result.code ~= 124, "Formatter was not killed by its owner: " .. vim.inspect(result))
end
local function snapshot(bufnr)
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return { bufnr = bufnr, filename = api.nvim_buf_get_name(bufnr),
    tick = api.nvim_buf_get_changedtick(bufnr), lines = lines, eol = true,
    source = table.concat(lines, "\n") .. "\n", current = function() return true end }
end
local sleep_args = { "--headless", "-u", "NONE", "-i", "NONE", "-n",
  "-c", "lua vim.uv.sleep(60000)", "-c", "qa!" }
conform.setup({ default_format_opts = { lsp_format = "fallback" },
  formatters_by_ft = { review = { "slow" } },
  formatters = {
    slow = { inherit = false, command = vim.v.progpath, args = sleep_args, stdin = true },
    file = { inherit = false, command = vim.v.progpath, stdin = false,
      args = vim.list_extend(vim.deepcopy(sleep_args), { "$FILENAME" }) },
    quick = { inherit = false, format = function(_, _, _, callback) callback(nil, { "formatted" }) end },
  },
})

-- Real subprocesses must exit on cancellation; stale checks cannot publish.
local system = vim.system
local processes, commands = {}, {}
vim.system = function(command, opts, callback)
  local process = system(command, opts, callback)
  processes[#processes + 1], commands[#commands + 1] = process, command
  return process
end
local b, path = open("cancel.txt")
local publications = 0
local cancel = checks.format({}, snapshot(b), function() publications = publications + 1 end)
assert(#processes == 1)
cancel()
killed(processes[1])
vim.wait(50, function() return false end)
assert(publications == 0 and text(b) == "original" and vim.fn.readfile(path)[1] == "original")
print("PASS: background Conform formatter is killed; cancelled check cannot publish")

conform.formatters_by_ft.review = { "file" }
cancel = checks.format({}, snapshot(b), function() publications = publications + 1 end)
local temporary = commands[#commands][#commands[#commands]]
assert(temporary ~= path and vim.fn.filereadable(temporary) == 1)
cancel()
killed(processes[#processes])
vim.wait(50, function() return false end)
assert(vim.fn.filereadable(temporary) == 0 and vim.fn.readfile(path)[1] == "original")
assert(publications == 0)
print("PASS: cancelled file formatter releases its temporary copy and preserves the original")

-- A bounded run must notify once and kill its process, even without a reply.
conform.formatters_by_ft.review = { "slow" }
local completions, error_message = 0, nil
format.run(snapshot(b), { timeout_ms = 40, apply = true }, function(err)
  completions, error_message = completions + 1, err
end)
wait(function() return completions == 1 end, "Formatter deadline")
assert(error_message:find("timed out", 1, true))
killed(processes[#processes])
assert(text(b) == "original")
vim.wait(50, function() return false end)
assert(completions == 1)
vim.system = system
print("PASS: formatter deadline kills a real process and completes exactly once")

-- Unexpected signals are failures even when libuv reports code=0 and a
-- formatter allows the corresponding numeric exit code. Never use partial text.
conform.formatters.slow.exit_codes = { 0, 137 }
vim.system = function(_, _, callback)
  vim.schedule(function() callback({ code = 0, signal = 9, stdout = "partial output\n", stderr = "" }) end)
  return { kill = function() end }
end
code.format_file()
wait(function() return not code.is_running(b) end, "Signal must release cf's lock")
assert(text(b) == "original" and vim.fn.readfile(path)[1] == "original")
assert(table.concat(notices, "\n"):find("terminated by signal 9", 1, true))
local signal_diagnostics
checks.format({}, snapshot(b), function(result) signal_diagnostics = result end)
wait(function() return signal_diagnostics end, "Signal diagnostic")
assert(#signal_diagnostics == 1 and signal_diagnostics[1].severity == vim.diagnostic.severity.ERROR)
assert(signal_diagnostics[1].message:find("signal 9", 1, true) and not signal_diagnostics[1].code)
local parsed = false
signal_diagnostics = nil
checks.linter({ id = "review", name = "review", cmd = vim.v.progpath, cwd = directory },
  { args = {}, stdin = true, parser = function() parsed = true; return {} end }, snapshot(b),
  function(result) signal_diagnostics = result end)
wait(function() return signal_diagnostics end, "Linter signal diagnostic")
assert(not parsed and signal_diagnostics[1].severity == vim.diagnostic.severity.ERROR)
conform.formatters_by_ft.review = { "file" }
code.format_file()
wait(function() return not code.is_running(b) end, "File formatter signal")
assert(text(b) == "original" and #vim.fn.glob(directory .. "/.conform.*", false, true) == 0)
vim.system = system
print("PASS: unexpected signals reject partial output, release locks, skip parsers, and clean up temp files")

-- LSP formatting is cancellable too, including late replies and cf's lock.
conform.formatters_by_ft.review = {}
local get_clients = vim.lsp.get_clients
local replies, cancelled = {}, {}
local client = { id = 9999, name = "review", offset_encoding = "utf-16", handlers = {}, commands = {} }
client.cancel_request = function(_, id) cancelled[id] = true end
client.request = function(_, method, params, callback)
  assert(method == "textDocument/formatting")
  assert(params.textDocument.uri == vim.uri_from_bufnr(b))
  replies[#replies + 1] = callback
  return true, #replies
end
vim.lsp.get_clients = function(opts)
  return opts.method == "textDocument/codeAction" and {} or { client }
end
local edits = { { range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 8 } },
  newText = "STALE FIX" } }
cancel = checks.format({}, snapshot(b), function() publications = publications + 1 end)
cancel()
assert(cancelled[1])
replies[1](nil, edits)
assert(publications == 0 and text(b) == "original")
code.format_file()
assert(code.is_running(b))
wait(function() return not code.is_running(b) end, "cf must unlock on LSP format timeout")
assert(cancelled[2])
api.nvim_buf_set_lines(b, 0, -1, false, { "new typing" })
replies[2](nil, edits)
assert(text(b) == "new typing" and not code.is_running(b))
client.request = function(_, _, _, callback) callback(nil, {}); return true, 3 end
code.format_file()
assert(not code.is_running(b), "Retry after timeout stayed locked")
local fresh_edits = { { range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
  newText = "fresh format" } }
client.request = function(_, _, _, callback) callback(nil, fresh_edits); return true, 4 end
local diagnostics
checks.format({}, snapshot(b), function(result) diagnostics = result end)
assert(#diagnostics > 0 and text(b) == "new typing", "LSP format check changed the live buffer")
code.format_file()
assert(text(b) == "fresh format" and not code.is_running(b) and vim.fn.readfile(path)[1] == "original")
vim.lsp.get_clients = get_clients
print("PASS: LSP checks cancel requests and stay read-only; cf unlocks, rejects late edits, and formats on retry")

-- Timed-out fix commands retain their edit guard until a real server reply.
local defer, format_buffer, resolve = vim.defer_fn, format.format_buffer, tools.resolve
local get_client = vim.lsp.get_client_by_id
local timers, command_reply, executions = {}, nil, 0
vim.defer_fn = function(callback) timers[#timers + 1] = callback end
format.format_buffer = function(_, callback) callback() end
tools.resolve = function() return { linters = {} } end
client.supports_method = function() return false end
client.request = function(_, method, _, callback)
  if method == "textDocument/codeAction" then
    callback(nil, { { title = "fix", kind = "source.fixAll", command = { command = "review.fix" } } },
      { client_id = client.id, bufnr = api.nvim_get_current_buf(), method = method })
  elseif method == "workspace/executeCommand" then
    executions, command_reply = executions + 1, callback
  else error(method) end
  return true, 42
end
vim.lsp.get_clients = function() return { client } end
vim.lsp.get_client_by_id = function() return client end
code.fix_file()
assert(code.is_running(b) and command_reply)
timers[1]()
assert(not code.is_running(b) and client.handlers["workspace/applyEdit"])
api.nvim_buf_set_lines(b, 0, -1, false, { "user edit" })
local response = client.handlers["workspace/applyEdit"](nil,
  { edit = { changes = { [vim.uri_from_bufnr(b)] = edits } } }, { client_id = client.id })
assert(not response.applied and text(b) == "user edit")
code.fix_file()
assert(executions == 1 and not code.is_running(b), "Retry overlapped the cancelled command")
local acknowledge_cancelled = command_reply
local other = open("other.txt")
code.fix_file()
local other_response = client.handlers["workspace/applyEdit"](nil,
  { edit = { changes = { [vim.uri_from_bufnr(other)] = edits } } }, { client_id = client.id })
assert(other_response.applied and text(other) == "STALE FIX", "Expired guard blocked another buffer")
command_reply(nil, {}, { client_id = client.id, bufnr = other, method = "workspace/executeCommand" })
assert(not code.is_running(other) and client.handlers["workspace/applyEdit"])
api.nvim_set_current_buf(b)
acknowledge_cancelled(nil, {}, { client_id = client.id, bufnr = b, method = "workspace/executeCommand" })
assert(client.handlers["workspace/applyEdit"] == nil, "Acknowledged cancellation leaked a handler")
code.fix_file()
assert(executions == 3)
command_reply(nil, {}, { client_id = client.id, bufnr = b, method = "workspace/executeCommand" })
assert(not code.is_running(b) and client.handlers["workspace/applyEdit"] == nil)
code.fix_file()
assert(executions == 4, "A successful response with LSP context blocked the next cx")
command_reply(nil, {}, { client_id = client.id, bufnr = b, method = "workspace/executeCommand" })
assert(not code.is_running(b) and client._code_tools_fix_guard == nil)
vim.defer_fn, format.format_buffer, tools.resolve = defer, format_buffer, resolve
vim.lsp.get_clients, vim.lsp.get_client_by_id = get_clients, get_client
print("PASS: timed-out commands reject late workspace edits; guards release on acknowledgement; retry is isolated")

-- A real CLI fixer timeout aborts the remaining fixers, reloads and formats.
b, path = open("fix-timeout.txt")
conform.formatters_by_ft.review = { "quick" }
local fixes, timeout = 0, nil
tools.resolve = function()
  return { linters = {
    { cmd = vim.v.progpath, name = "slow", cwd = directory, fix_args = sleep_args },
    { cmd = vim.v.progpath, name = "must not run", cwd = directory, fix_args = sleep_args },
  } }
end
vim.system = function(command, opts, callback)
  fixes, timeout = fixes + 1, opts.timeout
  return system(command, opts, callback)
end
vim.defer_fn = function(callback, ms) return defer(callback, ms == 10000 and 40 or ms) end
code.fix_file()
wait(function() return not code.is_running(b) end, "cx must unlock after CLI timeout")
vim.system, tools.resolve, vim.defer_fn = system, resolve, defer
assert(fixes == 1 and timeout == 10000)
assert(text(b) == "formatted" and vim.bo[b].modified and vim.fn.readfile(path)[1] == "original")
assert(table.concat(notices, "\n"):find("exited with code 124", 1, true))
print("PASS: CLI fixers have a real deadline; timeout aborts the chain and final formatting stays unsaved")

-- Successful file-formatting still reads the temporary output before cleanup.
conform.formatters.file.args = { "--headless", "-u", "NONE", "-i", "NONE", "-n", "-c",
  'lua vim.fn.writefile({"file formatted"}, vim.fn.argv(0)); vim.cmd("qa!")', "$FILENAME" }
conform.formatters_by_ft.review = { "file" }
code.format_file()
wait(function() return not code.is_running(b) end, "File formatter completion")
assert(text(b) == "file formatted" and vim.fn.readfile(path)[1] == "original")
assert(#vim.fn.glob(directory .. "/.conform.*", false, true) == 0, "Temporary files leaked")
print("PASS: successful file formatter reads its output, cleans up, and never writes the original")
vim.fn.delete(directory, "rf")
print("All asynchronous regression checks passed")
vim.cmd("qa!")
