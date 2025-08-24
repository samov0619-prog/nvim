return {
	{
		"olimorris/codecompanion.nvim",
		lazy = true,
		keys = {
			{ "<leader>Cc", "<cmd>CodeCompanionChat Toggle<CR>", desc = "chat" },
			{ "<leader>Ca", "<cmd>CodeCompanionActions<CR>",     desc = "ai actions",        mode = { "n", "v" } },
			{ "<leader>Cx", "<cmd>CodeCompanionCommand<CR>",     desc = "generate shell cmd" },
		},
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-treesitter/nvim-treesitter",
		},
		opts = {
			log_level = "DEBUG",
			strategies = {
				chat = {
					adapter = "copilot_like",
				},
				inline = {
					adapter = "copilot_like",
				},
				actions = {
					adapter = "copilot_like"
				},
				files = {
					adapter = "copilot_like"
				},

				adapter = "copilot_like"
			},
			cmd = {
				adapter = "copilot_like"
			},
		},
		adapters = {
			copilot_like = function()
				---@type CodeCompanion.Adapter
				local adapter = {
					name = "Copilot-Code v0.1.2",
					env = {
						url = vim.fn.getenv("COPILOT_LIKE_URL"),
						api_key = vim.fn.getenv("COPILOT_LIKE"),
						chat_url = "/chat/completions",
					},
					schema = {
						model = { default = "x5-airun-medium-coder-prod" },
					},
				}
				return require("codecompanion.adapters").extend(
					"openai_compatible", adapter
				)
			end,
		},
	},
}
