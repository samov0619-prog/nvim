local function get_relaltive_time(commit_time)
	local diff = os.time() - commit_time
	local years = math.floor(diff / (360 * 24 * 60 * 60))
	local months = math.floor(diff / (30 * 24 * 60 * 60))
	local days = math.floor(diff / (24 * 60 * 60))
	local hours = math.floor(diff / (60 * 60))
	local minutes = math.floor(diff / 60)

	if years >= 1 then
		return years .. '_yr'
	elseif months >= 1 then
		return months .. '_mo'
	elseif days >= 1 then
		return days .. '__d'
	elseif hours >= 1 then
		return hours .. '__h'
	else
		return minutes .. '_mi'
	end
end

local ago_message_author_hash_fn = function(line_porcelain, config, idx)
	local hash = string.sub(line_porcelain.hash, 0, 7)
	local line_with_hl = {}
	local is_commited = hash ~= "0000000"
	if is_commited then
		local summary
		if #line_porcelain.summary > config.max_summary_width then
			summary = string.sub(
				line_porcelain.summary,
				0,
				config.max_summary_width - 3
			) .. "..."
		else
			summary = line_porcelain.summary
		end
		line_with_hl = {
			idx = idx,
			values = {
				{
					textValue = get_relaltive_time(line_porcelain.committer_time),
					hl = hash,
				},
				{
					textValue = hash,
					hl = "Comment",
				},
				{
					textValue = line_porcelain.author,
					hl = hash,
				},
			},
			format = "%s %s %s",
		}
	else
		line_with_hl = {
			idx = idx,
			values = {
				{
					textValue = "Not commited",
					hl = "Comment",
				},
			},
			format = "%s",
		}
	end
	return line_with_hl
end

return {
	{
		"FabijanZulj/blame.nvim",
		lazy = false,
		config = function()
			require('blame').setup {
				virtual_style = 'right_align',
				format_fn = ago_message_author_hash_fn,
			}
			vim.keymap.set(
				"n",
				"<leader>gb",
				"<cmd>BlameToggle virtual<CR>",
				{ desc = "blame file", noremap = true }
			)
		end,
	},
}
