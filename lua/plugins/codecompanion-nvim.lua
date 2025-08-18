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
				explain = {
					adapter = "copilot_like"
				},
				cmd = {
					adapter = "copilot_like"
				},
				-- chat = {
				-- 	adapter = "together",
				-- },
				-- inline = {
				-- 	adapter = "together",
				-- },
				-- actions = {
				-- 	adapter = "together"
				-- },
				-- files = {
				-- 	adapter = "together"
				-- },
				-- explain = {
				-- 	adapter = "together"
				-- },
				-- cmd = {
				-- 	adapter = "together"
				-- },
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
				copilot_like = function()
					-- return {
					-- 	name = "copilot_like",
					-- 	-- Используем базовый адаптер, но с минимальными настройками
					-- 	url = vim.fn.getenv("COPILOT_LIKE_URL") .. "/chat/completions",
					--
					-- 	-- Функция для обработки запроса - здесь мы полностью контролируем формат
					-- 	handlers = {
					-- 		form_parameters = function(params, messages)
					-- 			-- Формируем точно такое же тело запроса, как в вашем curl
					-- 			return {
					-- 				model = "x5-airun-medium-coder-prod", -- Ваша модель
					-- 				messages = messages,  -- Сообщения передаются как есть
					-- 				-- Добавьте другие параметры при необходимости
					-- 				temperature = params.temperature or 0.7,
					-- 				max_tokens = params.max_tokens or 2048,
					-- 				top_p = params.top_p or 0.9,
					-- 			}
					-- 		end,
					--
					-- 		form_headers = function(env)
					-- 			-- Формируем точно такие же заголовки, как в curl
					-- 			return {
					-- 				["Content-Type"] = "application/json",
					-- 				["Authorization"] = "Bearer " .. vim.fn.getenv("COPILOT_LIKE"),
					-- 			}
					-- 		end,
					-- 	},
					--
					-- 	-- Схема для UI (какие параметры показывать пользователю)
					-- 	schema = {
					-- 		model = {
					-- 			type = "string",
					-- 			default = "x5-airun-medium-coder-prod",
					-- 			desc = "Model to use for completion"
					-- 		},
					-- 		temperature = {
					-- 			type = "number",
					-- 			default = 0.7,
					-- 			desc = "Sampling temperature"
					-- 		},
					-- 		max_tokens = {
					-- 			type = "number",
					-- 			default = 2048,
					-- 			desc = "Maximum number of tokens"
					-- 		},
					-- 		top_p = {
					-- 			type = "number",
					-- 			default = 0.9,
					-- 			desc = "Top-p sampling parameter"
					-- 		}
					-- 	}
					-- }
					return require("codecompanion.adapters").extend(
						"openai_compatible",
						{
							name = "Copilot-Code v0.1.2",
							env = {
								url = vim.fn.getenv("COPILOT_LIKE_URL"),
								api_key = vim.fn.getenv("COPILOT_LIKE"),
								chat_url = "/chat/completions",
							},
							roles = {
								-- llm = "assistant",    -- Роль для ответов AI
								user = "user", -- Роль для сообщений пользователя
								-- system = "system"     -- Роль для системных инструкций
							},
							schema = {
								-- provider = { default = "x5" },
								model = { default = "x5-airun-medium-coder-prod" },
								-- temperature = { default = 0.5 },
								-- top_p = { default = 1 },
								-- frequency_penalty = { default = 0.5 },
								-- presence_penalty = { default = 0.5 },
								-- max_tokens = { default = 1000 },
								-- n = { default = 1 },
								-- seed = { default = 12 },
								-- stop = { default = { "\n" } },
								-- logit_bias = { default = { ["22"] = 0 } },
								-- stream = { default = false },
							},
							headers = {
								["Content-Type"] = "application/json"
							}
							-- ,
							-- requestOptions = {
							-- 	caBundlePath = "/home/amtea/Downloads/RootCA_new.crt"
							-- }
						}
					)
				end
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
