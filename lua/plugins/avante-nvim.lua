return {
	{
		"yetone/avante.nvim",
    enabled = false;
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
		config = function()
			local airun_model = "x5/x5-airun-medium-coder-prod"
			local airun_autocomplete_model = "x5/x5-airun-small-coder-prod"
			local ai_run_embedded_model = "x5/x5-airun-multilingual-e5-large"
			local url = vim.fn.getenv("AI_RUN_2")

			-- конфиг именно airun vim.g из глобального конфига

			---@module 'avante'
			---@type avante.Config
			local cfg = {
				provider = "airun",
				mode = "legacy",
				auto_suggestions_provider = "airun_autocomplete",
				providers = {
					airun = {
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
					},
					airun_autocomplete = {
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
					},
				},
				rag_service = {
					enabled = false,
					host_mount = os.getenv("HOME"),
					runner = "docker", -- Runner for the RAG service (can use docker or nix)
					docker_extra_args = "",
					llm = {
						provider = "airun",
						endpoint = url,
						allow_insecure = true,
						api_key = "AI_RUN_TOKEN",
						model = airun_model,
						extra = {
							temperature = 0.7,
							max_tokens = 512,
						},
					},
					embed = {
						provider = "airun",
						endpoint = url,
						allow_insecure = true,
						api_key = "AI_RUN_TOKEN",
						model = ai_run_embedded_model,
						extra = {
							embed_batch_size = 16,
						},
					},
				},
				behaviour = {
					support_paste_from_clipboard = true,
					use_cwd_as_project_root = true,
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
					}, -- ignore files matching these
				},
				selection = {
					hint_display = "none",
				},
				selector = {
					provider = "fzf_lua",
				},
			}

			require("avante").setup(cfg)

			vim.keymap.set("n", "<leader>aic", "<cmd>AvanteChatNew<CR>", {desc = "Avante Chat New"})
		end,
	},
}
