return {
	-- {
	-- 	'stevearc/conform.nvim',
	-- 	config = function()
	-- 		local util = require("lspconfig.util")
	--
	-- 		-- проверка наличия конфига prettier в корне проекта
	-- 		local function has_prettier_config(bufnr)
	-- 			bufnr = bufnr or vim.api.nvim_get_current_buf()
	-- 			local fname = vim.api.nvim_buf_get_name(bufnr)
	-- 			local root = util.root_pattern(
	-- 				".prettierrc", ".prettierrc.json", ".prettierrc.js",
	-- 				"prettier.config.js", "prettier.config.cjs"
	-- 			)(fname)
	-- 			return root ~= nil
	-- 		end
	--
	-- 		-- единая конфигурация по filetype
	-- 		local ft_config = {
	-- 			-- javascript      = { formatter = "biome", require_prettier = true },
	-- 			-- javascriptreact = { formatter = "biome", require_prettier = true },
	-- 			-- typescript      = { formatter = "biome", require_prettier = true },
	-- 			-- typescriptreact = { formatter = "biome", require_prettier = true },
	-- 			-- vue             = { formatter = "biome", require_prettier = true },
	-- 			-- json            = { formatter = "biome", require_prettier = true },
	-- 			-- html            = { formatter = "biome", require_prettier = true },
	-- 			-- yaml            = { formatter = "biome", require_prettier = true },
	--
	-- 			javascript      = { formatter = "biome" },
	-- 			javascriptreact = { formatter = "biome" },
	-- 			typescript      = { formatter = "biome" },
	-- 			typescriptreact = { formatter = "biome" },
	-- 			vue             = { formatter = "biome" },
	-- 			json            = { formatter = "biome" },
	-- 			html            = { formatter = "biome" },
	-- 			yaml            = { formatter = "biome" },
	--
	-- 			css             = { formatter = "stylelint" },
	-- 			scss            = { formatter = "stylelint" },
	-- 			markdown        = { formatter = "mdformat" },
	--
	-- 			sh              = { formatter = "beautysh" },
	-- 			bash            = { formatter = "beautysh" },
	-- 			zsh             = { formatter = "beautysh" },
	-- 		}
	--
	-- 		-- генерируем таблицу для conform из общей конфигурации
	-- 		local formatters_by_ft = {}
	-- 		for ft, cfg in pairs(ft_config) do
	-- 			formatters_by_ft[ft] = { cfg.formatter, lsp_format = "never" }
	-- 		end
	--
	-- 		require("conform").setup({
	-- 			-- log_level = vim.log.levels.DEBUG,
	-- 			formatters_by_ft = formatters_by_ft,
	--
	-- 			formatters = {
	-- 				beautysh = {
	-- 					prepend_args = {
	-- 						"--indent-size", "4",
	-- 						"--tab",
	-- 						"--force-function-style", "paronly",
	-- 					},
	-- 				},
	-- 				prettier = {
	-- 					prepend_args = { "--end-of-line", "auto", "--no-bracket-spacing", "--print-width", "80", "--single-quote", "--tab-width", "2" },
	-- 					-- оборачиваем prettier в логирующую функцию
	-- 					run = function(self, ...)
	-- 						vim.notify("[FORMAT] Trying prettier")
	-- 						local ok, err = pcall(self.run_orig, self, ...)
	-- 						if not ok then
	-- 							vim.notify("[FORMAT] Prettier failed, falling back to LSP")
	-- 							return vim.lsp.buf.format({
	-- 								bufnr = vim.api.nvim_get_current_buf(),
	-- 								async = false,
	-- 								timeout_ms = 10000
	-- 							})
	-- 						end
	-- 						return err
	-- 					end,
	-- 					run_orig = require("conform.formatters.prettier").run
	-- 				},
	-- 			},
	-- 		})
	--
	-- 		vim.keymap.set("n", "<space>lfr", function()
	-- 			local bufnr = vim.api.nvim_get_current_buf()
	-- 			local ft    = vim.bo[bufnr].filetype
	-- 			local cfg   = ft_config[ft]
	--
	-- 			if cfg and cfg.formatter == "lsp" then
	-- 				vim.notify("[FORMAT] Using LSP formatter")
	-- 				return vim.lsp.buf.format({
	-- 					bufnr = bufnr,
	-- 					async = false,
	-- 					timeout_ms = 10000
	-- 				})
	-- 			end
	--
	-- 			local use_conform = cfg and (
	-- 				not cfg.require_prettier or has_prettier_config(bufnr)
	-- 			)
	--
	-- 			if use_conform then
	-- 				vim.notify(string.format("[FORMAT] Using conform formatter: %s", cfg.formatter))
	--
	-- 				require("conform").format({
	-- 					bufnr      = bufnr,
	-- 					lsp_format = "fallback", -- если CLI-утилита упадёт — вызовем LSP
	-- 				})
	-- 			else
	-- 				vim.notify("[FORMAT] Using LSP formatter")
	-- 				vim.lsp.buf.format({ bufnr = bufnr, async = false, timeout_ms = 10000 })
	-- 			end
	-- 		end, { desc = "format" })
	-- 	end
	-- },
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
							return config_path
						end
					end
				end

				-- Затем в домашней директории
				local home_config = vim.fn.expand("~/biome.jsonc")
				if vim.fn.filereadable(home_config) == 1 then
					return home_config
				end

				return nil
			end

			local function create_biome_formatter()
				return {
					command = util.from_node_modules("biome") or vim.fn.expand("~/.local/share/nvim/mason/packages/biome/node_modules/@biomejs/biome/bin/biome"),
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

			vim.api.nvim_create_user_command("Format",
				function(args)
					local range = nil
					if args.count ~= -1 then
						local end_line = vim.api.nvim_buf_get_lines(0, args.line2 - 1, args.line2, true)[1]
						range = {
							start = { args.line1 - 1, 0 },
							["end"] = { args.line2 - 1, end_line and #end_line or 0 },
						}
					end

					require("conform").format(
						{
							async = true,
							lsp_format = "never",
							range = range,
						},
						function(err, did_edit)
							if not err then
								local mode = vim.api.nvim_get_mode().mode
								if vim.startswith(mode, "v") then
									vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n",
										true)
								end
							end
						end)
				end, { range = true })
			vim.keymap.set("", "<leader>fo", "<cmd>Format<CR>", { desc = "Format code" })
		end
	},
}
