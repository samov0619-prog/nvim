-- Run: nvim -n --headless -u NONE -i NONE -l tests/ts-toolchain.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
for _, plugin in ipairs({ "nvim-lspconfig", "mason.nvim" }) do
  vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/" .. plugin)
end
vim.o.swapfile, vim.o.backup, vim.o.writebackup = false, false, false
local directory = "/tmp/opencode/ts-toolchain-" .. vim.fn.getpid()
assert(not vim.uv.fs_stat(directory), "Test directory already exists")
local mason, repo = directory .. "/mason", directory .. "/repo"
local profiles = directory .. "/profiles.json"
local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({ text }, path)
end
local function object(path, value) write(path, vim.json.encode(value)) end
local function ts(path, version, server)
  object(path .. "/package.json", { name = "typescript", version = version })
  if server ~= false then write(path .. "/lib/tsserver.js", "// fixture") end
end
local function installation(name, version)
  local path = mason .. "/packages/" .. name .. "/node_modules/@vue/language-server"
  object(path .. "/package.json", { version = version, bin = { ["vue-language-server"] = "bin/server.js" } })
  write(path .. "/bin/server.js", "// fixture")
  object(path .. "/node_modules/@vue/typescript-plugin/package.json", { version = version })
  ts(mason .. "/packages/" .. name .. "/node_modules/typescript", "6.0.3")
  return path
end
local wrapper = mason .. "/packages/typescript-language-server/node_modules/typescript-language-server"
object(wrapper .. "/package.json", { version = "6.0.2", bin = { ["typescript-language-server"] = "lib/cli.mjs" } })
write(wrapper .. "/lib/cli.mjs", "// fixture")
ts(mason .. "/packages/typescript-language-server/node_modules/typescript", "6.0.3")
local legacy = installation("vue-language-server-vue2", "3.0.11")
local modern = installation("vue-language-server", "3.3.13")
vim.fn.mkdir(repo .. "/.git", "p")
object(repo .. "/package.json", { private = true })
local a, b, plain = repo .. "/packages/legacy", repo .. "/packages/modern", repo .. "/packages/plain"
object(a .. "/package.json", { dependencies = { vue = "^2.7" }, devDependencies = { typescript = "5.4.5" } })
object(b .. "/package.json", { dependencies = { vue = "^3.5" }, devDependencies = { typescript = "5.9.3" } })
object(plain .. "/package.json", {})
object(a .. "/node_modules/vue/package.json", { version = "2.7.16" })
object(b .. "/node_modules/vue/package.json", { version = "3.5.22" })
ts(a .. "/node_modules/typescript", "5.4.5")
ts(b .. "/node_modules/typescript", "5.9.3")
local tools = require("config.ts-toolchain")
tools.setup({ mason_root = mason, profiles_file = profiles, editor_sdk_root = directory .. "/editor-sdk" })
local function resolve(dir, ft)
  local ctx = tools.resolve_path(dir .. "/src/example." .. (ft == "vue" and "vue" or "ts"), ft or "typescript")
  assert(not ctx.error and not ctx.disabled, vim.inspect(ctx))
  return ctx
end
local ca, cb, cp = resolve(a, "vue"), resolve(b, "vue"), resolve(plain)
assert(ca.root == a and ca.profile == "vue2" and ca.vue_server == legacy and ca.typescript.version == "5.4.5")
assert(cb.root == b and cb.profile == "vue3" and cb.vue_server == modern and cb.typescript.version == "5.9.3")
assert(cp.profile == "none" and cp.plugin == nil and cp.typescript.version == "6.0.3")
assert(cp.ts_source:match("fallback"))
print("PASS: mixed monorepo uses package roots, matched Vue toolchains and project TypeScript; plain JS/TS has no plugin")

