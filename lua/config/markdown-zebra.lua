local M = {}
local highlight = 'RenderMarkdownTableStripe'

local function set_highlight()
	local normal = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
	local dark = vim.o.background == 'dark'
	local bg = normal.bg or (dark and 0x202020 or 0xffffff)
	local target = dark and 255 or 0
	local function channel(shift)
		local value = math.floor(bg / 2 ^ shift) % 256
		return math.floor(value + (target - value) * 0.045 + 0.5)
	end
	vim.api.nvim_set_hl(0, highlight, {
		bg = channel(16) * 65536 + channel(8) * 256 + channel(0),
	})
end

-- Keep syntax foregrounds and styles; override only the background.
local function shade(line)
	for _, chunk in ipairs(line) do
		local groups = type(chunk[2]) == 'table' and vim.list_extend({}, chunk[2])
			or (chunk[2] and { chunk[2] } or {})
		groups[#groups + 1] = highlight
		chunk[2] = groups
	end
end

local function striped(renderer, row)
	-- Anchor parity to the delimiter, not the subset visible in the window.
	return row.node.type == 'pipe_table_row'
		and (row.node.start_row - renderer.data.delim.start_row) % 2 == 0
end

function M.setup()
	set_highlight()
	vim.api.nvim_create_autocmd('ColorScheme', {
		group = vim.api.nvim_create_augroup('MarkdownTableZebra', { clear = true }),
		callback = set_highlight,
	})
	if M.installed then return end

	-- Small adapter to render-markdown's internal table renderer (245956d).
	-- Reuse its layout, lifecycle and anti-conceal; no extra parsing or timers.
	local renderer = require('render-markdown.render.markdown.table')
	local row_render, wrapped_render = renderer.row, renderer.wrapped_row
	assert(type(row_render) == 'function' and type(wrapped_render) == 'function',
		'render-markdown table API changed: update markdown-zebra adapter')

	renderer.wrapped_row = function(self, row)
		local lines = wrapped_render(self, row)
		if striped(self, row) then
			for _, line in ipairs(lines) do shade(line) end
		end
		return lines
	end

	renderer.row = function(self, row)
		local marks = self.marks:get()
		local first = #marks + 1
		row_render(self, row)
		if not striped(self, row) then return end
		-- Include virtual padding and borders of unwrapped rows.
		for i = first, #marks do
			if marks[i].opts.virt_text then shade(marks[i].opts.virt_text) end
		end
		self.marks:over(self.config, true, row.node, {
			hl_group = highlight,
			priority = 4097,
		})
	end
	M.installed = true
end

return M
