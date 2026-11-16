local opts = { noremap = true, silent = true }
local M = require("config.functions.utils")
local described = M.described

local os_name = vim.uv.os_uname().sysname

-- GIT LINKS --
vim.keymap.set("n", "<leader>gy", function()
  require("config.git-link").copy()
end, described(opts, "copy link to current line"))
vim.keymap.set("x", "<leader>gy", function()
  require("config.git-link").copy(true)
end, described(opts, "copy link to current lines"))

-- TAB PAGES --
vim.keymap.set('n', '<leader>tc', '<cmd>tabclose<CR>', described(opts, "close current tab page"))

-- WINDOWS NAVIGATION --
if os_name == "Darwin" then
  -- (i, t)
  vim.keymap.set({ 'i', 't' }, '˙', '<C-\\><C-N><C-w>h', described(opts, "go to left window"))
  vim.keymap.set({ 'i', 't' }, '∆', '<C-\\><C-N><C-w>j', described(opts, "go to down window"))
  vim.keymap.set({ 'i', 't' }, '˚', '<C-\\><C-N><C-w>k', described(opts, "go to up window"))
  vim.keymap.set({ 'i', 't' }, '¬', '<C-\\><C-N><C-w>l', described(opts, "go to right window"))

  -- (n)
  vim.keymap.set('n', '˙', '<C-w>h', described(opts, "go to left window"))
  vim.keymap.set('n', '∆', '<C-w>j', described(opts, "go to down window"))
  vim.keymap.set('n', '˚', '<C-w>k', described(opts, "go to up window"))
  vim.keymap.set('n', '¬', '<C-w>l', described(opts, "go to right window"))
else
  -- (i, t)
  vim.keymap.set({ 'i', 't' }, '<A-h>', '<C-\\><C-N><C-w>h', described(opts, "go to left window"))
  vim.keymap.set({ 'i', 't' }, '<A-j>', '<C-\\><C-N><C-w>j', described(opts, "go to down window"))
  vim.keymap.set({ 'i', 't' }, '<A-k>', '<C-\\><C-N><C-w>k', described(opts, "go to up window"))
  vim.keymap.set({ 'i', 't' }, '<A-l>', '<C-\\><C-N><C-w>l', described(opts, "go to right window"))

  -- (n)
  vim.keymap.set('n', '<A-h>', '<C-w>h', described(opts, "go to left window"))
  vim.keymap.set('n', '<A-j>', '<C-w>j', described(opts, "go to down window"))
  vim.keymap.set('n', '<A-k>', '<C-w>k', described(opts, "go to up window"))
  vim.keymap.set('n', '<A-l>', '<C-w>l', described(opts, "go to right window"))
end

-- SCRATCH BUFF --
vim.keymap.set('n', '<leader>scr', function()
  vim.cmd('new')
  vim.bo.buftype = 'nofile'
  vim.bo.bufhidden = 'wipe'
  vim.bo.swapfile = false
end, described(opts, "create scratch buffer"))

-- DIFF --
function ToggleDiff()
  if vim.wo.diff then
    vim.cmd("windo diffoff")
  else
    vim.cmd("windo diffthis")
  end
end

function ToggleDiffContext()
  local diffopt = vim.opt.diffopt:get()
  if vim.tbl_contains(diffopt, "context:0") then
    vim.opt.diffopt:remove("context:0")
    print("Diff context выключен")
  else
    vim.opt.diffopt:append("context:0")
    print("Diff context включен")
  end
end

vim.keymap.set("n", "<leader>do", ToggleDiff, described(opts, "toggle diff mode"))
vim.keymap.set("n", "<leader>dc", ToggleDiffContext, described(opts, "toggle diff context"))
vim.keymap.set('n', '<leader>dg', '<cmd>diffget<CR>', described(opts, "get hunk from other diff"))
vim.keymap.set('n', '<leader>dp', '<cmd>diffput<CR>', described(opts, "put hunk to other diff"))

-- DIAGNOSTIC --
vim.keymap.set('n', '<C-W>d', function()
  vim.diagnostic.open_float()
  vim.diagnostic.open_float()
end, described(opts, "open diagnostic float"))
vim.keymap.set(
  "n",
  "<leader>dd",
  function()
    require("config.code-review").toggle_diagnostics()
  end,
  described(opts, "toggle diagnostics")
)

-- MERMAID -- (load the viewer only on demand)
vim.keymap.set('n', '<leader>rd', function()
  require('config.mermaid-preview').toggle()
end, described(opts, 'Preview Mermaid diagram'))
vim.api.nvim_create_user_command('MermaidPreview', function()
  require('config.mermaid-preview').toggle()
end, {})

-- COLORTHEME --

-- EDIT --
vim.keymap.set({ 'n', 'v' }, '<leader>y', '"+y', described({ noremap = true, silent = true }, "yank to clipboard"))
vim.keymap.set({ 'n', 'v' }, '<leader>p', '"+p', described({ noremap = true, silent = true }, "paste from clipboard"))

vim.keymap.set("n", "<leader>cf", function()
  require("config.code").format_file()
end, described(opts, "format file"))
vim.keymap.set("n", "<leader>cx", function()
  require("config.code").fix_file()
end, described(opts, "fix file"))

-- Move current line(s) ---
vim.keymap.set("n", "<leader>j", ":m .+1<CR>==", described(opts, "move line down"))
vim.keymap.set("n", "<leader>k", ":m .-2<CR>==", described(opts, "move line up"))
vim.keymap.set("v", "<leader>j", ":'<,'>m '>+1<CR>gv=gv", described(opts, "move selection down"))
vim.keymap.set("v", "<leader>k", ":'<,'>m '<-2<CR>gv=gv", described(opts, "move selection up"))

-- Increment-decrement selection
vim.keymap.set('n', '<C-Space>', ':normal van<cr>', opts)
vim.keymap.set('v', '<C-Space>', function()
  vim.api.nvim_feedkeys('an', 'v', false)
end)
vim.keymap.set('n', '<C-Backspace>', ':normal vin<cr>', opts)
vim.keymap.set('v', '<C-Backspace>', function()
  vim.api.nvim_feedkeys('in', 'v', false)
end)

-- EDITOR --
vim.keymap.set("n", "<leader>fp", function() vim.fn.setreg("+", vim.fn.expand("%:p")) end,
  described(opts, "copy file path"))
