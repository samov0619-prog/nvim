local colors = {
	yellow = '#ECBE7B',
	cyan = '#008080',
	darkblue = '#081633',
	green = '#98be65',
	orange = '#FF8800',
	violet = '#a9a1e1',
	magenta = '#c678dd',
	blue = '#51afef',
	red = '#ec5f67'
}

local function throttle(fn, interval_ms)
	local cache = { ts = 0, result = '' }
	return function()
		local now = vim.loop.hrtime() / 1e6 -- время в мс
		if (now - cache.ts) > interval_ms then
			cache.result = fn()
			cache.ts = now
		end
		return cache.result
	end
end

local git = {}
git.info_cache = {}

function git.get_aware_filename()
	local fullpath = vim.fn.expand('%:p')
	if not fullpath:match('diffview://') then
		return nil
	end
	return vim.fn.expand('%:t')
end

function git.get_info()
	local fullpath = vim.fn.expand('%:p')
	if not fullpath:match('diffview://') then
		return nil
	end

	-- Используем кеш для оптимизации
	if git.info_cache[fullpath] then
		return git.info_cache[fullpath]
	end

	local info = {}

	-- Обработка merge стадий
	local stage = fullpath:match(':(%d+):')
	if stage then
		local stage_names = {
			['0'] = 'result',
			['1'] = '$orig',
			['2'] = 'HEAD',
			['3'] = 'MERGE_HEAD'
		}
		info.stage = stage_names[stage]
		info.sha = nil
		info.author = nil
	else
		-- Извлечение SHA коммита
		local sha = fullpath:match('/%.git/worktrees/[^/]+/([a-f0-9]+)/')
		if not sha then
			sha = fullpath:match('/%.git/([a-f0-9]+)/')
		end

		if sha then
			info.sha = sha:sub(1, 7)
			info.stage = nil

			-- Получение автора через git команду
			local cmd = string.format('git show -s --format="%%an" %s 2>/dev/null', sha)
			local handle = io.popen(cmd)
			if handle then
				local author = handle:read('*a')
				handle:close()

				if author and author:match('%S') then
					info.author = author:gsub('^%s*(.-)%s*$', '%1')
				end
			end
		end
	end

	git.info_cache[fullpath] = info
	return info
end

function git.get_stage_info()
	local info = git.get_info()
	return info and (info.stage or info.sha) or nil
end

function git.get_commit_author()
	local info = git.get_info()
	return info and info.author or nil
end

local function _git_ahead_behind()
	local ok = os.execute('git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1')
	if ok ~= 0 then
		return ''
	end

	local handle = io.popen('git rev-list --left-right --count @{u}...HEAD 2>/dev/null')
	if not handle then return '' end
	local out = handle:read('*l')
	handle:close()
	if not out or out == '' then return '' end

	local behind, ahead = out:match('(%d+)%s+(%d+)')
	ahead = tonumber(ahead) or 0
	behind = tonumber(behind) or 0

	if ahead == 0 and behind == 0 then
		return ''
	end

	local parts = {}
	if ahead > 0 then table.insert(parts, '↑' .. ahead) end
	if behind > 0 then table.insert(parts, '↓' .. behind) end

	return table.concat(parts, ' ')
end

local git_ahead_behind = throttle(_git_ahead_behind, 5000)

return {
	{
		'nvim-lualine/lualine.nvim',
		dependencies = {
			'nvim-tree/nvim-web-devicons',
			'arkav/lualine-lsp-progress',
			'tpope/vim-obsession'
		},
		config = function()
			require('lualine').setup({
				options = {
					always_show_tabline = false,
				},
				sections = {
					lualine_b = {
						"branch",
						{
							git_ahead_behind,
							color = { fg = colors.orange },
						},
						"diff",
						"diagnostics"
					},
					lualine_c = {
						{
							-- Простая функция LSP клиентов - оставляем inline
							function()
								local clients = vim.lsp.get_clients({ bufnr = vim.api.nvim_get_current_buf() })
								local lsp_names = {}

								for _, client in pairs(clients) do
									table.insert(lsp_names, client.name)
								end

								return table.concat(lsp_names, ", ") or "no_lsp"
							end,
							icon = '󱏒',
							color = { fg = '#c678dd', gui = 'bold' },
						},
						{
							'lsp_progress',
							colors = {
								percentage      = colors.cyan,
								title           = colors.cyan,
								message         = colors.cyan,
								spinner         = colors.cyan,
								lsp_client_name = colors.magenta,
								use             = true,
							},
							separators = {
								component = ' ',
								progress = ' | ',
								message = {
									pre = '(',
									post = ')',
									commenced = 'In Progress',
									completed = 'Completed',
								},
								percentage = { pre = '', post = '%% ' },
								title = { pre = '', post = ': ' },
								lsp_client_name = { pre = '[', post = ']' },
								spinner = { pre = '', post = '' },
							},
							display_components = { 'lsp_client_name', 'spinner', { 'title', 'percentage' } },
							timer = { progress_enddelay = 100, spinner = 1000, lsp_client_name_enddelay = 100 },
							spinner_symbols = { '🌑 ', '🌒 ', '🌓 ', '🌔 ', '🌕 ', '🌖 ', '🌗 ', '🌘 ' },
						},
					},
					lualine_x = {
						{
							-- Простая функция линтеров - оставляем inline
							function()
								local linters = require("lint").get_running()
								if #linters == 0 then
									return "󰦕"
								end
								return "󱉶 " .. table.concat(linters, ", ")
							end
						},
						'filesize',
						'encoding',
						'fileformat',
						'filetype'
					}
				},
				inactive_sections = {
					lualine_c = {}
				},
				tabline = {
					lualine_z = {
						{
							"tabs",
							mode = 1,
						},
					}
				},
				winbar = {
					lualine_a = {
						{
							-- Функция filename с git интеграцией - использует git модуль
							function()
								local git_result = git.get_aware_filename()
								if git_result then
									return git_result
								else
									return require('lualine.components.filename'):new({
										path = 3,
										shorting_target = 10,
									}):update_status()
								end
							end,
							separator = '',
							color = function()
								return vim.bo.modified and { fg = "#e61616" } or nil
							end
						},
						{
							git.get_stage_info,
							separator = '',
							color = { gui = 'bold' },
							cond = function()
								return git.get_stage_info() ~= nil
							end
						},
						{
							git.get_commit_author,
							separator = '',
							color = { fg = "#888888" },
							cond = function()
								return git.get_commit_author() ~= nil
							end,
							fmt = function(str)
								return "(" .. str .. ")"
							end
						}
					},
					lualine_z = {
						{
							-- Простая функция сессии - оставляем inline
							function()
								local status = vim.fn.ObsessionStatus()
								return #status == 0 and '[]' or status
							end,
							color = function()
								local status = vim.fn.ObsessionStatus()
								local color = { gui = 'bold' }

								if #status == 0 then
									color.fg = "grey"
									color.bg = "black"
								elseif status == "[S]" then
									color.bg = "grey"
								end

								return color
							end
						}
					}
				},
				inactive_winbar = {
					lualine_a = {
						{
							'filename',
							path = 3,
							shorting_target = 10,
						}
					}
				}
			})
		end
	}
}
