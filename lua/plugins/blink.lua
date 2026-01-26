return {
	{
		'saghen/blink.cmp',
		version = '1.*',
		-- enabled = false,
		dependencies = {
			'L3MON4D3/LuaSnip',
			"moyiz/blink-emoji.nvim",
			'Kaiser-Yang/blink-cmp-avante',
		},
		---@module 'blink.cmp'
		---@type blink.cmp.Config
		opts = {
			snippets = { preset = 'luasnip' },
			completion = {
				ghost_text = {
					enabled = true,
					show_with_menu = false,
				},
				list = {
					selection = { preselect = true, auto_insert = false }
				},
				menu = {
					auto_show = false,
					-- you may want to set the following options
					-- completion.menu.auto_show = false -- only show menu on manual <C-space>
					draw = {
						components = {
							label_description = {
								width = {
									fill = true,
									max = 60,
								},
							},
							label = {
								width = { fill = true, max = 100 },
								text = function(ctx)
									local label = ctx.label or ''
									local max_width = 100
									local label_width = vim.fn.strdisplaywidth(label)

									if label_width > max_width then
										local start = label_width - max_width + 1
										label = vim.fn.strcharpart(label, start, max_width)
										label = '…' .. label
									end

									return label
								end
							}
						}
					}
				},
			},
			signature = { enabled = false },
			fuzzy = {
				implementation = 'lua',
				prebuilt_binaries = {
					download = false,
				},
			},
			keymap = {
				['<C-space>'] = { 'show', 'show_documentation', 'hide_documentation', 'fallback' },
				['<CR>'] = { 'accept', 'fallback' },

				['C-n'] = { 'select_next', 'snippet_forward', 'fallback' },
				['C-p'] = { 'select_prev', 'snippet_backward', 'fallback' },
			},
			sources = {
				default = { 'avante', 'lsp', 'path', 'snippets', 'buffer', 'emoji' },
				providers = {
					avante = {
						module = 'blink-cmp-avante',
						name = 'Avante',
						opts = {
							-- options for blink-cmp-avante
						}
					},
					emoji = {
						module = "blink-emoji",
						name = "Emoji",
						score_offset = 15, -- Tune by preference
						-- min_keyword_length = 2,
						opts = {
							---@type string|table|fun():table
							trigger = { ":" }
						},
						should_show_items = function()
							return true
						end
					},
					cmdline = {
						min_keyword_length = function(ctx)
							-- when typing a command, only show when the keyword is 3 characters or longer
							if ctx.mode == 'cmdline' and string.find(ctx.line, ' ') == nil then return 3 end
							return 0
						end
					},
				}
			},
			cmdline = {
				completion = {
					menu = {
						auto_show = function(ctx)
							return vim.fn.getcmdtype() == ':' or vim.fn.getcmdtype() == '@'
							-- enable for inputs as well, with:
							-- or vim.fn.getcmdtype() == '@'
						end,
						draw = {
							columns = { { 'kind_icon' }, { 'label', gap = 1 } },
						}
					}
				},
				keymap = {
					['<CR>'] = { 'accept', 'fallback' }
				}
			}
		},
		opts_extend = { "sources.default" }
	},
	{
		'windwp/nvim-autopairs',
		event = "InsertEnter",
		opts = {}
	},
	{
		"windwp/nvim-ts-autotag",
		dependencies = { "nvim-treesitter/nvim-treesitter" },
		event = "InsertEnter",
		opts = {}
	},
}
