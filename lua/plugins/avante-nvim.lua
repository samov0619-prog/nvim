return {
	{
		"yetone/avante.nvim",
		dependencies = {
			"nvim-treesitter/nvim-treesitter",
			"nvim-lua/plenary.nvim",
			"MunifTanjim/nui.nvim",
			"nvim-tree/nvim-web-devicons",
			"MeanderingProgrammer/render-markdown.nvim",
			"ibhagwan/fzf-lua",
		},
		build = vim.fn.has("win32") ~= 0
			and "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false"
			or "make",
		event = "VeryLazy",
		---@module 'avante'
		---@type avante.Config
		opts = {
			mode = "agentic",

			mappings = {
				suggestion = {
					accept = "<M-l>",
					next = "<M-]>",
					prev = "<M-[>",
					dismiss = "<C-]>",
				},
			},
			debug = false,
			providers = {},
			web_search_engine = {},
			behaviour = {
				auto_focus_sidebar = true,
				auto_suggestions = false,
				auto_suggestions_respect_ignore = false,
				auto_set_highlight_group = true,
				auto_set_keymaps = true,
				auto_apply_diff_after_generation = false,
				jump_result_buffer_on_finish = false,
				support_paste_from_clipboard = true,
				minimize_diff = true,
				enable_token_counting = true,
				use_cwd_as_project_root = true,
				auto_focus_on_diff_view = true,
			},
			repo_map = {
				ignore_patterns = {
					"%.git",
					"%.worktree",
					"__pycache__",
					"node_modules",
					"target",
					"build",
					"dist",
					"BUILD",
					"ventor%.",
					"%.min%.",
					".devenv",
				},        -- ignore files matching these
				negate_patterns = {}, -- negate ignore files matching these.
			},
			rag_service = { -- RAG Service configuration
				enabled = false,
				host_mount = os.getenv("HOME"),
				runner = "docker", -- Runner for the RAG service (can use docker or nix)
				docker_extra_args = "",
			},
			selector = {
				provider = "fzf_lua",
			},
		},
		config = function(_, opts)
			local airun_model = "x5-airun-medium-coder-prod"
			local airun_autocomplete_model = "x5-airun-small-coder-prod"
			local ai_run_embedded_model = "x5-airun-multilingual-e5-large"
			local url = vim.fn.getenv("AI_RUN")

			local modify_config = function(cfg)
				-- конфиг иименно airun vim.g из глобального конфига

				cfg.provider = "airun"
				cfg.mode = "legacy"
				cfg.auto_suggestions_provider = "airun_autocomplete"
				cfg.providers.airun = {
					__inherited_from = "openai",
					endpoint = url,
					api_key_name = "AI_RUN_TOKEN",
					model = airun_model,
					disable_tools = true,
					allow_insecure = true,
					extra = {
						temperature = 0.7,
						max_tokens = 512,
					},
				}
				cfg.providers.airun_autocomplete = {
					__inherited_from = "openai",
					endpoint = url,
					allow_insecure = true,
					api_key_name = "AI_RUN_TOKEN",
					model = airun_autocomplete_model,
					disable_tools = true,
					extra = {
						temperature = 0.2,
						max_tokens = 250,
					},
				}
				cfg.rag_service.enabled = false
				cfg.rag_service.llm = {
					provider = "airun",
					endpoint = url,
					allow_insecure = true,
					api_key = "AI_RUN_TOKEN",
					model = airun_model,
					extra = {
						temperature = 0.7,
						max_tokens = 512,
					},
				}
				cfg.rag_service.embed = {
					provider = "airun",
					endpoint = url,
					allow_insecure = true,
					api_key = "AI_RUN_TOKEN",
					model = ai_run_embedded_model,
					extra = {
						embed_batch_size = 16,
					},
				}

				return cfg
			end

			opts = modify_config(opts)

			require("avante").setup(opts)
		end,
	},
}
