-- Run: nvim -n --headless -u NONE -i NONE -l tests/code-buffers.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
for _, plugin in ipairs({ "mini.files", "mini.icons", "nvim-lspconfig", "conform.nvim", "nvim-lint", "zk-nvim" }) do
  vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/" .. plugin)
end
vim.o.hidden, vim.o.swapfile, vim.o.backup, vim.o.writebackup = true, false, false, false
vim.o.lines, vim.o.columns = 55, 180
local api = vim.api
local directory = vim.fn.tempname()
vim.fn.mkdir(directory .. "/project", "p")
vim.fn.writefile({ "original" }, directory .. "/file.txt")
local function settle() vim.wait(100, function() return false end) end
local function wait(predicate, label) assert(vim.wait(3000, predicate, 10), label) end

-- MiniFiles must run before the tooling BufEnter callback, as in the reported
-- failure: it wipes the event's directory buffer while processing that event.
dofile(root .. "/lua/plugins/mini-files.lua")[1].config()
package.loaded.lazydev = { setup = function() end }
local enable = vim.lsp.enable
vim.lsp.enable = function() end
dofile(root .. "/lua/plugins/nvim-lspconfig.lua")[1].config()
vim.lsp.enable = enable
require("conform.log").set_handler(function() end)
dofile(root .. "/lua/plugins/conform-nvim.lua")[1].config()
dofile(root .. "/lua/plugins/nvim-lint.lua")[1].config()
local tools = require("config.code-tools")
local code = require("config.code")
local checks = require("config.code-checks")
local checked = 0
checks.format = function() checked = checked + 1; return function() end end
local mf = require("mini.files")

