local opts = { noremap = true, silent = true }
local M = require("config.functions.utils")
local described = M.described

-- WINDOWS NAVIGATION --
-- (t)
vim.keymap.set('t', '<A-h>', '<C-\\><C-N><C-w>h', described(opts, "go to left window"))
vim.keymap.set('t', '<A-j>', '<C-\\><C-N><C-w>j', described(opts, "go to down window"))
vim.keymap.set('t', '<A-k>', '<C-\\><C-N><C-w>k', described(opts, "go to up window"))
vim.keymap.set('t', '<A-l>', '<C-\\><C-N><C-w>l', described(opts, "go to right window"))

-- (i)
vim.keymap.set('i', '<A-h>', '<C-\\><C-N><C-w>h', described(opts, "go to left window"))
vim.keymap.set('i', '<A-j>', '<C-\\><C-N><C-w>j', described(opts, "go to down window"))
vim.keymap.set('i', '<A-k>', '<C-\\><C-N><C-w>k', described(opts, "go to up window"))
vim.keymap.set('i', '<A-l>', '<C-\\><C-N><C-w>l', described(opts, "go to right window"))

-- (n)
vim.keymap.set('n', '<A-h>', '<C-w>h', described(opts, "go to left window"))
vim.keymap.set('n', '<A-j>', '<C-w>j', described(opts, "go to down window"))
vim.keymap.set('n', '<A-k>', '<C-w>k', described(opts, "go to up window"))
vim.keymap.set('n', '<A-l>', '<C-w>l', described(opts, "go to right window"))

-- SCRATCH BUFF --
vim.keymap.set('n', '<leader>scr', function()
	vim.cmd('new')
	vim.bo.buftype = 'nofile'
	vim.bo.bufhidden = 'wipe'
	vim.bo.swapfile = false
end, described(opts, "create scratch buffer"))

-- TERMINAL --
-- Open bottom
vim.keymap.set('n', '<leader>th', ':belowright sp | terminal<CR> i', described(opts, "open terminal horizontal"))
-- Open right
vim.keymap.set('n', '<leader>tv', ':belowright vsp | terminal<CR> i', described(opts, "open terminal vertical"))
-- Open external terminal to wd
vim.keymap.set('n', '<leader>tx', function()
	vim.fn.system('kitty --directory="' .. vim.fn.getcwd() .. '" &')
end, described(opts, "open external terminal"))
-- To normal from (t)
vim.keymap.set('t', '<C-[>', '<C-\\><C-n>', described(opts, "exit terminal mode"))
-- i_CTRL-R in (t)
vim.keymap.set('t', '<C-R>', function()
	return '<C-\\><C-N>"' .. vim.fn.getcharstr() .. 'pi'
end, described(vim.tbl_extend("force", opts, { expr = true }), "paste register"))

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
		vim.diagnostic.enable(not vim.diagnostic.is_enabled())
	end,
	described(opts, "toggle diagnostic virtual_lines")
)
vim.keymap.set(
	"n",
	"<leader>dl",
	function()
		vim.diagnostic.setqflist({})
	end,
	described(opts, "show diagnostic list")
)

-- COLORTHEME --

-- EDIT --
vim.keymap.set({ 'n', 'v' }, '<leader>y', '"+y', described({ noremap = true, silent = true }, "yank to clipboard"))
vim.keymap.set({ 'n', 'v' }, '<leader>p', '"+p', described({ noremap = true, silent = true }, "paste from clipboard"))

vim.keymap.set('n', '<leader>MY', '"ayy', described({ noremap = true, silent = true }, "clear and add string to @a"))
vim.keymap.set('n', '<leader>my', '"Ayy', described({ noremap = true, silent = true }, "add string to @a"))
-- Move current line(s) ---
vim.keymap.set("n", "<leader>j", ":m .+1<CR>==", described(opts, "move line down"))
vim.keymap.set("n", "<leader>k", ":m .-2<CR>==", described(opts, "move line up"))
vim.keymap.set("v", "<leader>j", ":'<,'>m '>+1<CR>gv=gv", described(opts, "move selection down"))
vim.keymap.set("v", "<leader>k", ":'<,'>m '<-2<CR>gv=gv", described(opts, "move selection up"))

-- EDITOR --
vim.keymap.set("n", "<leader>cl", function() vim.opt.cursorline = not vim.opt.cursorline:get() end,
	described(opts, "toggle cursor line"))
vim.keymap.set("n", "<leader>cc", function() vim.opt.cursorcolumn = not vim.opt.cursorcolumn:get() end,
	described(opts, "toggle cursor column"))
vim.keymap.set("n", "<leader>cfp", function() vim.fn.setreg("+", vim.fn.expand("%:p")) end,
	described(opts, "copy file path"))
