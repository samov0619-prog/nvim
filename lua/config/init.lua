local opts = { noremap = true, silent = true }
local M = require("config.functions.utils")
local described = M.described

local os_name = vim.uv.os_uname().sysname
-- SHELL --
if os_name == "Darwin" then
	vim.opt.shell = '/bin/zsh'
else
	vim.opt.shell = '/usr/bin/zsh'
end
-- ENV --
vim.env.NVIM_CFG = vim.fn.stdpath("config")

-- vim.env.ALACRITTY_CFG = vim.env.APPDATA .. "/alacritty/"
vim.env.PATH = "/home/amtea/.nvm/versions/node/v22.14.0/bin:" .. vim.env.PATH

local function load_custom_env(path)
	local file = io.open(path, "r")
	if not file then return end

	for line in file:lines() do
		local key, value = line:match("^([%w_]+)%s*=%s*(.+)$")
		if key and value then
			vim.fn.setenv(key, value)
		end
	end

	file:close()
end

load_custom_env(os.getenv("HOME") .. "/.config/.nvimenv")

-- LEADER --
vim.g.mapleader = " "
vim.keymap.set("n", "<Space>", "<Nop>", opts)

-- LANG --
vim.env.LANG = "en_US.UTF-8"

vim.keymap.set('i', '<C-х>', '<C-[>', described(opts, "<C-[>"))
vim.keymap.set('i', '<C-к>', '<C-r>', described(opts, "<C-r>"))

-- STATUSLINE --
vim.opt.statusline = "%{bufnr()} %<%f %h%m%r%=%-14.(%l,%c%V%) %P"
vim.opt.showmode = false
vim.o.laststatus = 3

-- EDITOR --
vim.opt.signcolumn = "yes:1"

vim.opt.number = true
-- vim.opt.relativenumber = true
vim.opt.numberwidth = 1

vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.smartindent = true
vim.opt.expandtab = true

vim.opt.list = true
vim.opt.listchars = "eol:¬,tab:>·,trail:~,extends:>,precedes:<"

vim.opt.cursorline = true

-- Comment in gitconfig
vim.api.nvim_create_autocmd("FileType", {
	pattern = "gitconfig",
	callback = function()
		vim.opt_local.commentstring = "# %s"
	end,
})

-- TERMINAL --
vim.api.nvim_create_autocmd('TermOpen', {
	pattern = '*',
	callback = function()
		vim.opt_local.cursorlineopt = 'number'
		vim.opt_local.cursorcolumn = false
		vim.opt_local.scrolloff = 0
		vim.opt_local.sidescrolloff = 0
	end,
})

-- DIAGNOSTIC --
vim.diagnostic.config({
	virtual_text = true,   -- Включаем виртуальный текст
	signs = true,          -- Включаем значки на полях
	underline = true,      -- Подчёркиваем проблемные участки
	update_in_insert = false, -- Не обновлять диагностику в режиме вставки
	severity_sort = false, -- Не сортировать диагностику по уровню серьёзности
})

vim.api.nvim_create_user_command('Restart', function()
	vim.fn.system('hyprctl dispatch exec "kitty nvim" &')
	vim.cmd('qa!')
end, {})

vim.api.nvim_create_autocmd('User', {
	pattern = 'LazyVimStarted',
	callback = function()
		local stats = require('lazy').stats()
		print('Startup in: ' .. stats.startuptime .. 'ms')
	end
})

vim.api.nvim_create_autocmd("SourcePost", {
	pattern = "*.vim",
	callback = function(args)
		if args.file:match("temp_sessions/.*") then
			vim.g.session_file = args.file
		end
	end,
})
