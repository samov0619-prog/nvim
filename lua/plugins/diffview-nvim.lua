return {
	{
		"sindrets/diffview.nvim",
		config = function()
			require("diffview").setup({
				view = {
					merge_tool = {
						layout = "diff3_mixed",
						disable_diagnostics = true,
						winbar_info = false,
					},
				},
			})
			vim.keymap.set("n", "<leader>gdo", "<cmd>DiffviewOpen<cr>", { desc = "diffview open" })
			vim.keymap.set("n", "<leader>gdO", "<cmd>DiffviewOpen origin<cr>", { desc = "diffview open origin" })
			vim.keymap.set("n", "<leader>gdu", "<cmd>DiffviewOpen @{u}<cr>", { desc = "diffview upstream" })
			vim.keymap.set("n", "<leader>gdc", "<cmd>DiffviewClose<cr>", { desc = "diffview close" })
		end
	},
}
