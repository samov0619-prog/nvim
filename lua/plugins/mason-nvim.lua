return {
	{
		"mason-org/mason.nvim",
		event = "VeryLazy",
		dependencies = {
			"mason-org/mason-lspconfig.nvim",
		},
		config = function()
			local mason = require "mason"
			local mason_lspconfig = require("mason-lspconfig")

			mason.setup {
				PATH = "append",
				ui = {
					icons = {
						package_installed = "✓",
						package_pending = "➜",
						package_uninstalled = "✗",
					},
				},
			}

			mason_lspconfig.setup(
				{
					automatic_enable = true,
					ensure_installed = {
						"bashls",
						"cssls",
						"css_variables",
						"cssmodules_ls",
						-- "eslint",
						"html",
						"jsonls",
						"hyprls",
						"lua_ls",
						"stylelint_lsp",
						"marksman",
						"lemminx",
						"jdtls",
						-- "ts_ls",
					}
				}
			)
		end,
	},
	{
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		config = function()
			require('mason-tool-installer').setup {
				ensure_installed = {
					"prettier",
					"eslint_d",
					"biome",
					"stylelint",
					"shfmt",
					"mdformat",
					"js-debug-adapter"
				},
				run_on_start = true,
				debounce_hours = 5, -- at least 5 hours between attempts to install/update
			}
		end
	}
}
