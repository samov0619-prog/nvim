-- Run: nvim -n --headless -u NONE -i NONE -l tests/code-biome-lsp.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
for _, plugin in ipairs({ "nvim-lspconfig", "conform.nvim", "nvim-lint" }) do
  vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/" .. plugin)
end
vim.o.hidden, vim.o.swapfile, vim.o.backup, vim.o.writebackup = true, false, false, false
require("conform.log").set_handler(function() end)
local api = vim.api
local directory = vim.fn.tempname()
local biome = vim.fn.stdpath("data") .. "/mason/bin/biome"
assert(vim.fn.executable(biome) == 1, "Install Biome through Mason before running this test")
local notices = {}
vim.notify = function(message) notices[#notices + 1] = tostring(message) end
local function write(path, source)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(vim.split(source, "\n", { plain = true }), path, "b")
end
local function wait(predicate, label)
  assert(vim.wait(15000, predicate, 10), label .. "\n" .. vim.inspect(notices))
end

-- Exercise native FileType auto-start and the same reconciliation as the real
-- configuration, without starting unrelated language servers in this fixture.
package.loaded.lazydev = { setup = function() end }
local enable = vim.lsp.enable
vim.lsp.enable = function() end
dofile(root .. "/lua/plugins/nvim-lspconfig.lua")[1].config()
vim.lsp.enable = enable
dofile(root .. "/lua/plugins/conform-nvim.lua")[1].config()
dofile(root .. "/lua/plugins/nvim-lint.lua")[1].config()
vim.lsp.enable("biome")
local tools = require("config.code-tools")
local function matching(bufnr)
  local tool = tools.resolve(bufnr).lsp.biome
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr, name = "biome" })) do
    if client.initialized and tools.biome_client_matches(client, tool) then return client end
  end
end
local function open(path, ft, source)
  write(path, source)
  vim.cmd.edit(vim.fn.fnameescape(path))
  vim.bo.filetype = ft
  local bufnr = api.nvim_get_current_buf()
  wait(function() return matching(bufnr) end, "Biome must auto-attach to " .. ft .. ": " .. path)
  return bufnr, matching(bufnr)
end
local function local_binary(dir)
  local bin = dir .. "/node_modules/.bin/biome"
  vim.fn.mkdir(vim.fs.dirname(bin), "p")
  assert(vim.uv.fs_symlink(biome, bin))
  return bin
end

vim.fn.mkdir(directory .. "/.git", "p")
local project_config = {
  formatter = { indentStyle = "space", indentWidth = 2 },
  linter = { rules = { suspicious = { noDuplicateProperties = "error" } } },
  markdown = { analyzeEmbeds = true },
}
write(directory .. "/biome.json", vim.json.encode(project_config))
local root_buffer, original_client = open(directory .. "/root.js", "javascript", "const value=1;\n")
assert(original_client.config._code_tools_cmd == biome and original_client.config.root_dir == directory)

local scss, scss_client = open(directory .. "/style.scss", "scss", ".a {\n  color: red;\n}\n")
assert(scss_client.id == original_client.id)
api.nvim_buf_set_lines(scss, 0, -1, false, { ".a {", "  color: red;", "  color: blue;", "}" })
api.nvim_exec_autocmds("TextChanged", { buffer = scss })
local namespace = require("lint").get_namespace("biomejs")
wait(function()
  for _, diagnostic in ipairs(vim.diagnostic.get(scss, { namespace = namespace })) do
    if diagnostic.code == "lint/suspicious/noDuplicateProperties" then return true end
  end
end, "Unsaved, already formatted SCSS must have its lint diagnostic")
for _, diagnostic in ipairs(vim.diagnostic.get(scss, { namespace = namespace })) do
  assert(diagnostic.code ~= "format", "SCSS fixture must isolate lint from formatting")
