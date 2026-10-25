-- Run with ruff, basedpyright-langserver and python3 on PATH:
-- nvim -n --headless -u NONE -i NONE -l tests/code-python.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
for _, plugin in ipairs({ "nvim-lspconfig", "conform.nvim", "nvim-lint" }) do
  vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/" .. plugin)
end
vim.o.hidden, vim.o.swapfile, vim.o.backup, vim.o.writebackup = true, false, false, false
local api = vim.api
local directory = vim.fn.tempname()
local ruff = vim.fn.exepath("ruff")
assert(ruff ~= "" and vim.fn.executable("basedpyright-langserver") == 1, "Install Ruff and basedpyright first")
local notices = {}
vim.notify = function(message) notices[#notices + 1] = tostring(message) end
local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
end
local function wait(predicate, label)
  assert(vim.wait(15000, predicate, 10), label .. "\n" .. vim.inspect(notices))
end
local function open(path, lines)
  write(path, lines)
  vim.cmd.edit(vim.fn.fnameescape(path))
  vim.bo.filetype = "python"
  return api.nvim_get_current_buf()
end
local function text(buf) return table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n") end
local function has_code(buf, namespace, code)
  for _, diagnostic in ipairs(vim.diagnostic.get(buf, { namespace = namespace })) do
    if diagnostic.code == code then return true end
  end
  return false
end

package.loaded.lazydev = { setup = function() end }
local enable = vim.lsp.enable
vim.lsp.enable = function() end
dofile(root .. "/lua/plugins/nvim-lspconfig.lua")[1].config()
vim.lsp.enable = enable
require("conform.log").set_handler(function() end)
dofile(root .. "/lua/plugins/conform-nvim.lua")[1].config()
dofile(root .. "/lua/plugins/nvim-lint.lua")[1].config()
local tools = require("config.code-tools")
local lint = require("lint")
local code = require("config.code")
local ruff_ns, format_ns = lint.get_namespace("ruff"), lint.get_namespace("ruff_format")

-- Python project discovery must also work before git init, from a nested file.
local plain = directory .. "/plain"
write(plain .. "/pyproject.toml", { '[project]', 'name = "fixture"', 'version = "0.0.0"' })
local buf = open(plain .. "/src/example.py", { "value=0" })
assert(tools.resolve(buf).boundary == plain, "Find a non-Git Python project from src/")
assert(tools.resolve(buf).formatter.id == "ruff_format")
wait(function() return #vim.diagnostic.get(buf, { namespace = format_ns }) > 0 end, "Default Ruff formatting")
print("PASS: non-Git Python project and Ruff defaults need no tool-specific config")

-- Ruff alone owns Python even when the repository contains JS tool configs.
local mixed = directory .. "/mixed"
vim.fn.mkdir(mixed .. "/.git", "p")
write(mixed .. "/biome.json", { "{}" })
write(mixed .. "/eslint.config.js", { "export default []" })
write(mixed .. "/.ruff.toml", { '[lint]', 'select = ["F", "I"]' })
write(mixed .. "/backend/pyproject.toml", { '[project]', 'name = "backend"', 'version = "0.0.0"' })
local local_ruff = mixed .. "/.venv/bin/ruff"
vim.fn.mkdir(vim.fs.dirname(local_ruff), "p")
assert(vim.uv.fs_symlink(ruff, local_ruff))
buf = open(mixed .. "/backend/example.py", { "value=0" })
local ctx = tools.resolve(buf)
assert(ctx.profile == "python" and next(ctx.lsp) == nil and #ctx.linters == 1)
assert(ctx.formatter.cmd == local_ruff and ctx.linter.cmd == local_ruff, "Prefer the project's Ruff")
api.nvim_buf_set_lines(buf, 0, -1, false, { "import os", "", "value=missing_name" })
require("config.code-diagnostics").refresh(buf, true)
wait(function() return has_code(buf, ruff_ns, "F401") and has_code(buf, ruff_ns, "F821") end,
  "Lint the unsaved buffer using the ancestor Ruff config")
assert(vim.fn.readfile(ctx.filename)[1] == "value=0", "Checks must not save or modify the file")
code.format_file()
wait(function() return not code.is_running(buf) end, "Format the Python buffer")
assert(text(buf):find("value = missing_name", 1, true) and text(buf):find("import os", 1, true))
assert(vim.fn.readfile(ctx.filename)[1] == "value=0", "Formatting must only edit the buffer")
vim.cmd.write()
code.fix_file()
wait(function() return not code.is_running(buf) end, "Fix and then format Python")
assert(not text(buf):find("import os", 1, true) and text(buf):find("value = missing_name", 1, true))
wait(function() return not has_code(buf, ruff_ns, "F401") and has_code(buf, ruff_ns, "F821") end,
  "Safe fixes preserve source and remaining unfixable diagnostics")
print("PASS: mixed repo, local Ruff, unsaved linting, format-only and safe CLI fixes")

-- Config-only edits must invalidate cached diagnostics, even when the nearer
-- pyproject.toml has no Ruff section and does not change itself.
write(mixed .. "/.ruff.toml", { '[lint]', 'select = ["F", "I"]', 'ignore = ["F821"]' })
require("config.code-diagnostics").refresh(buf, false)
wait(function() return #vim.diagnostic.get(buf, { namespace = ruff_ns }) == 0 end, "Reload ancestor Ruff settings")
print("PASS: ancestor Ruff config changes invalidate cached Python diagnostics")

-- An explicit safe-fix policy must win over unsafe-fixes=true in project config.
write(mixed .. "/.ruff.toml", { 'unsafe-fixes = true', '[lint]', 'select = ["F"]' })
buf = open(mixed .. "/unsafe.py", { "def example():", "    unused = 1", "    return 2" })
code.fix_file()
wait(function() return not code.is_running(buf) end, "Safe-only fixes")
assert(text(buf):find("unused = 1", 1, true), "F841 requires an unsafe fix and must remain")
print("PASS: project settings cannot enable unsafe fixes in the shared fix action")

-- Exercise real basedpyright, including its native .venv discovery. A package
-- available only inside that environment must resolve and retain its type.
local result = vim.system({ vim.fn.exepath("python3"), "-m", "venv", "--without-pip", plain .. "/.venv" },
  { text = true }):wait(15000)
assert(result.code == 0, result.stderr)
result = vim.system({ plain .. "/.venv/bin/python", "-c", "import sysconfig; print(sysconfig.get_path('purelib'))" },
  { text = true }):wait(5000)
assert(result.code == 0, result.stderr)
write(vim.trim(result.stdout) .. "/fixture_dependency/__init__.py", { "value: int = 42" })
write(vim.trim(result.stdout) .. "/fixture_dependency/py.typed", {})
buf = open(plain .. "/src/typed.py", { "from fixture_dependency import value", "result: str = value" })
vim.lsp.enable("basedpyright")
wait(function() return has_code(buf, nil, "reportAssignmentType") end, "basedpyright must see dependency types from .venv")
assert(not has_code(buf, nil, "reportMissingImports"), "Resolve imports from the project .venv")
local client = assert(vim.lsp.get_clients({ bufnr = buf, name = "basedpyright" })[1])
assert(client.config.root_dir == plain)
assert(client.settings.basedpyright.analysis.typeCheckingMode == "standard")
assert(#vim.lsp.get_clients({ bufnr = buf, name = "ruff" }) == 0)
print("PASS: basedpyright attaches with standard checks and resolves the project's .venv")

-- Project type-checking settings must take precedence over the editor default.
local configured = directory .. "/configured"
write(configured .. "/pyproject.toml", { '[tool.basedpyright]', 'typeCheckingMode = "off"' })
buf = open(configured .. "/example.py", { 'value: int = "not an int"', "def broken(:" })
wait(function()
  for _, diagnostic in ipairs(vim.diagnostic.get(buf)) do
    if diagnostic.source == "basedpyright" then return true end
  end
  return false
end, "Receive syntax diagnostics with project type checking disabled")
assert(not has_code(buf, nil, "reportAssignmentType"), "Project config overrides standard mode")
print("PASS: project typeCheckingMode overrides the editor's default")

vim.lsp.enable("basedpyright", false)
vim.fn.delete(directory, "rf")
vim.cmd("qa!")
