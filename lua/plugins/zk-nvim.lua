return {
	{
		"zk-org/zk-nvim",
		config = function()
			require("zk").setup({
				picker = "fzf_lua",
				lsp = {
					-- `config` is passed to `vim.lsp.start_client(config)`
					config = {
						cmd  = { "zk", "lsp" },
						name = "zk",
						-- on_attach = ...
						-- etc, see `:h vim.lsp.start_client()`
					},

					-- automatically attach buffers in a zk notebook that match the given filetypes
					auto_attach = {
						enabled = true,
						filetypes = { "markdown" },
					},
				},
			})

			local opts = { noremap = true, silent = false }
			vim.keymap.set("n", "<leader>zkn", "<Cmd>ZkNew<CR>", { desc = "new note" })
			vim.keymap.set("n", "<leader>zkN", "<Cmd>ZkNew { title = vim.fn.input('Title: ') }<CR>",
				{ desc = "new note with title" })
			-- Open notes.
			vim.keymap.set("n", "<leader>zko", "<Cmd>ZkNotes { sort = { 'modified' } }<CR>", { desc = "open notes" })
			-- Open notes associated with the selected tags.
			vim.keymap.set("n", "<leader>zkt", "<Cmd>ZkTags<CR>", { desc = "open tags" })
			-- Search for the notes matching a given query.
			vim.keymap.set("n", "<leader>zkf",
				"<Cmd>ZkNotes { sort = { 'modified' }, match = { vim.fn.input('Search: ') } }<CR>",
				{ desc = "find notes" })
			-- Search for the notes matching the current visual selection.
			vim.keymap.set("v", "<leader>zkf", ":'<,'>ZkMatch<CR>", { desc = "find notes" })
		end
	}
}