end
assert(vim.bo[scss].modified and #vim.fn.readfile(directory .. "/style.scss") == 3)
print("PASS: SCSS auto-attaches and publishes full unsaved lint diagnostics without a formatting difference")

for _, case in ipairs({
  { "data.yaml", "yaml", "value: 1\n" },
  { "readme.md", "markdown", "# Sample\n" },
}) do
  local bufnr, client = open(directory .. "/" .. case[1], case[2], case[3])
  assert(client.id == original_client.id)
  assert(tools.resolve(bufnr).lsp.biome)
end
print("PASS: YAML and Markdown use native Biome auto-start with the shared project policy")

local app_a, app_b = directory .. "/packages/a", directory .. "/packages/b"
local bin_a, bin_b = local_binary(app_a), local_binary(app_b)
write(app_a .. "/package.json", "{}")
write(app_b .. "/package.json", "{}")
local a, client_a = open(app_a .. "/src/a.js", "javascript", "const value=1;\n")
local b, client_b = open(app_b .. "/src/b.js", "javascript", "const value=2;\n")
assert(client_a.id ~= client_b.id and client_a.id ~= original_client.id)
for _, case in ipairs({ { a, client_a, app_a, bin_a }, { b, client_b, app_b, bin_b } }) do
  local ctx = tools.resolve(case[1])
  assert(ctx.formatter.cmd == case[4] and ctx.linters[1].cmd == case[4])
  assert(ctx.formatter.cwd == directory, "CLI globs must stay relative to the shared config")
  assert(case[2].config.root_dir == case[3] and case[2].config._code_tools_cmd == case[4])
  assert(not tools.biome_client_matches(original_client, ctx.lsp.biome))
end
local another, same_client = open(app_a .. "/src/another.js", "javascript", "const value=3;\n")
assert(same_client.id == client_a.id and matching(another).id == client_a.id)
local diagnostics
local lines = api.nvim_buf_get_lines(a, 0, -1, false)
require("config.code-checks").biome(tools.resolve(a), {
  bufnr = a, filename = api.nvim_buf_get_name(a), tick = api.nvim_buf_get_changedtick(a),
  lines = lines, offsets = { 0 }, source = table.concat(lines, "\n") .. "\n", eol = true,
  current = function() return true end,
}, client_a, function(result) diagnostics = result end)
wait(function() return diagnostics end, "Package workspace must load the ancestor Biome config")
local format_difference = false
for _, diagnostic in ipairs(diagnostics) do
  assert(diagnostic.severity ~= vim.diagnostic.severity.ERROR, vim.inspect(diagnostics))
  if diagnostic.code == "format" then format_difference = true end
end
assert(format_difference, vim.inspect(diagnostics))
print("PASS: packages sharing one config use their own Biome binaries/clients and reuse only matching installations")

api.nvim_set_current_buf(a)
project_config.linter.rules.correctness = { noUnusedVariables = "off" }
write(directory .. "/biome.json", vim.json.encode(project_config))
api.nvim_exec_autocmds("FocusGained", { buffer = a })
wait(function()
  local formatting = false
  for _, diagnostic in ipairs(vim.diagnostic.get(a, { namespace = namespace })) do
    if diagnostic.code == "lint/correctness/noUnusedVariables" then return false end
    if diagnostic.code == "format" then formatting = true end
  end
  return formatting
end, "The narrowed package workspace must reload an ancestor config")
assert(matching(a).id == client_a.id)
print("PASS: changing the shared ancestor config refreshes package diagnostics without restarting its client")

-- Same root, new executable: an existing attached client must not survive the
-- transition from Mason to a newly installed local Biome.
local root_bin = local_binary(directory)
api.nvim_set_current_buf(root_buffer)
api.nvim_exec_autocmds("BufEnter", { buffer = root_buffer })
wait(function()
  local client = matching(root_buffer)
  return client and client.id ~= original_client.id
end, "Installing local Biome must replace the attached Mason client")
local replacement = matching(root_buffer)
assert(replacement.config.root_dir == directory and replacement.config._code_tools_cmd == root_bin)
assert(not vim.lsp.buf_is_attached(root_buffer, original_client.id))
assert(not vim.lsp.config.biome.reuse_client(original_client, replacement.config))
assert(vim.lsp.config.biome.reuse_client(replacement, replacement.config))
print("PASS: changing the executable at the same root detaches the old client and prevents stale reuse")

write(directory .. "/nested/biome.json", '{"formatter":{"indentStyle":"space","indentWidth":4}}')
local nested, hoisted = open(directory .. "/nested/source.js", "javascript", "const value=4;\n")
assert(hoisted.config.root_dir == directory .. "/nested" and hoisted.config._code_tools_cmd == root_bin)
assert(tools.resolve(nested).formatter.cmd == root_bin)
print("PASS: a nested config can use a hoisted binary inside the project boundary")

assert(vim.uv.fs_unlink(bin_a))
api.nvim_set_current_buf(a)
api.nvim_exec_autocmds("BufEnter", { buffer = a })
wait(function() return matching(a) and matching(a).id == replacement.id end,
  "Removing the package binary must reuse the matching hoisted installation")
assert(not vim.lsp.buf_is_attached(a, client_a.id) and tools.resolve(a).formatter.cmd == root_bin)
print("PASS: removing a package binary reconciles its buffer with the hoisted installation")

vim.lsp.enable("biome", false)
wait(function() return #vim.lsp.get_clients({ name = "biome" }) == 0 end, "Biome clients must stop")
vim.fn.delete(directory, "rf")
print("All Biome LSP regression checks passed")
vim.cmd("qa!")
