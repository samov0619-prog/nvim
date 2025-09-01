return {
	{
		"pmizio/typescript-tools.nvim",
		dependencies = { "nvim-lua/plenary.nvim", "neovim/nvim-lspconfig" },
		opts = {
			-- on_attach = function(client)
			-- client.server_capabilities.documentFormattingProvider = false
			-- client.server_capabilities.documentRangeFormattingProvider = false
			-- end,
			filetypes = {
				"javascript",
				"javascriptreact",
				"javascript.jsx",
				"typescript",
				"typescriptreact",
				"typescript.tsx",
				"vue",
			},
		},
		config = function()
			local config = {
				-- -@type Settings
				settings = {
					-- tsserver_format_options = {
						-- convertTabsToSpaces = false,
						-- semicolons = "insert",
					-- },
					-- tsserver_file_preferences = {
					-- 	includeCompletionsForModuleExports = true,
					-- }
				},
			}
			require("typescript-tools").setup(config)
		end
	}
}
