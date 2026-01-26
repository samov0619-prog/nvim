return {
	{
		"lewis6991/gitsigns.nvim",
		config = function()
			require('gitsigns').setup {
				on_attach = function(bufnr)
					local gitsigns = require('gitsigns')

					-- Navigation
					vim.keymap.set('n', ']c', function()
						if vim.wo.diff then
							vim.cmd.normal({ ']c', bang = true })
						else
							gitsigns.nav_hunk('next')
						end
					end, { desc = "next hunk", buffer = bufnr })

					vim.keymap.set('n', '[c', function()
						if vim.wo.diff then
							vim.cmd.normal({ '[c', bang = true })
						else
							gitsigns.nav_hunk('prev')
						end
					end, { desc = "prev hunk", buffer = bufnr })

					vim.keymap.set(
						"n",
						"<leader>bl",
						function()
							gitsigns.blame_line({ full = true })
						end,
						{ desc = "blame current line", noremap = true, buffer = bufnr }
					)

					-- Actions
					vim.keymap.set('n', '<leader>hs', gitsigns.stage_hunk, { desc = "stage hunk", buffer = bufnr })
					vim.keymap.set('n', '<leader>hr', gitsigns.reset_hunk, { desc = "reset hunk", buffer = bufnr })
					vim.keymap.set('v', '<leader>hs', function()
						gitsigns.stage_hunk({ vim.fn.line('.'), vim.fn.line('v') })
					end, { desc = "stage hunk", buffer = bufnr })
					vim.keymap.set('v', '<leader>hr', function()
						gitsigns.reset_hunk({ vim.fn.line('.'), vim.fn.line('v') })
					end, { desc = "reset hunk", buffer = bufnr })
					vim.keymap.set('n', '<leader>hS', gitsigns.stage_buffer, { desc = "stage buffer", buffer = bufnr })
					vim.keymap.set('n', '<leader>hR', gitsigns.reset_buffer, { desc = "reset buffer", buffer = bufnr })
					vim.keymap.set('n', '<leader>hp', gitsigns.preview_hunk, { desc = "preview hunk", buffer = bufnr })
					vim.keymap.set('n', '<leader>hi', gitsigns.preview_hunk_inline,
						{ desc = "preview hunk inline", buffer = bufnr })
					vim.keymap.set('n', '<leader>hb', function()
						gitsigns.blame_line({ full = true })
					end, { desc = "blame line", buffer = bufnr })
					vim.keymap.set('n', '<leader>hd', gitsigns.diffthis, { desc = "diff this", buffer = bufnr })
					vim.keymap.set('n', '<leader>hD', function()
						gitsigns.diffthis('~')
					end, { desc = "diff this ~", buffer = bufnr })
					vim.keymap.set('n', '<leader>hQ', function() gitsigns.setqflist('all') end,
						{ desc = "set qflist all", buffer = bufnr })
					vim.keymap.set('n', '<leader>hq', gitsigns.setqflist, { desc = "set qflist", buffer = bufnr })

					-- Toggles
					vim.keymap.set('n', '<leader>tb', gitsigns.toggle_current_line_blame,
						{ desc = "toggle current line blame", buffer = bufnr })
					vim.keymap.set('n', '<leader>tw', gitsigns.toggle_word_diff,
						{ desc = "toggle word diff", buffer = bufnr })

					-- Text object
					vim.keymap.set({ 'o', 'x' }, 'ih', gitsigns.select_hunk, { desc = "select hunk", buffer = bufnr })
				end
			}
		end,
	},
}
