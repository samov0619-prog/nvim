return {
	{
		"tpope/vim-fugitive",
		dependencies = {
			"shumphrey/fugitive-gitlab.vim",
			"tpope/vim-rhubarb",
		},
		config = function()
			_G.CustomGitLabHandlerLua = function(opts)
				if not opts.remote or not opts.remote:match("gitlab%.pla") then
					return ""
				end

				local remote = opts.remote
					:gsub("^.*//", "")
					:gsub("git@", "")
					:gsub(":", "/")
					:gsub("%.git$", "")

				local url = ("https://%s/-/blob/%s/%s"):format(remote, opts.commit or "HEAD", opts.path or "")

				if opts.line1 then
					url = url .. "#L" .. opts.line1
					if opts.line2 and opts.line2 ~= opts.line1 then
						url = url .. "-" .. opts.line2
					end
				end

				return "[code](" .. url .. ")"
			end

			-- Регистрируем VimL-обертку, вызывающую Lua-функцию
			vim.cmd([[
				function! CustomGitLabHandler(opts) abort
				return luaeval("_G.CustomGitLabHandlerLua(_A)", a:opts)
				endfunction

				let g:fugitive_browse_handlers = get(g:, 'fugitive_browse_handlers', [])
				call add(g:fugitive_browse_handlers, function('CustomGitLabHandler'))
			]])

			vim.keymap.set(
				"n",
				"<leader>gg",
				":Gedit :<CR>",
				{ desc = "open fugitive UI window", silent = true }
			)
			vim.keymap.set(
				"n",
				"<leader>gl",
				":Git log<cr>",
				{ desc = "open log" }
			)

			vim.keymap.set(
				"n",
				"<leader>gps",
				":Git push<CR>",
				{ desc = "pushes changes to remote" }
			)
			vim.keymap.set(
				"n",
				"<leader>gpl",
				":Git pull<CR>",
				{ desc = "pulls changes from remote" }
			)

			vim.keymap.set(
				"n",
				"<leader>gy",
				":.GBrowse!<cr>",
				{ desc = "copy link to current line" }
			)
			vim.keymap.set(
				"n",
				"<leader>gY",
				":GBrowse!<CR>",
				{ desc = "copy link to file" }
			)
			vim.keymap.set(
				"x",
				"<leader>gy",
				":'<'>GBrowse!<cr>",
				{ desc = "copy link to current lines" }
			)
		end,
	},
}