ts(a .. "/node_modules/typescript", "4.9.5")
local incompatible = tools.resolve_path(a .. "/src/App.vue", "vue")
assert(incompatible.error:match("reliable template types"))
assert(incompatible.error:find(profiles, 1, true), "Warning must name the actual override file")
assert(incompatible.error:find("typescript@5.9.3", 1, true), "Warning must explain how to install the editor SDK")
local suggested = vim.json.decode(assert(incompatible.error:match("\n({[^\n]+})\n")))
assert(suggested[a].tsdk == directory .. "/editor-sdk/node_modules/typescript/lib")
assert(incompatible.error:find("restart Neovim", 1, true))
local original_notify = vim.notify
local notices = {}
vim.notify = function(message) notices[#notices + 1] = message end
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buf, a .. "/src/App.vue")
vim.bo[buf].filetype = "vue"
local function unexpected_start() error("Incompatible SDK must not start a client") end
vim.lsp.config.ts_ls.root_dir(buf, unexpected_start)
vim.lsp.config.vue_ls.root_dir(buf, unexpected_start)
assert(#notices == 1 and notices[1] == "TS/Vue: " .. incompatible.error, "Warn once per project, not once per server")
vim.notify = original_notify
ts(directory .. "/editor-sdk/node_modules/typescript", "5.9.3")
local installed_sdk_warning = tools.resolve_path(a .. "/src/App.vue", "vue")
assert(installed_sdk_warning.error and not installed_sdk_warning.error:find("npm install", 1, true))
assert(installed_sdk_warning.typescript.version == "4.9.5", "Installed editor SDK must not be selected implicitly")
ts(a .. "/node_modules/typescript", "5.4.5")
print("PASS: Vue + TS 4.9 fails visibly instead of losing template types or silently replacing the SDK")
local plain_ts4 = directory .. "/plain-ts4"
object(plain_ts4 .. "/package.json", { devDependencies = { typescript = "4.9.5" } })
ts(plain_ts4 .. "/node_modules/typescript", "4.9.5")
assert(resolve(plain_ts4).typescript.version == "4.9.5" and resolve(plain_ts4).plugin == nil)
print("PASS: plain TS 4.9 projects retain their SDK without Vue-specific restrictions")

local hoisted = repo .. "/packages/hoisted"
object(hoisted .. "/package.json", { devDependencies = { typescript = "5.8.3" } })
local store = repo .. "/node_modules/.pnpm/typescript@5.8.3/node_modules/typescript"
ts(store, "5.8.3")
assert(vim.uv.fs_symlink(store, repo .. "/node_modules/typescript"))
assert(resolve(hoisted).typescript.path == store .. "/lib")
print("PASS: hoisted SDK and pnpm symlinks resolve to the actual installed version")

local external = directory .. "/sdk/typescript"
ts(external, "5.4.5")
object(profiles, {
  [repo] = { profile = "vue3" },
  [a] = { profile = "vue2", tsdk = external .. "/lib/tsserver.js" },
  [plain] = { profile = "none" },
})
assert(resolve(a, "vue").typescript.version == "5.4.5")
assert(resolve(a, "vue").ts_source == "override")
assert(resolve(b, "vue").profile == "vue3" and resolve(plain).profile == "none")
local isolated = plain .. "/subproject"
object(profiles, { [isolated] = { profile = "vue2" } })
local explicit = resolve(isolated, "vue")
assert(explicit.root == isolated and explicit.profile == "vue2")
object(profiles, {})
print("PASS: longest explicit path wins; SDK overrides and package-less subproject roots work")

-- Separate Git roots must never use the outer workspace's TS or Vue.
local nested = repo .. "/nested"
vim.fn.mkdir(nested .. "/.git", "p")
object(nested .. "/package.json", { devDependencies = { typescript = "5" } })
local bad = tools.resolve_path(nested .. "/a.ts", "typescript")
assert(bad.error and bad.error:match("declared but not installed"))
ts(nested .. "/node_modules/typescript", "7.0.2", false)
bad = tools.resolve_path(nested .. "/a.ts", "typescript")
assert(bad.error and bad.error:match("TypeScript 7.0.2 is incompatible"))
ts(nested .. "/node_modules/typescript", "7.0.2")
bad = tools.resolve_path(nested .. "/a.ts", "typescript")
assert(bad.error and bad.error:match("incompatible"))
object(nested .. "/package.json", { dependencies = { vue = "^2" } })
bad = tools.resolve_path(nested .. "/a.vue", "vue")
assert(bad.error and bad.error:match("Vue is declared but not installed"))
print("PASS: missing dependencies and TS 7 fail visibly, without silent SDK fallback or cross-Git discovery")

local no_git = directory .. "/workspace"
object(no_git .. "/package.json", {})
write(no_git .. "/pnpm-lock.yaml", "lockfileVersion: 9")
object(no_git .. "/packages/app/package.json", {})
ts(no_git .. "/node_modules/typescript", "5.9.3")
assert(resolve(no_git .. "/packages/app").typescript.version == "5.9.3")
local deno = directory .. "/deno"
write(deno .. "/deno.json", "{}")
local disabled = tools.resolve_path(deno .. "/file.ts", "typescript")
assert(disabled.disabled == "Deno project")
assert(tools.resolve_path(deno .. "/src/nested/file.ts", "typescript").disabled == "Deno project")
local deno_workspace = directory .. "/deno-workspace"
write(deno_workspace .. "/.git", "gitdir: /unused/worktree")
write(deno_workspace .. "/deno.json", "{}")
object(deno_workspace .. "/packages/app/package.json", {})
assert(tools.resolve_path(deno_workspace .. "/packages/app/file.ts", "typescript").disabled == "Deno project")
print("PASS: non-Git lockfile workspaces and Deno exclusion")

-- A top-level plugin can differ after a standard Mason update. Always prefer
-- the server's matching nested dependency, as Node/tsserver resolution does.
object(mason .. "/packages/vue-language-server/node_modules/@vue/typescript-plugin/package.json", { version = "9.0.0" })
assert(resolve(b, "vue").plugin_version == "3.3.13")
object(modern .. "/node_modules/@vue/typescript-plugin/package.json", { version = "3.0.11" })
bad = tools.resolve_path(b .. "/a.vue", "vue")
assert(bad.error and bad.error:match("versions differ"))
object(modern .. "/node_modules/@vue/typescript-plugin/package.json", { version = "3.3.13" })
print("PASS: prefer server-local Vue plugin and reject mismatched versions")

-- Exercise the same hooks as native vim.lsp.enable(), without spawning fake JS.
local original_rpc = vim.lsp.rpc.start
local calls = {}
vim.lsp.rpc.start = function(cmd, _, opts)
  calls[#calls + 1] = { cmd = cmd, opts = opts }
  return {}
end
local function prepared(name, dir)
  local config = vim.deepcopy(vim.lsp.config[name])
  config.root_dir = dir
  config.cmd({}, config)
  local params = { initializationOptions = config.init_options }
  if config.before_init then config.before_init(params, config) end
  return config, params
end
local config_a, params_a = prepared("ts_ls", a)
local config_b = prepared("ts_ls", b)
assert(params_a.initializationOptions.tsserver.path == a .. "/node_modules/typescript/lib/tsserver.js")
assert(params_a.initializationOptions.plugins[1].location == legacy)
assert(params_a.initializationOptions.hostInfo == "neovim")
assert(config_b.init_options.plugins[1].location == modern)
local config_plain = prepared("ts_ls", plain)
assert(#config_plain.init_options.plugins == 0 and vim.lsp.config.ts_ls.init_options.plugins == nil)
prepared("vue_ls", a)
assert(calls[#calls].cmd[4] == "--tsdk=" .. mason .. "/packages/vue-language-server-vue2/node_modules/typescript/lib")
assert(type(vim.lsp.config.vue_ls.on_init) == "function", "Keep upstream request forwarding")
local client = { name = "ts_ls", config = config_a, is_stopped = function() return false end }
assert(tools.client_matches(client, { name = "ts_ls", root_dir = a }))
assert(not tools.client_matches(client, { name = "ts_ls", root_dir = b }))
object(profiles, { [a] = { tsdk = external .. "/lib" } })
assert(not tools.client_matches(client, { name = "ts_ls", root_dir = a }), "Changing SDK must not reuse old client")
object(profiles, {})
ts(a .. "/node_modules/typescript", "5.0.4")
assert(not tools.client_matches(client, { name = "ts_ls", root_dir = a }), "Updating SDK in place invalidates reuse")
vim.lsp.rpc.start = original_rpc
print("PASS: per-client initialization, official bridge, --tsdk and reuse isolation (including SDK updates)")

write(profiles, "{invalid")
assert(tools.resolve_path(a .. "/a.ts").error:match("Invalid JSON"))
object(profiles, { [a] = { profile = "typo" } })
assert(tools.resolve_path(a .. "/a.ts").error:match("Unknown profile"))
object(profiles, { [a] = { tsdk = false } })
assert(tools.resolve_path(a .. "/a.ts").error:match("tsdk must be an absolute path"))
local ui = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(ui, "toolchain-test://ui")
assert(tools.resolve(ui).disabled == "Not a file buffer")
print("PASS: bad overrides and UI buffers fail safely")

-- Test a real local registry load and Mason's update target: U sees 3.0.11,
-- not npm latest, for this separate package identity. No network or install.
require("mason").setup({
  install_root_dir = directory .. "/registry",
  registries = { "lua:config.mason-registry" },
  PATH = "skip",
})
local registry = require("mason-registry")
registry.refresh()
local pkg = registry.get_package("vue-language-server-vue2")
assert(pkg:get_latest_version() == "3.0.11")
assert(pkg.spec.source.extra_packages[1] == "@vue/typescript-plugin@3.0.11")
assert(pkg.spec.bin["vue-language-server-vue2"] == "npm:vue-language-server")
assert(pkg:get_install_path():match("/packages/vue%-language%-server%-vue2$"))
print("PASS: Mason local registry exposes a separate legacy package pinned to matching 3.0.x tools")

vim.fn.delete(directory, "rf")
print("All TS/Vue toolchain unit tests passed")
