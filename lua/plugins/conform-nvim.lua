return {
	{
		'stevearc/conform.nvim',
		config = function()
			local util = require("lspconfig.util")

			-- проверка наличия конфига prettier в корне проекта
			local function has_prettier_config(bufnr)
				bufnr = bufnr or vim.api.nvim_get_current_buf()
				local fname = vim.api.nvim_buf_get_name(bufnr)
				local root = util.root_pattern(
					".prettierrc", ".prettierrc.json", ".prettierrc.js",
					"prettier.config.js", "prettier.config.cjs"
				)(fname)
				return root ~= nil
			end

			-- единая конфигурация по filetype
			local ft_config = {
				javascript      = { formatter = "prettier", require_prettier = true },
				javascriptreact = { formatter = "prettier", require_prettier = true },
				typescript      = { formatter = "prettier", require_prettier = true },
				typescriptreact = { formatter = "prettier", require_prettier = true },
				vue             = { formatter = "prettier", require_prettier = true },
				json            = { formatter = "prettier", require_prettier = true },
				html            = { formatter = "prettier", require_prettier = true },
				yaml            = { formatter = "prettier", require_prettier = true },

				css             = { formatter = "stylelint" },
				scss            = { formatter = "stylelint" },
				markdown        = { formatter = "mdformat" },

				sh              = { formatter = "beautysh" },
				bash            = { formatter = "beautysh" },
				zsh             = { formatter = "beautysh" },
			}

			-- генерируем таблицу для conform из общей конфигурации
			local formatters_by_ft = {}
			for ft, cfg in pairs(ft_config) do
				formatters_by_ft[ft] = { cfg.formatter, lsp_format = "fallback" }
			end

			require("conform").setup({
				-- log_level = vim.log.levels.DEBUG,
				formatters_by_ft = formatters_by_ft,

				formatters = {
					beautysh = {
						prepend_args = {
							"--indent-size", "4",
							"--tab",
							"--force-function-style", "paronly",
						},
					},
					prettier = {
						prepend_args = { "--end-of-line", "auto", "--no-bracket-spacing", "--print-width", "80", "--single-quote", "--tab-width", "2" },
						-- оборачиваем prettier в логирующую функцию
						run = function(self, ...)
							vim.notify("[FORMAT] Trying prettier")
							local ok, err = pcall(self.run_orig, self, ...)
							if not ok then
								vim.notify("[FORMAT] Prettier failed, falling back to LSP")
								return vim.lsp.buf.format({
									bufnr = vim.api.nvim_get_current_buf(),
									async = false,
									timeout_ms = 10000
								})
							end
							return err
						end,
						run_orig = require("conform.formatters.prettier").run
					},
				},
			})

			vim.keymap.set("n", "<space>lfr", function()
				local bufnr = vim.api.nvim_get_current_buf()
				local ft    = vim.bo[bufnr].filetype
				local cfg   = ft_config[ft]

				if cfg and cfg.formatter == "lsp" then
					vim.notify("[FORMAT] Using LSP formatter")
					return vim.lsp.buf.format({
						bufnr = bufnr,
						async = false,
						timeout_ms = 10000
					})
				end

				local use_conform = cfg and (
					not cfg.require_prettier or has_prettier_config(bufnr)
				)

				if use_conform then
					vim.notify(string.format("[FORMAT] Using conform formatter: %s", cfg.formatter))

					require("conform").format({
						bufnr      = bufnr,
						lsp_format = "fallback", -- если CLI-утилита упадёт — вызовем LSP
					})
				else
					vim.notify("[FORMAT] Using LSP formatter")
					vim.lsp.buf.format({ bufnr = bufnr, async = false, timeout_ms = 10000 })
				end
			end, { desc = "format" })
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
					vim.notify("[FORMAT] fo")
					require("conform").format(
					{
						formatters = { "biome" },
						async = true,
						lsp_format = "fallback",
						range = range,
					},
						function(err)
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
	-- {
	-- 	"mhartington/formatter.nvim",
	-- 	config = function()
	-- 		local defaults = require("formatter.defaults")
	-- 		local util = require("formatter.util")
	-- 		-- M.eslint_d = util.copyf(defaults.eslint_d)
	-- 		require("formatter").setup({
	-- 			filetype = {
	-- 				typescriptreact = {
	-- 					require("formatter.filetypes.typescriptreact").eslint
	-- function()
	-- 	return {
	-- 		exe = "eslint_d",
	-- 		args = {
	-- 			"--stdin",
	-- 			"--stdin-filename",
	-- 			util.escape_path(util.get_current_buffer_file_path()),
	-- 			"--fix-to-stdout",
	-- 			"--config",
	-- 			util.escape_path("~/.config/eslint-default/.eslintrc.js")
	-- 		},
	-- 		stdin = true,
	-- 		try_node_modules = true,
	-- 	}
	-- end
	-- 				}
	-- 			}
	-- 		})
	--
	-- 		vim.keymap.set("", "<leader>fo", "<cmd>Format<CR>", {})
	-- 	end
	-- }
}
