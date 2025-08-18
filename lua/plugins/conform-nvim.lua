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
						prepend_args = { "--use-tabs", "--tab-width", "4" },
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
				local bufnr       = vim.api.nvim_get_current_buf()
				local ft          = vim.bo[bufnr].filetype
				local cfg         = ft_config[ft]

				-- подключаем conform только если есть конфиг для этого ft
				-- и (если require_prettier == true) — есть конфиг prettier в проекте
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
		end
	}
}
