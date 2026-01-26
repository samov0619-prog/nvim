return {
	{
		"mfussenegger/nvim-lint",
		-- nixos
		enabled = false,
		config = function()
			local lint = require('lint')
			local util = require("lspconfig.util")
			local max_file_size = 1024 * 1024 -- 1MB

			local function has_eslint_config(bufnr)
				bufnr = bufnr or vim.api.nvim_get_current_buf()
				local fname = vim.api.nvim_buf_get_name(bufnr)
				local root = util.root_pattern(
					".eslintrc",
					".eslintrc.js",
					".eslintrc.cjs",
					".eslintrc.json",
					".eslintrc.yaml",
					".eslintrc.yml",
					"eslint.config.js",
					"eslint.config.cjs",
					"eslint.config.mjs",
					"eslint.config.ts"
				)(fname)
				return root ~= nil
			end

			lint.linters_by_ft = {
				javascript = { 'eslint_d' },
				typescript = { 'eslint_d' },
				javascriptreact = { 'eslint_d' },
				typescriptreact = { 'eslint_d' },
			}

			local lint_group = vim.api.nvim_create_augroup("lint", { clear = true })

			vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "InsertLeave" }, {
				group = lint_group,
				callback = function()
					local bufnr = vim.api.nvim_get_current_buf()
					local name = vim.api.nvim_buf_get_name(bufnr)

					if name ~= "" and vim.fn.filereadable(name) == 1 then
						local stat = vim.uv.fs_stat(name)
						if stat and stat.size > max_file_size then
							return
						end

						local ft = vim.bo[bufnr].filetype
						local needs_eslint = lint.linters_by_ft[ft]
							and vim.tbl_contains(lint.linters_by_ft[ft], "eslint_d")

						-- если линтер eslint_d, но конфиг не найден — пропускаем
						if needs_eslint and not has_eslint_config(bufnr) then
							return
						end

						lint.try_lint()
					end
				end,
			})
		end
	}
}
