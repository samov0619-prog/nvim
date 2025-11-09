return {
	{
		'stevearc/conform.nvim',
		config = function()
			local util = require("conform.util")
			local project_markers = {
				"package.json",
				"tsconfig.json",
				"biome.json",
				"biome.jsonc",
				".git",
			}

			local function find_biome_config(self, ctx)
				-- Сначала ищем в корне проекта
				local project_root = util.root_file(project_markers)(self, ctx)

				if project_root then
					local project_configs = {
						"biome.json",
						"biome.jsonc",
					}

					for _, config in ipairs(project_configs) do
						local config_path = project_root .. "/" .. config
						if vim.fn.filereadable(config_path) == 1 then
							print("config_path", config_path)
							return config_path
						end
					end
				end

				-- Затем в домашней директории
				local home_config = vim.fn.expand("~/biome.jsonc")
				if vim.fn.filereadable(home_config) == 1 then
					print("home_config", home_config)
					return home_config
				end

				return nil
			end

			local function create_biome_formatter()
				return {
					command = util.from_node_modules("biome") or
					vim.fn.expand("~/.local/share/nvim/mason/packages/biome/node_modules/@biomejs/biome/bin/biome"),
					args = function(self, ctx)
						local config_path = find_biome_config(self, ctx)
						local args = {
							"format",
							"--stdin-file-path",
							"$FILENAME",
						}

						if config_path then
							table.insert(args, 2, "--config-path")
							table.insert(args, 3, config_path)
						end

						return args
					end,
					stdin = true,
					cwd = function(self, ctx)
						-- Пытаемся найти корень проекта
						return util.root_file(project_markers)(self, ctx) or vim.fn.getcwd()
					end,
				}
			end

			require("conform").setup({
				-- log_level = vim.log.levels.DEBUG,
				formatters_by_ft = {
					javascript      = { "biome" },
					javascriptreact = { "biome" },
					typescript      = { "biome" },
					typescriptreact = { "biome" },
					vue             = { "biome" },
					json            = { "biome" },
					html            = { "biome" },
					yaml            = { "biome" },

					css             = { "stylelint" },
					scss            = { "stylelint" },
					markdown        = { "mdformat" },

					sh              = { "beautysh" },
					bash            = { "beautysh" },
					zsh             = { "beautysh" },
				},

				formatters = {
					beautysh = {
						prepend_args = {
							"--indent-size", "4",
							"--tab",
							"--force-function-style", "paronly",
						},
					},
					biome = create_biome_formatter()
				}
			})

			vim.keymap.set("", "<leader>fo", function()
				require("conform").format(
					{
						async = true,
						timeout_ms = 4000,
						lsp_format = "fallback",
					},
					function(err, _)
						if not err then
							local mode = vim.api.nvim_get_mode().mode
							if vim.startswith(mode, "v") then
								vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n",
									true)
							end
						end
					end)
			end, { desc = "Format" })
		end
	},
}
