local opts = { noremap = true, silent = true }

return {
	{
		"neovim/nvim-lspconfig",
		dependencies = {
			"folke/lazydev.nvim",
			"Bilal2453/luvit-meta"
		},
		config = function()
			require("lazydev").setup(
				{
					library = {
						{ path = "luvit-meta/library", words = { "vim%.uv" } },
					},
				}
			)

			vim.lsp.config("*",
				{
					on_attach = function(client, bufnr)
						client.server_capabilities.semanticTokensProvider = nil


						vim.keymap.set(
							"n",
							"<space>lgd",
							vim.lsp.buf.definition,
							vim.tbl_extend('force', { buffer = bufnr, desc = "go to definition" }, opts)
						)
						vim.keymap.set(
							"n",
							"<space>lgt",
							vim.lsp.buf.type_definition,
							vim.tbl_extend('force', { buffer = bufnr, desc = "go to type definition" }, opts)
						)
						vim.keymap.set(
							"n",
							"<space>lgr",
							vim.lsp.buf.references,
							vim.tbl_extend('force', { buffer = bufnr, desc = "go to references" }, opts)
						)
						vim.keymap.set(
							"n",
							"<space>lgi",
							vim.lsp.buf.implementation,
							vim.tbl_extend('force', { buffer = bufnr, desc = "go to implementation" }, opts)
						)
						vim.keymap.set(
							{ "n", "i" },
							"<C-s>",
							vim.lsp.buf.signature_help,
							vim.tbl_extend('force', { buffer = bufnr, desc = "signature help" }, opts)
						)
						vim.keymap.set(
							{ "n", "i" },
							"<C-a>",
							vim.lsp.buf.hover,
							vim.tbl_extend('force', { buffer = bufnr, desc = "hover" }, opts)
						)
						vim.keymap.set(
							"n",
							"<space>lrn",
							vim.lsp.buf.rename,
							vim.tbl_extend('force', { buffer = bufnr, desc = "rename" }, opts)
						)
						vim.keymap.set(
							{ "n", "v" },
							"<leader>lca",
							vim.lsp.buf.code_action,
							vim.tbl_extend('force', { desc = "code action" }, opts)
						)
						vim.keymap.set("n", "<leader>lrs", function()
							local buf_clients = vim.lsp.get_clients({ bufnr = bufnr })
							local seen = {}
							vim.diagnostic.reset()
							for _, buf_client in ipairs(buf_clients) do
								local name = buf_client.name
								if not seen[name] then
									seen[name] = true
									vim.cmd("LspRestart " .. name)
								end
							end
							vim.notify("LSP restarted", vim.log.levels.INFO)
						end, { desc = "reset diagnostics & restart lsp" })
					end
				}
			)


			vim.lsp.config("bashls", {
				filetypes = {
					"sh", "zsh"
				}
			})

			vim.lsp.config("lua_ls", {
				root_markers = {
					"init.lua",
					".luarc.json",
					".luarc.jsonc",
					".luacheckrc",
					".stylua.toml",
					"stylua.toml",
					"selene.toml",
					"selene.yml",
					".git"
				}

			})

			vim.lsp.config("lemminx", {
				init_options = {
					settings = {
						xml = {
							-- Когда в fonts.conf встретится SYSTEM "urn:fontconfig:fonts.dtd",
							-- подставлять локальный файл /etc/fonts/fonts.dtd
							fileAssociations = {
								{
									systemId = "urn:fontconfig:fonts.dtd",
									uri      = "file:///etc/fonts/fonts.dtd",
									pattern  = "**/fonts.conf",
								},
							},
							-- Необязательно: OASIS‑каталоги мы не используем
							catalogs = {},
						},
					},
				},
			})

			vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter' }, {
				group = vim.api.nvim_create_augroup("HyprlangLsp", { clear = true }),
				pattern = { "*.hl", "hypr*.conf" },
				callback = function()
					vim.lsp.start {
						name = "hyprlang",
						cmd = { "hyprls" },
						root_dir = vim.fn.getcwd(),
					}
				end
			})

			vim.api.nvim_create_autocmd("LspAttach", {
				group = vim.api.nvim_create_augroup("DisableLspForTempFiles", { clear = true }),
				callback = function(args)
					local buf = args.buf
					local filepath = vim.api.nvim_buf_get_name(buf)

					if filepath:match("^/tmp/nvim") then
						vim.diagnostic.enable(false, { bufnr = buf })
					end
				end,
			})
		end,
	}
}
