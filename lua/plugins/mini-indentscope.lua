return {
	{
		'echasnovski/mini.indentscope',
		version = '*',
		config = function()
			require("mini.indentscope").setup({
				draw = {
					animation = require('mini.indentscope').gen_animation.none()
				},
				options = {
					try_as_border = true,
				},
				symbol = '│'
			})
		end
	},
}
