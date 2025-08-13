return {
	{
		'tea06194/gitgraph.nvim',
		branch = "dual-mode",
		opts = {
			git_cmd = "git",
			symbols = {
				merge_commit = '',
				commit = '',
				merge_commit_end = '',
				commit_end = '',

				-- Advanced symbols
				GVER = '',
				GHOR = '',
				GCLD = '',
				GCRD = '╭',
				GCLU = '',
				GCRU = '',
				GLRU = '',
				GLRD = '',
				GLUD = '',
				GRUD = '',
				GFORKU = '',
				GFORKD = '',
				GRUDCD = '',
				GRUDCU = '',
				GLUDCD = '',
				GLUDCU = '',
				GLRDCL = '',
				GLRDCR = '',
				GLRUCL = '',
				GLRUCR = '',
			},
			format = {
				timestamp = '%H:%M:%S %d-%m-%Y',
				fields = { 'hash', 'timestamp', 'author', 'branch_name', 'tag' },
			},
			hooks = {
				on_select_commit = function(commit)
					vim.notify('DiffviewOpen ' .. commit.hash .. '^!')
					vim.cmd(':DiffviewOpen ' .. commit.hash .. '^!')
				end,
				on_select_range_commit = function(from, to)
					vim.notify('DiffviewOpen ' .. from.hash .. '~1..' .. to.hash)
					vim.cmd(':DiffviewOpen ' .. from.hash .. '~1..' .. to.hash)
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
