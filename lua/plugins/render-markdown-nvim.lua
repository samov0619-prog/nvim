return {
	{
		'MeanderingProgrammer/render-markdown.nvim',
		dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' },
		ft = { 'markdown', 'quarto' },
		config = function()
			require('config.markdown-zebra').setup()
			require("render-markdown").setup({
				render_modes = { 'n', 'i', 'c', 't' },
				anti_conceal = {
					enabled = true,
					above = 0,
					below = 0,
				},
				pipe_table = {
					enabled = true,
					cell = 'padded',
					wrap = true,
				},
			})
		end,
	}
}
