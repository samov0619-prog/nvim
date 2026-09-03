local uv = vim.uv

-- (maybe backup) Зачем нужен был strip_fyler_prefix:
--   у oil/fyler имя буфера идёт со схемой (oil:// , fyler://). Когда фокус был В самом
--   explorer'е и ты жал "поиск в текущем каталоге", vim.fn.expand("%:p:h") возвращал
--   путь СО схемой -> fzf получал битый cwd. Strip срезал схему.
--   В zoxide-экшенах он был лишь подстраховкой (zoxide отдаёт чистые абсолютные пути).
--   На mini.files фиксированный strip не подходит: имя minifiles://<id>/<path> (есть id-сегмент),
--   поэтому вместо strip используем current_dir() ниже — он берёт реальный путь через API mini.files.
---Strips "oil://" or "fyler://" prefix from a string if present.
---@param path string
---@return string
-- local function strip_fyler_prefix(path)
-- 	local prefix = "fyler://"
-- 	if vim.startswith(path, prefix) then
-- 		return path:sub(#prefix + 1)
-- 	end
-- 	return path
-- end
-- local function strip_oil_prefix(path)
-- 	local prefix = "oil://"
-- 	if vim.startswith(path, prefix) then
-- 		return path:sub(#prefix + 1)
-- 	end
-- 	return path
-- end

return {
	{
		"ibhagwan/fzf-lua",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function()
			local fzf = require("fzf-lua")
			local fzf_utils = require "fzf-lua.utils"
			local fzf_path = require "fzf-lua.path"
			-- local fyler = require("fyler") -- (maybe backup)
			local mini_files = require("mini.files")

			-- Реальный каталог "текущего места" (замена strip_fyler_prefix(expand "%:p:h")):
			-- - в mini.files (имя minifiles://<id>/<path>) берём путь через его API
			-- - в обычном файле — каталог файла
			local function current_dir()
				local name = vim.api.nvim_buf_get_name(0)
				if name:match("^minifiles://") then
					local ok, mf = pcall(require, "mini.files")
					if ok then
						local entry = mf.get_fs_entry()
						if entry then return vim.fs.dirname(entry.path) end
					end
				end
				return vim.fn.expand("%:p:h")
			end

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
							-- path = strip_fyler_prefix(path) -- (maybe backup) zoxide и так даёт чистый путь
							-- Open using fyler API
							-- fyler.open({ root_path = path }) -- (maybe backup)
              if uv.fs_stat(path) then
                vim.cmd.cd({ args = { vim.fn.fnameescape(path) }, mods = { silent = true } })
                mini_files.open(path)
              else
                mini_files.open(path)
              end
						end,
						["`"] = function(selected, opts)
							local cwd = selected[1]:match("[^\t]+$") or selected[1]
							-- fix: zoxide отдаёт абсолютные пути; join только для относительных
							if opts.cwd and not vim.startswith(cwd, "/") then
								cwd = fzf_path.join({ opts.cwd, cwd })
							end
							local git_root = opts.git_root and fzf_path.git_root({ cwd = cwd }, true) or nil
							cwd = git_root or cwd
							-- cwd = strip_fyler_prefix(cwd) -- (maybe backup) zoxide и так даёт чистый путь
							if uv.fs_stat(cwd) then
								-- fix: экранируем путь (пробелы/спецсимволы)
								vim.cmd.cd({ args = { vim.fn.fnameescape(cwd) }, mods = { silent = true } })
								-- fix: убрано двойное добавление — DirChanged-автокоманда ниже сама зовёт zoxide add
								-- fzf_utils.io_system({ "zoxide", "add", "--", cwd })
								-- fyler.open({ root_path = cwd }) -- (maybe backup)
								mini_files.open(cwd)
							end
						end,
						["~"] = function(selected, opts)
							local cwd = selected[1]:match("[^\t]+$") or selected[1]
							-- fix: zoxide отдаёт абсолютные пути; join только для относительных
							if opts.cwd and not vim.startswith(cwd, "/") then
								cwd = fzf_path.join({ opts.cwd, cwd })
							end
							local git_root = opts.git_root and fzf_path.git_root({ cwd = cwd }, true) or nil
							cwd = git_root or cwd
							-- cwd = strip_fyler_prefix(cwd) -- (maybe backup) zoxide и так даёт чистый путь
							if uv.fs_stat(cwd) then
								-- fix: экранируем путь (пробелы/спецсимволы)
								vim.cmd.tcd({ args = { vim.fn.fnameescape(cwd) }, mods = { silent = true } })
								-- fix: убрано двойное добавление — DirChanged-автокоманда ниже сама зовёт zoxide add
								-- fzf_utils.io_system({ "zoxide", "add", "--", cwd })
								-- fyler.open({ root_path = cwd }) -- (maybe backup)
								mini_files.open(cwd)
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
					-- (maybe backup) было: strip_fyler_prefix(vim.fn.expand "%:p:h")
					cwd = current_dir(),
				}
			end, { desc = "find files in current dir" })

			vim.keymap.set("v", "<leader>fF", function()
				local input = fzf_utils.get_visual_selection()
				fzf.files {
					-- (maybe backup) было: strip_fyler_prefix(vim.fn.expand "%:p:h")
					cwd = current_dir(),
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
					-- (maybe backup) было: strip_fyler_prefix(vim.fn.expand "%:p:h")
					cwd = current_dir(),
				}
			end, { desc = "find files in current dir" })

			vim.keymap.set("v", "<leader>fG", function()
				fzf.live_grep {
					-- (maybe backup) было: strip_fyler_prefix(vim.fn.expand "%:p:h")
					cwd = current_dir(),
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
				-- (maybe backup) было: local clean_dir = strip_fyler_prefix(dir)
				local clean_dir = dir
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
