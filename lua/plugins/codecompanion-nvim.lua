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
			strategies = {
				chat = {
					adapter = "together",
				},
				inline = {
					adapter = "together",
				},
				actions = {
					adapter = "together"
				},
				files = {
					adapter = "together"
				},
				explain = {
					adapter = "together"
				},
				cmd = {
					adapter = "together"
				},
			},
			adapters = {
				together = function()
					return require("codecompanion.adapters").extend(
						"openai_compatible",
						{
							name = "DeepSeek-R1-Distill-Llama-70B",
							env = {
								url = "https://api.together.xyz",
								chat_url = "/v1/chat/completions",
								api_key = vim.fn.getenv("TOGETHER")
							},
							schema = {
								model = {
									default = "meta-llama/Llama-3.3-70B-Instruct-Turbo-Free"
									-- default = "deepseek-ai/DeepSeek-R1-Distill-Llama-70B-free"
								},
								-- messages = params.messages,
								-- temperature = params.temperature or 0.7,
								-- max_tokens = params.max_tokens or 2048,
								-- top_p = params.top_p or 0.9,
							},
						}
					)
				end,
				-- opts = {
				-- 	allow_insecure = true,
				-- 	proxy = "socks5://127.0.0.1:2080",
				-- },
			},
		},
		config = function(_, opts)
			require("codecompanion").setup(opts)
		end,
	}
}
