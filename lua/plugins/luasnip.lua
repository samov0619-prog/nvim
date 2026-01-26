return {
	{
		"L3MON4D3/LuaSnip",
		lazy = true,
		dependencies = { "rafamadriz/friendly-snippets" },
		config = function()
			local ls = require("luasnip")
			local vscode_loader = require("luasnip.loaders.from_vscode")
			ls.config.set_config {
				cut_selection_keys = "<Tab>",
			}
			vscode_loader.lazy_load()
			vscode_loader.lazy_load({ paths = "~/.config/nvim/my-snippets" })
			ls.filetype_extend("typescript", {"tsdoc"})
			ls.filetype_extend("typescriptreact", {"tsdoc"})
			ls.filetype_extend("vue", {"typescriptreact"})
		end,
	}
}
