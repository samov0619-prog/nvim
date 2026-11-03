-- Run: nvim -n --headless -u NONE -i NONE -l tests/code-rust.lua
-- Deterministic subprocess fixtures; real-tool acceptance is in doc/code-rust.md.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
for _, plugin in ipairs({ "nvim-lspconfig", "conform.nvim", "nvim-lint" }) do
  vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/" .. plugin)
end
vim.o.hidden, vim.o.swapfile, vim.o.backup, vim.o.writebackup = true, false, false, false
local api = vim.api
local directory = vim.fn.tempname()
local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
end
local notices = {}
vim.notify = function(message) notices[#notices + 1] = tostring(message) end
local function wait(predicate, label) assert(vim.wait(3000, predicate, 10), label .. vim.inspect(notices)) end
local function open(path)
  write(path, { "fn main(){let value=0;}" })
  vim.cmd.edit(vim.fn.fnameescape(path))
  vim.bo.filetype = "rust"
  return api.nvim_get_current_buf()
end
local function text(buf) return table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n") end
local function snapshot(buf)
  local tick, filename = api.nvim_buf_get_changedtick(buf), api.nvim_buf_get_name(buf)
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  return { bufnr = buf, filename = filename, tick = tick, lines = lines, eol = true,
    source = table.concat(lines, "\n") .. "\n", current = function() return true end }
end

local bin = directory .. "/toolchain/bin"
vim.fn.mkdir(bin, "p")
for _, name in ipairs({ "cargo", "rustfmt", "rust-analyzer" }) do
  assert(vim.uv.fs_symlink(vim.v.progpath, bin .. "/" .. name))
end
local old_path = vim.env.PATH
local mason = vim.fn.stdpath("data") .. "/mason/bin"
vim.env.PATH = mason .. ":" .. bin .. ":" .. old_path
local metadata, calls, delay, killed = {}, {}, 15, 0
local system = vim.system
vim.system = function(command, opts, callback)
  calls[#calls + 1] = { command = command, opts = opts }
  assert(not opts.env.PATH:find(mason, 1, true), "No Rust subprocess may inherit Mason's PATH")
  if command[1] == bin .. "/cargo" then
    assert(vim.deep_equal(vim.list_slice(command, 2, 7), {
      "metadata", "--offline", "--no-deps", "--format-version", "1", "--manifest-path",
    }), "Metadata only; no build, clippy or fix subprocess")
    local result = vim.deepcopy(metadata[command[8]])
    vim.defer_fn(function()
      callback(result and { code = 0, stdout = vim.json.encode(result), stderr = "" }
        or { code = 1, stdout = "", stderr = "fixture metadata failure" })
    end, 10)
  else
    assert(command[1] == bin .. "/rustfmt", vim.inspect(command))
    assert(vim.tbl_contains(command, "--emit=stdout"))
    vim.defer_fn(function()
      -- Reply even after kill to exercise the executor's late-result guard.
      callback({ code = 0, signal = 0, stdout = opts.stdin:gsub("value=0", "value = 0"), stderr = "" })
    end, delay)
  end
  return { kill = function() killed = killed + 1 end }
end

package.loaded.lazydev = { setup = function() end }
local enable, enabled = vim.lsp.enable, nil
vim.lsp.enable = function(names) enabled = names end
dofile(root .. "/lua/plugins/nvim-lspconfig.lua")[1].config()
vim.lsp.enable = enable
assert(vim.tbl_contains(enabled, "rust_analyzer"))
require("conform.log").set_handler(function() end)
dofile(root .. "/lua/plugins/conform-nvim.lua")[1].config()
local tools, rust = require("config.code-tools"), require("config.code-rust")
local code, format, checks = require("config.code"), require("config.code-format"), require("config.code-checks")

local workspace = directory .. "/workspace"
local crate = workspace .. "/crates/app"
write(workspace .. "/Cargo.toml", { '[workspace]', 'members = ["crates/app"]',
  '[workspace.package]', 'edition = "2024"' })
write(crate .. "/Cargo.toml", { '[package]', 'name = "app"', 'edition.workspace = true' })
write(workspace .. "/rustfmt.toml", { "max_width = 88" })
write(workspace .. "/biome.json", { "{}" })
metadata[crate .. "/Cargo.toml"] = { workspace_root = workspace, packages = {
  { manifest_path = crate .. "/Cargo.toml", edition = "2024" },
} }
local buf = open(crate .. "/src/main.rs")
local ctx = tools.resolve(buf)
assert(ctx.profile == "rust" and ctx.cargo.pending and ctx.formatter.error)
local count = #calls
tools.resolve(buf)
assert(#calls == count, "Pending metadata requests must be shared")
wait(function() return not tools.resolve(buf).cargo.pending end, "Load workspace metadata")
ctx = tools.resolve(buf)
assert(ctx.boundary == workspace and ctx.formatter.cmd == bin .. "/rustfmt")
assert(ctx.formatter.config == workspace .. "/rustfmt.toml")
assert(vim.tbl_contains(ctx.formatter.args, "--edition=2024"))
assert(next(ctx.lsp) == nil and #ctx.linters == 0 and not tools.format_filetypes.rust)
local configured, lsp = require("conform").list_formatters_to_run(buf)
assert(#configured == 1 and configured[1].name == "rustfmt" and not lsp)
print("PASS: async cached Cargo workspace/edition; Rust is isolated from Biome, Mason and nvim-lint")

local diagnostics
checks.format(ctx, snapshot(buf), function(result) diagnostics = result end)
wait(function() return diagnostics end, "Format diagnostics")
assert(#diagnostics == 1 and diagnostics[1].source == "rustfmt" and diagnostics[1].code == "format")
assert(not text(buf):find("value = 0", 1, true), "Check must not edit the buffer")
local check_call = calls[#calls]
code.format_file()
wait(function() return not code.is_running(buf) end, "Format Rust")
assert(text(buf):find("value = 0", 1, true))
local format_call = calls[#calls]
assert(vim.deep_equal(check_call.command, format_call.command))
assert(check_call.opts.cwd == format_call.opts.cwd and vim.deep_equal(check_call.opts.env, format_call.opts.env))
assert(vim.fn.readfile(ctx.filename)[1]:find("value=0", 1, true), "Formatting must not write the file")
print("PASS: checks and Conform use identical rustfmt command, environment and project settings")

write(crate .. "/.rustfmt.toml", { "max_width = 100" })
assert(tools.resolve(buf).formatter.config == crate .. "/.rustfmt.toml", "Nearer rustfmt config wins")
metadata[crate .. "/Cargo.toml"].packages[1].edition = "2021"
write(workspace .. "/Cargo.toml", { '[workspace]', 'members = ["crates/app"]',
  '[workspace.package]', 'edition = "2021"', '# changed inherited edition' })
assert(tools.resolve(buf).cargo.pending)
wait(function() return not tools.resolve(buf).cargo.pending end, "Reload metadata after workspace change")
assert(vim.tbl_contains(tools.resolve(buf).formatter.args, "--edition=2021"))

local nested = crate .. "/nested"
write(nested .. "/Cargo.toml", { '[package]', 'name = "nested"', 'edition = "2018"', '[workspace]' })
metadata[nested .. "/Cargo.toml"] = { workspace_root = nested, packages = {
  { manifest_path = nested .. "/Cargo.toml", edition = "2018" },
} }
local nested_buf = open(nested .. "/src/lib.rs")
wait(function() return not tools.resolve(nested_buf).cargo.pending end, "Nested crate metadata")
assert(tools.resolve(nested_buf).boundary == nested)
assert(vim.tbl_contains(tools.resolve(nested_buf).formatter.args, "--edition=2018"))
print("PASS: nearer rustfmt config, workspace invalidation and independent nested crate")

-- package.workspace can name a workspace outside the crate's ancestor chain.
local external = directory .. "/external"
write(external .. "/Cargo.toml", { '[package]', 'name = "external"', 'workspace = "../workspace"' })
metadata[external .. "/Cargo.toml"] = { workspace_root = workspace, packages = {
  { manifest_path = external .. "/Cargo.toml", edition = "2024" },
} }
local external_buf = open(external .. "/src/lib.rs")
wait(function() return not tools.resolve(external_buf).cargo.pending end, "Explicit package.workspace")
ctx = tools.resolve(external_buf)
assert(ctx.boundary == workspace and ctx.formatter.config == workspace .. "/rustfmt.toml")
assert(vim.tbl_contains(ctx.formatter.args, "--edition=2024"))
assert(not vim.tbl_contains(ctx.dirs, directory), "Do not scan unrelated parents between crate and workspace")
api.nvim_set_current_buf(nested_buf)
print("PASS: Cargo-reported external workspace and its formatting settings")

local racing = directory .. "/racing"
write(racing .. "/Cargo.toml", { '[package]', 'name = "racing"', 'edition = "2018"' })
metadata[racing .. "/Cargo.toml"] = { workspace_root = racing, packages = {
  { manifest_path = racing .. "/Cargo.toml", edition = "2018" },
} }
local resolved, callbacks = nil, 0
rust.project(racing, function(project) resolved, callbacks = project, callbacks + 1 end)
write(racing .. "/Cargo.toml", { '[package]', 'name = "racing"', 'edition = "2024"', '# changed during metadata' })
metadata[racing .. "/Cargo.toml"].packages[1].edition = "2024"
wait(function() return resolved end, "Restart metadata after a concurrent manifest change")
assert(callbacks == 1 and resolved.edition == "2024")

local timeout = directory .. "/timeout"
write(timeout .. "/Cargo.toml", { '[package]', 'name = "timeout"' })
metadata[timeout .. "/Cargo.toml"] = { workspace_root = timeout, packages = {
  { manifest_path = timeout .. "/Cargo.toml", edition = "2021" },
} }
local defer, expire = vim.defer_fn, nil
vim.defer_fn = function(callback, ms)
  if ms == 5000 then expire = callback end
  return defer(callback, ms)
end
resolved, callbacks = nil, 0
rust.project(timeout, function(project) resolved, callbacks = project, callbacks + 1 end)
assert(expire)
expire()
vim.defer_fn = defer
wait(function() return resolved end, "Metadata deadline")
assert(resolved.error:find("timed out", 1, true))
vim.wait(40, function() return false end)
assert(callbacks == 1 and resolved.error, "Late metadata must not override a timeout")
print("PASS: concurrent manifest edits restart metadata; metadata deadline ignores late replies")

delay = 120
code.format_file()
api.nvim_buf_set_lines(nested_buf, 0, -1, false, { "new user edits" })
wait(function() return not code.is_running(nested_buf) end, "Reject stale Rust formatting")
assert(text(nested_buf) == "new user edits")
local completed, failure
format.run(snapshot(nested_buf), { apply = true, timeout_ms = 20 }, function(err)
  completed, failure = true, err
end)
wait(function() return completed end, "Rust formatter timeout")
assert(failure:find("timed out", 1, true) and killed > 0)
local cancel = format.run(snapshot(nested_buf), { apply = true }, function() error("Cancelled callback") end)
cancel()
vim.wait(160, function() return false end)
assert(text(nested_buf) == "new user edits")
print("PASS: Rust formatting preserves cancellation, deadlines and changedtick protection")

delay = 15
local config = vim.lsp.config.rust_analyzer
local settings = config.settings["rust-analyzer"]
assert(settings.check.command == "clippy" and settings.checkOnSave and settings.diagnostics.enable)
assert(settings.cargo.buildScripts.enable and settings.procMacro.enable)
assert(not settings.lens.run.enable and not settings.lens.debug.enable and not settings.lens.updateTest.enable)
assert(not config.handlers or not config.handlers["textDocument/publishDiagnostics"])
local init = { capabilities = {} }
config.before_init(init, config)
assert(init.initializationOptions == settings)
assert(not vim.lsp.commands["rust-analyzer.runSingle"])
local start = vim.lsp.rpc.start
vim.lsp.rpc.start = function(command, _, opts)
  assert(vim.deep_equal(command, { bin .. "/rust-analyzer" }), vim.inspect(command))
  assert(opts.cwd == workspace)
  assert(opts.env.PATH == rust.environment().PATH)
  return {}
end
config.cmd({}, { root_dir = workspace })
vim.lsp.rpc.start = start
local selected_root
config.root_dir(buf, function(path) selected_root = path end)
assert(selected_root == workspace)
local client = { id = 12345, name = "rust_analyzer", offset_encoding = "utf-8", config = config,
  supports_method = function() return true end,
  request = function(_, method, params, callback)
    assert(method == "textDocument/codeAction" and params.context.only[1] == "source.fixAll")
    vim.schedule(function() callback(nil, {}) end)
    return true, 1
  end,
}
local get_clients = vim.lsp.get_clients
vim.lsp.get_clients = function() return { client } end
code.fix_file()
wait(function() return not code.is_running(nested_buf) end, "Rust fix without fixAll")
assert(table.concat(notices, "\n"):find("use <leader>lca", 1, true))
local preview = vim.lsp.util.open_floating_preview
local expanded = false
vim.lsp.util.open_floating_preview = function(lines, ft)
  assert(ft == "rust" and lines[1] == "expanded macro")
  expanded = true
end
client.request = function(_, method, params, callback)
  assert(method == "rust-analyzer/expandMacro" and params.textDocument.uri == vim.uri_from_bufnr(nested_buf))
  callback(nil, { name = "fixture!", expansion = "expanded macro" })
end
config.on_attach(client, nested_buf)
vim.cmd.LspExpandMacro()
assert(expanded)
vim.lsp.util.open_floating_preview = preview
local cargo_home = vim.env.CARGO_HOME
vim.env.CARGO_HOME = directory .. "/cargo-home"
client.config = { root_dir = workspace }
assert(rust.library_root(vim.env.CARGO_HOME .. "/registry/src/fixture/src/lib.rs") == workspace)
assert(rust.library_root("/nix/store/fixture/lib/rustlib/src/rust/library/core/src/lib.rs") == workspace)
vim.env.CARGO_HOME = cargo_home
vim.lsp.get_clients = get_clients
print("PASS: toolchain LSP settings/root, macro preview, dependency source reuse and honest fixAll behavior")

local failed = directory .. "/failed"
write(failed .. "/Cargo.toml", { '[package]', 'name = "failed"' })
local failed_buf = open(failed .. "/src/lib.rs")
wait(function() return not tools.resolve(failed_buf).cargo.pending end, "Failed metadata")
assert(tools.resolve(failed_buf).formatter.error:find("metadata failed", 1, true))
count = #calls
code.format_file()
assert(not code.is_running(failed_buf) and #calls == count, "Never guess a crate's edition on metadata failure")

local standalone = open(directory .. "/single.rs")
assert(tools.resolve(standalone).cargo.standalone and tools.resolve(standalone).boundary == directory)
vim.env.PATH = mason
assert(rust.executable("rustfmt") == nil)
assert(tools.resolve(standalone).formatter.error:find("rustfmt is unavailable", 1, true))
configured, lsp = require("conform").list_formatters_to_run(standalone)
assert(#configured == 0 and not lsp, "Missing CLI must never activate Rust LSP formatting")
vim.env.PATH = bin .. ":" .. old_path
local python = directory .. "/python"
write(python .. "/pyproject.toml", { "[project]" })
write(python .. "/.venv/bin/ruff", { "#!/bin/sh", "exit 0" })
vim.fn.setfperm(python .. "/.venv/bin/ruff", "rwxr-xr-x")
local pybuf = open(python .. "/example.py")
vim.bo[pybuf].filetype = "python"
ctx = tools.resolve(pybuf)
assert(ctx.profile == "python" and ctx.formatter.id == "ruff_format" and ctx.linter.id == "ruff")
assert(ctx.formatter.cmd == python .. "/.venv/bin/ruff")
print("PASS: missing metadata/toolchain cannot silently fall back; standalone Rust and Python profiles")

-- Exercise the actual scheduler, not only the check function in isolation.
vim.bo[pybuf].filetype = "text"
dofile(root .. "/lua/plugins/nvim-lint.lua")[1].config()
api.nvim_set_current_buf(standalone)
local ns = require("lint").get_namespace("rustfmt")
require("config.code-diagnostics").refresh(standalone, true)
wait(function() return #vim.diagnostic.get(standalone, { namespace = ns }) == 1 end, "Scheduled Rust format diagnostic")
assert(vim.diagnostic.get(standalone, { namespace = ns })[1].code == "format")
code.format_file()
wait(function() return not code.is_running(standalone) end, "Scheduled Rust formatting")
require("config.code-diagnostics").refresh(standalone, true)
wait(function() return #vim.diagnostic.get(standalone, { namespace = ns }) == 0 end, "Clear scheduled format diagnostic")
print("PASS: existing CodeTools scheduler publishes and clears Rust formatting diagnostics")

vim.system, vim.env.PATH = system, old_path
vim.fn.delete(directory, "rf")
vim.cmd("qa!")
