local M = {}

-- Функция для получения корневой директории основного git репозитория
-- Работает корректно даже если мы находимся в воркспейсе
local function get_main_git_root()
	-- Получаем список всех воркспейсов
	-- Первая строка всегда содержит основной репозиторий
	local handle = io.popen('git worktree list 2>/dev/null')
	if not handle then return nil end

	local first_line = handle:read('*l')
	handle:close()

	if first_line and first_line ~= '' then
		-- Парсим первую строку: путь хеш [ветка]
		local main_repo_path = vim.split(first_line, '%s+')[1]
		return main_repo_path
	end
	return nil
end

local function extract_meaningful_branch_name(branch_name)
	local cleaned = vim.trim(branch_name)

	-- Если нет "/", возвращаем как есть
	if not cleaned:find("/") then
		return cleaned
	end

	-- Разбиваем по "/" и берем непустые части
	local parts = {}
	for part in cleaned:gmatch("[^/]+") do
		if part and part ~= "" then
			table.insert(parts, part)
		end
	end

	if #parts == 0 then
		return cleaned -- fallback на полное название
	end

	local last_part = parts[#parts]

	-- Если последняя часть слишком короткая или выглядит как версия,
	-- берем две последние части
	if #last_part <= 2 or last_part:match("^v%d+$") or last_part:match("^%d+$") then
		if #parts >= 2 then
			return parts[#parts - 1] .. "-" .. last_part
		end
	end

	return last_part
end

M.git_worktrees = function()
	local fzf = require('fzf-lua')
	local git_worktree = require('git-worktree')

	local parse_entry = function(entry)
		local parsed = vim.split(entry, '%s+')
		return {
			path = parsed[1],
			hash = parsed[2],
			branch = parsed[3]:sub(2, #parsed[3] - 1),
		}
	end

	local switch_worktree = function(selected)
		local parsed = parse_entry(selected[1])
		git_worktree.switch_worktree(parsed.path)
	end

	local delete_worktree = function(selected)
		local parsed = parse_entry(selected[1])
		vim.ui.input({ prompt = 'Delete worktree ' .. parsed.branch .. '? [y/N] ' }, function(input)
			if input and input:lower() == 'y' then
				git_worktree.delete_worktree(parsed.path, true)
			end
		end)
	end

	-- Улучшенная функция создания воркспейса с использованием fzf-lua.git_branches
	local create_worktree = function()
		local git_root = get_main_git_root()
		if not git_root then
			vim.notify('Not in a git repository', vim.log.levels.ERROR)
			return
		end

		-- Получаем имя репозитория для создания папки worktrees
		local repo_name = vim.fn.fnamemodify(git_root, ':t')
		local worktrees_dir = git_root .. '-worktrees'

		-- Используем встроенный git_branches API из fzf-lua
		-- Он уже умеет правильно показывать и форматировать ветки
		fzf.git_branches({
			prompt = 'Select branch for new worktree> ',
			-- Включаем как локальные, так и удаленные ветки
			cmd = "git branch --all --color=never",
			actions = {
				['default'] = function(selected)
					if not selected or #selected == 0 then return end

					-- git_branches возвращает строку в формате, который может содержать
					-- префиксы вроде "remotes/origin/" или пробелы в начале
					local branch_line = selected[1]

					-- Очищаем строку от служебных символов и префиксов
					local branch_name = branch_line
						:gsub('^%s*', '') -- убираем пробелы в начале
						:gsub('^%*%s*', '') -- убираем звездочку (текущая ветка)
						:gsub('^remotes/origin/', '') -- убираем префикс удаленной ветки
						:gsub('^origin/', '') -- альтернативный префикс

					-- Проверяем, является ли это удаленной веткой
					local is_remote = branch_line:match('remotes/origin/') ~= nil
					local folder_name = extract_meaningful_branch_name(branch_name)
					-- Создаем путь для нового воркспейса
					local worktree_path = worktrees_dir .. '/' .. folder_name

					-- Проверяем, не существует ли уже такой воркспейс
					local existing_worktrees = vim.fn.system('git worktree list')
					if existing_worktrees:find(worktree_path, 1, true) then
						vim.notify('Worktree for branch "' .. branch_name .. '" already exists at ' .. worktree_path,
							vim.log.levels.WARN)
						return
					end

					-- CreateIfNotExist
					vim.fn.mkdir(worktrees_dir, 'p')

					-- Some overhead but...
					local upstream = nil
					if not is_remote then
						vim.notify('Creating worktree local: ' .. worktree_path .. ' for branch: ' .. branch_name)
						git_worktree.create_worktree(worktree_path, branch_name, nil)
					end
					if is_remote then
						vim.ui.input({
							prompt = "Set upstream? (e.g. origin/" .. branch_name .. ") ",
						}, function(input)
							if input and #input > 0 then
								upstream = input
							end

							if upstream then
								vim.notify('Creating worktree: ' .. worktree_path .. ' for branch: ' .. branch_name)
								git_worktree.create_worktree(worktree_path, branch_name, upstream)
							else
								vim.notify('Creating worktree: ' .. worktree_path .. ' for branch: ' .. branch_name)
								git_worktree.create_worktree(worktree_path, branch_name, nil)
							end
						end)
					end
				end
			},
			winopts = {
				title = 'Create New Worktree - Select Branch',
				height = 0.6,
				width = 0.8,
			},
		})
	end

	fzf.fzf_exec('git worktree list', {
		prompt = 'Git Worktrees (add: C-a, delete: C-d)> ',
		previewer = false,
		actions = {
			['default'] = switch_worktree,
			['ctrl-d'] = delete_worktree,
			['ctrl-a'] = create_worktree,
		},
		winopts = {
			title = 'git-worktree.nvim (fzf-lua)',
		},
	})
end

return {
	{
		'ThePrimeagen/git-worktree.nvim',
		dependencies = {
			"ibhagwan/fzf-lua",
		},
		config = function()
			vim.keymap.set("n", "<leader>gw", M.git_worktrees,
				{ desc = "git worktrees (fzf)" })

			require("git-worktree").setup({
				autopush = false,
			})
		end
	}
}
