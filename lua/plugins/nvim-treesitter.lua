return {
	{
		"nvim-treesitter/nvim-treesitter",
		dependencies = {
			"nvim-treesitter/nvim-treesitter-textobjects",
			"eandrju/cellular-automaton.nvim",
			"nvim-treesitter/playground"
		},
		---@type TSConfig
		opts = {
			auto_install = false,
			ensure_installed = {
				-- languages
				"bash",
				-- "c",
				-- "clojure",
				-- "fennel",
				"comment",
				"go",
				"gomod",
				"gosum",
				-- "groovy",
				"java",
				"javascript",
				-- "kotlin",
				"lua",
				-- "proto",
				"python",
				-- "rust",
				"scheme",
				"sql",
				"tsx",
				"typescript",
				"vim",
				"vimdoc",
				-- markup
				"css",
				"html",
				"markdown",
				"markdown_inline",
				"mermaid",
				"xml",
				"asm",
				-- config
				"dot",
				"toml",
				"yaml",
				-- data
				"csv",
				"json",
				"json5",
				-- utility
				"diff",
				"ssh_config",
				"printf",
				"disassembly",
				"dockerfile",
				"git_config",
				"git_rebase",
				"gitcommit",
				"gitignore",
				"http",
				"query",
			},
			highlight = {
				enable = true,
				disable = function(lang, buf)
					local max_filesize = 500 * 1024 -- 100 KB
					local ok, stats = pcall(
						vim.loop.fs_stat,
						vim.api.nvim_buf_get_name(buf)
					)
					if ok and stats and stats.size > max_filesize then
						return true
					end
				end,
				additional_vim_regex_highlighting = false,
			},
			ignore_install = {},
			incremental_selection = {
				enable = true,
				keymaps = {
					init_selection = "<C-space>",
					node_incremental = "<C-space>",
					scope_incremental = false,
					node_decremental = "<C-backspace>",
				},
			},
			modules = {
			},
			playground = {
				enable = true,
				updatetime = 25,
				persist_queries = false,
			},
			textobjects = {
				select = {
					enable = true,
					lookahead = true,
					keymaps = {
						["a="] = {
							query = "@assignment.outer",
							desc = "select outer part of an assignment",
						},
						["i="] = {
							query = "@assignment.inner",
							desc = "select inner part of an assignment",
						},
						["r="] = {
							query = "@assignment.rhs",
							desc = "select right hand side of an assignment",
						},

						["aa"] = {
							query = "@parameter.outer",
							desc = "select outer part of a parameter/argument",
						},
						["ia"] = {
							query = "@parameter.inner",
							desc = "select inner part of a parameter/argument",
						},

						--[[ ["ai"] = {
								query = "@conditional.outer",
								desc = "select outer part of a conditional",
							},
							["ii"] = {
								query = "@conditional.inner",
								desc = "select inner part of a conditional",
							}, ]]

						["al"] = {
							query = "@loop.outer",
							desc = "select outer part of a loop",
						},
						["il"] = {
							query = "@loop.inner",
							desc = "select inner part of a loop",
						},

						["ac"] = {
							query = "@call.outer",
							desc = "select outer part of a function call",
						},
						["ic"] = {
							query = "@call.inner",
							desc = "select inner part of a function call",
						},

						["af"] = {
							query = "@function.outer",
							desc = "select outer part of a method/function definition",
						},
						["if"] = {
							query = "@function.inner",
							desc = "select inner part of a method/function definition",
						},

						["at"] = {
							query = "@class.outer",
							desc = "select outer part of a type",
						},
						["it"] = {
							query = "@class.inner",
							desc = "select inner part of a type",
						},

						["an"] = {
							query = "@block.outer",
							desc = "select inner part of a block",
						},
						["in"] = {
							query = "@block.inner",
							desc = "select outer part of a block",
						},
					},
				},
				move = {
					enable = true,
					set_jumps = true,
					goto_next_start = {
						["]m"] = { query = "@function.outer", desc = "next function start" },
						["]i"] = { query = "@conditional.outer", desc = "next conditional start" },
					},
					goto_next_end = {
						["]M"] = { query = "@function.outer", desc = "next function end" },
						["]I"] = { query = "@conditional.outer", desc = "next conditional end" },
					},
					goto_previous_start = {
						["[m"] = { query = "@function.outer", desc = "prev function start" },
						["[i"] = { query = "@conditional.outer", desc = "prev conditional start" },
					},
					goto_previous_end = {
						["[M"] = { query = "@function.outer", desc = "prev function end" },
						["[I"] = { query = "@conditional.outer", desc = "prev conditional end" },
					},
				},
				swap = {
					enable = true,
					swap_next = {
						["<leader>man"] = { query = "@parameter.inner", desc = "swap next parameter" },
						["<leader>mfn"] = { query = "@function.outer", desc = "swap next function" },
						["<leader>mcn"] = { query = "@class.outer", desc = "swap next class" },
						["<leader>mpn"] = { query = "@attribute.outer", desc = "swap next attribute" },
					},
					swap_previous = {
						["<leader>map"] = { query = "@parameter.inner", desc = "swap prev parameter" },
						["<leader>mfp"] = { query = "@function.outer", desc = "swap prev function" },
						["<leader>mcp"] = { query = "@class.outer", desc = "swap prev class" },
						["<leader>mpp"] = { query = "@attribute.outer", desc = "swap prev attribute" },
					},
				},
			},
			sync_install = false,
		},
		build = ":TSUpdateSync",
		config = function(_, opts)
			require("nvim-treesitter.configs").setup(opts)
			vim.treesitter.language.register("bash", "zsh")
			vim.keymap.set("n", "<leader>mir", "<cmd>CellularAutomaton make_it_rain<CR>")
		end
	}
}