for _, alternate in ipairs({ false, true }) do
  if alternate then vim.cmd.edit(vim.fn.fnameescape(directory .. "/file.txt")) end
  vim.cmd.edit(vim.fn.fnameescape(directory .. "/project"))
  local dirbuf = api.nvim_get_current_buf()
  wait(function() return vim.bo.filetype == "minifiles" end, "Directory edit must open MiniFiles")
  local minibuf = api.nvim_get_current_buf()
  assert(not tools.is_file_buffer(dirbuf) and not tools.is_file_buffer(minibuf))
  assert(#vim.lsp.get_clients({ bufnr = minibuf }) == 0)
  vim.v.errmsg = ""
  local ok, err = pcall(vim.cmd.quit)
  assert(ok and vim.v.errmsg == "", tostring(err) .. "\n" .. vim.v.errmsg)
  wait(function() return not api.nvim_buf_is_valid(dirbuf) end, "Directory buffer must be wiped after :q")
  settle()
  mf.close()
  assert(not tools.is_file_buffer(dirbuf))
end
print("PASS: real MiniFiles directory -> :q wipes the event buffer without errors, with and without an alternate file")

-- A supported code filetype alone must never make a UI buffer eligible.
-- Observe native starts without spawning language servers in these fixtures.
local start = vim.lsp.start
local starts = {}
vim.lsp.start = function(config, opts)
  starts[#starts + 1] = { name = config.name, bufnr = opts and opts.bufnr or api.nvim_get_current_buf() }
end
-- Native enable validates executable availability before calling start().
for _, name in ipairs({ "bashls", "hyprls" }) do vim.lsp.config(name, { cmd = { vim.v.progpath } }) end
vim.lsp.enable({ "bashls", "hyprls" })
vim.fn.mkdir(directory .. "/notebook/.zk", "p")
local notebook_buffers = {}
require("zk.lsp").buf_add = function(bufnr) notebook_buffers[#notebook_buffers + 1] = bufnr end
dofile(root .. "/lua/plugins/zk-nvim.lua")[1].config()
local sync = api.nvim_get_autocmds({ group = "CodeProjectConfig", event = "BufEnter" })[1].callback
local root_dir = vim.lsp.config.eslint.root_dir

for _, case in ipairs({
  { "MiniFiles", "acwrite" }, { "NvimTree", "nofile" }, { "GitGraph", "nofile" },
  { "Diffview", "nowrite" }, { "Fugitive", "nowrite" }, { "Mason", "nofile" },
  { "FzfLua", "terminal" }, { "Quickfix", "quickfix" }, { "Prompt", "prompt" }, { "Help", "help" },
}) do
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(buf, directory .. "/notebook/" .. case[1] .. ".sh")
  if case[2] == "terminal" then api.nvim_open_term(buf, {})
  else vim.bo[buf].buftype = case[2] end
  api.nvim_set_current_buf(buf)
  settle() -- Drain checks queued for the ordinary alternate buffer, not this UI.
  local before = #starts
  -- Native Neovim deliberately allows help-language servers in help buffers.
  if case[2] ~= "help" then
    vim.bo[buf].filetype = "sh"
    vim.bo[buf].filetype = "hyprlang"
  end
  vim.bo[buf].filetype = "markdown"
  assert(not tools.is_file_buffer(buf), case[1])
  sync({ buf = buf })
  root_dir(buf, function() error("A UI buffer must not resolve a lint LSP root") end)
  local count = checked
  api.nvim_exec_autocmds("FocusGained", { buffer = buf })
  code.format_file(); code.fix_file()
  settle()
  assert(checked == count and not code.is_running(buf), case[1] .. " started code tools")
  assert(#starts == before and #notebook_buffers == 0, case[1] .. " started an LSP")
  assert(not tools.resolve(buf).formatter and next(tools.resolve(buf).lsp) == nil)
  api.nvim_buf_delete(buf, { force = true })
  sync({ buf = buf }) -- stale event arguments must also be harmless
  settle()
end
print("PASS: UI buffer types are excluded from native/manual LSP, zk, diagnostics, format and fix")

for _, name in ipairs({ "diffview://revision/file.js", "fugitive://repo/file.js", "merge-preview://result/file.js" }) do
  local buf = api.nvim_create_buf(false, false)
  api.nvim_buf_set_name(buf, name)
  assert(not tools.is_file_buffer(buf), "Virtual names remain excluded even with an ordinary buftype")
  sync({ buf = buf })
  assert(not tools.resolve(buf).formatter)
  api.nvim_buf_delete(buf, { force = true })
end
local unloaded = vim.fn.bufadd(directory .. "/unloaded.js")
assert(not tools.is_file_buffer(unloaded))
sync({ buf = unloaded })
assert(not tools.is_file_buffer(api.nvim_create_buf(false, false)), "Unnamed buffer")
print("PASS: virtual paths, unnamed, unloaded and wiped buffers are harmless")

vim.cmd.edit(vim.fn.fnameescape(directory .. "/new.js"))
assert(tools.is_file_buffer() and tools.is_file_buffer(0), "New unsaved files must remain eligible")
vim.cmd.edit(vim.fn.fnameescape(directory .. "/note.md"))
vim.bo.filetype = "markdown"
assert(#notebook_buffers == 0, "Markdown outside a notebook must not start zk")
vim.cmd.edit(vim.fn.fnameescape(directory .. "/notebook/note.md"))
vim.bo.filetype = "markdown"
assert(notebook_buffers[#notebook_buffers] == api.nvim_get_current_buf(), "Normal Markdown must reach zk")
for _, name in ipairs({ "custom.hl", "hyprland.conf" }) do
  local before = #starts
  vim.cmd.edit(vim.fn.fnameescape(directory .. "/" .. name))
  local ft = vim.filetype.match({ buf = api.nvim_get_current_buf() })
  vim.bo.filetype = ft
  settle()
  assert(vim.bo.filetype == "hyprlang", "Preserve Hyprland filename detection")
  assert(#starts == before + 1 and starts[#starts].name == "hyprls",
    "Only the native hyprls config must start: " .. vim.inspect({ before = before, starts = starts }))
end
print("PASS: unsaved files, Markdown notebooks and native Hyprland LSP remain eligible")

vim.lsp.enable({ "bashls", "hyprls" }, false)
vim.lsp.start = start
vim.fn.delete(directory, "rf")
print("All buffer lifecycle regression checks passed")
vim.cmd("qa!")
