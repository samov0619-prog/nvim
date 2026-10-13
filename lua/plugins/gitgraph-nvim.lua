local function compare_commits(from, to)
	local result = vim.system({ "git", "rev-list", "--parents", "-n", "1", from }, { text = true }):wait(2000)
	if result.code ~= 0 then
		vim.notify("CodeDiff: не удалось прочитать коммит " .. from, vim.log.levels.WARN)
		return
	end
	local parent = result.stdout:match("^%x+%s+(%x+)")
	if not parent then
		vim.notify("CodeDiff: сравнение недоступно — у начального коммита нет родителя (корневой коммит или граница shallow-клона)",
			vim.log.levels.WARN)
		return
	end
	vim.api.nvim_cmd({ cmd = "CodeDiff", args = { parent, to } }, {})
end

return {
	{
		'tea06194/gitgraph.nvim',
		branch = "dual-mode",
		dependencies = { "esmuellert/codediff.nvim" },
		opts = {
			git_cmd = "git",
			-- symbols = {
			-- 	merge_commit = '',
			-- 	commit = '',
			-- 	merge_commit_end = '',
			-- 	commit_end = '',
			--
			-- 	-- Advanced symbols
			-- 	GVER = '',
			-- 	GHOR = '',
			-- 	GCLD = '',
			-- 	GCRD = '╭',
			-- 	GCLU = '',
			-- 	GCRU = '',
			-- 	GLRU = '',
			-- 	GLRD = '',
			-- 	GLUD = '',
			-- 	GRUD = '',
			-- 	GFORKU = '',
			-- 	GFORKD = '',
			-- 	GRUDCD = '',
			-- 	GRUDCU = '',
			-- 	GLUDCD = '',
			-- 	GLUDCU = '',
			-- 	GLRDCL = '',
			-- 	GLRDCR = '',
			-- 	GLRUCL = '',
			-- 	GLRUCR = '',
			-- },
			format = {
				timestamp = '%H:%M:%S %d-%m-%Y',
				fields = { 'hash', 'timestamp', 'author', 'branch_name', 'tag' },
			},
			hooks = {
				on_select_commit = function(commit)
					compare_commits(commit.hash, commit.hash)
				end,
				on_select_range_commit = function(from, to)
					compare_commits(from.hash, to.hash)
				end,
			},
		},
		keys = {
			{
				"<leader>gph",
				function()
					require('gitgraph').draw({}, { all = true, max_count = 1000 })
				end,
				desc = "graph",
			},
			{
				"<leader>gpd",
				function()
					require('gitgraph').draw_dual({ commit_info_as_branch_color = true },
						{ all = true, max_count = 1000 })
				end,
				desc = "graph dual",
			},
		},
	}
}
