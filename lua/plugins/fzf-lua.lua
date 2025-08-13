local uv = vim.uv

---Strips "oil://" prefix from a string if present.
---@param path string
---@return string
local function strip_oil_prefix(path)
	local prefix = "oil://"
	if vim.startswith(path, prefix) then
		return path:sub(#prefix + 1)
	end
	return path
end

return {
	{
		"ibhagwan/fzf-lua",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function()
			local fzf = require("fzf-lua")
			local fzf_utils = require "fzf-lua.utils"
			local fzf_path = require "fzf-lua.path"

			local config = {
				git = {
					branches = {
						actions = {
							["ctrl-d"] = function(selected)
								vim.cmd.Git("difftool --name-only " .. selected[1])
							end,
						},
					},
					blame = {
						winopts = {
							preview = {
								layout = "vertical",
								vertical = "down:60%"
							}
						}
					},
				},
				winopts = {
					width = 1,
					height = 0.9,
				},
				zoxide = {
					prompt_title = 'Zoxide',
					actions = {
						["default"] = function(selected)
							local path = selected[1]:match("[^\t]+$") or selected[1]
							require("oil").open(path)
						end,
						["`"] = function(selected, opts)
							local cwd = selected[1]:match("[^\t]+$") or selected[1]
							if opts.cwd then
								cwd = fzf_path.join({ opts.cwd, cwd })
							end
							local git_root = opts.git_root and fzf_path.git_root({ cwd = cwd }, true) or nil
							cwd = git_root or cwd
							if uv.fs_stat(cwd) then
								vim.cmd("cd " .. cwd)
								fzf_utils.io_system({ "zoxide", "add", "--", cwd })
								require("oil").open(cwd)
							end
						end,
						["~"] = function(selected, opts)
							local cwd = selected[1]:match("[^\t]+$") or selected[1]
							if opts.cwd then
								cwd = fzf_path.join({ opts.cwd, cwd })
							end
							local git_root = opts.git_root and fzf_path.git_root({ cwd = cwd }, true) or nil
							cwd = git_root or cwd
							if uv.fs_stat(cwd) then
								vim.cmd("tcd " .. cwd)
								fzf_utils.io_system({ "zoxide", "add", "--", cwd })
								require("oil").open(cwd)
							end
						end,
					},
				},
			}

			fzf.setup(config)

			fzf.register_ui_select()

			vim.keymap.set("n", "<leader>fr", function()
				fzf.resume()
			end, { desc = "find resume" })

			vim.keymap.set("n", "<leader>ff", function()
				fzf.files()
			end, { desc = "find files" })

			vim.keymap.set("v", "<leader>ff", function()
				local input = fzf_utils.get_visual_selection()
				fzf.files({
					fzf_opts = {
						['--query'] = input,
					}
				})
			end, { desc = "find files for selection" })

			vim.keymap.set("n", "<leader>fF", function()
				fzf.files {
					cwd = strip_oil_prefix(vim.fn.expand "%:p:h"),
				}
			end, { desc = "find files in current dir" })

			vim.keymap.set("v", "<leader>fF", function()
				local input = fzf_utils.get_visual_selection()
				fzf.files {
					cwd = strip_oil_prefix(vim.fn.expand "%:p:h"),
					fzf_opts = {
						['--query'] = input,
					}
				}
			end, { desc = "find files in current dir for selection" })

			vim.keymap.set("n", "<leader>fg", function()
				fzf.live_grep()
			end, { desc = "find grep through files" })

			vim.keymap.set("v", "<leader>fg", function()
				fzf.live_grep {
					search = fzf_utils.get_visual_selection(),
				}
			end, { desc = "find grep through files for selection" })

			vim.keymap.set("n", "<leader>fG", function()
				fzf.live_grep {
					cwd = strip_oil_prefix(vim.fn.expand "%:p:h"),
				}
			end, { desc = "find files in current dir" })

			vim.keymap.set("v", "<leader>fG", function()
				fzf.live_grep {
					cwd = strip_oil_prefix(vim.fn.expand "%:p:h"),
					search = fzf_utils.get_visual_selection(),
				}
			end, { desc = "find files in current dir for selection" })

			vim.keymap.set("n", "<leader>fa", function()
				vim.cmd [[FzfLua]]
			end, { desc = "find in commands" })

			vim.keymap.set("n", "<leader>fq", function()
				fzf.quickfix()
			end, { desc = "find in quickfix" })

			vim.keymap.set("n", "<leader>fQ", function()
				fzf.quickfix_stack()
			end, { desc = "find in quickfix stack" })

			vim.keymap.set("n", "<leader>fl", function()
				fzf.loclist()
			end, { desc = "find in loc list" })

			vim.keymap.set("n", "<leader>fL", function()
				fzf.loclist()
			end, { desc = "find in loc list stack" })

			vim.keymap.set("n", "<leader>fs", function()
				fzf.lsp_document_symbols()
			end, { desc = "find document symbols" })

			vim.keymap.set("n", "<leader>fS", function()
				fzf.lsp_live_workspace_symbols()
			end, { desc = "find workspace symbols" })

			vim.keymap.set("n", "<leader>fd", function()
				fzf.diagnostics_document()
			end, { desc = "find document diagnostics" })

			vim.keymap.set("n", "<leader>fD", function()
				fzf.diagnostics_workspace()
			end, { desc = "find workspace diagnostics" })

			vim.keymap.set("n", "<leader>fm", function()
				fzf.marks()
			end, { desc = "find marks" })

			vim.keymap.set("n", "<leader>fh", function()
				fzf.helptags()
			end, { desc = "find help tags" })

			vim.keymap.set("n", "<leader>fk", function()
				fzf.keymaps()
			end, { desc = "find keymaps" })

			vim.keymap.set("n", "<leader>fb", function()
				fzf.buffers()
			end, { desc = "find buffers" })

			vim.keymap.set("n", "<leader>fgs", function()
				fzf.git_status()
			end, { desc = "git status" })

			-- Zoxide

			---Adds directory to zoxide asynchronously
			---@param dir string
			local function add_to_zoxide(dir)
				local clean_dir = strip_oil_prefix(dir)
				vim.fn.jobstart({
					"zoxide", "add", clean_dir
				}, {
					detach = true,
					on_exit = function(_, code)
						if code ~= 0 then
							vim.notify("Failed to add directory to zoxide: " .. clean_dir, vim.log.levels.WARN)
						end
					end
				})
			end

			vim.keymap.set(
				"n",
				"<leader>zxo",
				":FzfLua zoxide<CR>",
				{ desc = "zoxide directories" })

			vim.keymap.set("n", "<leader>zxa", function()
				local buf_path = vim.api.nvim_buf_get_name(0)
				local dir = vim.fn.fnamemodify(buf_path, ":p:h")
				add_to_zoxide(dir)
			end, { desc = "add directory to zoxide" })

			vim.api.nvim_create_autocmd("DirChanged", {
				group = vim.api.nvim_create_augroup("ZoxideIntegration", { clear = true }),
				callback = function(args)
					add_to_zoxide(args.file)
				end,
			})
		end
	}
}
