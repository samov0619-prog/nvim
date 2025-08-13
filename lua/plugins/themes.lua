local uv = vim.uv

return {
	{
		'sainnhe/sonokai',
		lazy = false,
		priority = 1000,
		config = function()
			local os_theme_file = vim.fn.expand("~/.config/theme/current_theme")
			local theme = (vim.fn.filereadable(os_theme_file) == 1 and vim.fn.readfile(os_theme_file)[1]) or "dark"

			local light = {
				black = { "#181819", "255" },
				bg_dim = { "#f8f8f8", "254" },
				bg0 = { "#ffffff", "231" },
				bg1 = { "#f0f0f0", "255" },
				bg2 = { "#e8e8e8", "255" },
				bg3 = { "#e0e0e0", "254" },
				bg4 = { "#d8d8d8", "254" },
				bg_red = { "#ff6077", "203" },
				diff_red = { "#ffebee", "203" },
				bg_green = { "#a7df78", "107" },
				diff_green = { "#d9ffcf", "107" },
				bg_blue = { "#7091ff", "110" },
				diff_blue = { "#e6fdff", "110" },
				diff_yellow = { "#ffffdc", "179" },
				fg = { "#303030", "236" },
				red = { "#e61616", "203" },
				orange = { "#dd8500", "215" },
				yellow = { "#00b0b0", "179" },
				green = { "#009f00", "107" },
				blue = { "#4255ff", "110" },
				purple = { "#c900c9", "176" },
				grey = { "#7f8490", "246" },
				grey_dim = { "#595f6f", "240" },
				none = { "NONE", "NONE" },
			}

			local toggle = function(value)
				if value == "dark" then
					vim.g.sonokai_colors_override = {
						none = { 'NONE', 'NONE' }
					}
				else
					vim.g.sonokai_colors_override = light
				end
				vim.cmd.colorscheme('sonokai')
			end

			local ev = uv.new_fs_event()

			if ev ~= nil then
				ev:start(os_theme_file, {}, vim.schedule_wrap(function(err)
					if err then error(err) end
					local new_val = vim.fn.readfile(os_theme_file)[1]
					if new_val and new_val ~= theme then
						theme = new_val
						toggle(theme)
					end
				end))
			end

			vim.g.sonokai_enable_italic = true

			toggle(theme)

			vim.cmd.colorscheme('sonokai')

			vim.cmd.highlight('IndentLineCurrent guifg=#414550')

			vim.api.nvim_set_hl(0, "MatchParen", {
				bg = '#acfafe',
				fg = '#000000',
			})

			vim.api.nvim_create_autocmd("ColorScheme", {
				pattern = "*",
				callback = function()
					vim.api.nvim_set_hl(0, "MatchParen", {
						bg = '#acfafe',
						fg = '#000000',
					})

					if theme == "dark" then
						vim.api.nvim_set_hl(0, 'MiniIndentscopeSymbol', { fg = '#595f6f' })
						vim.api.nvim_set_hl(0, 'MiniIndentscopeSymbolOff', { fg = '#ff9900' })
					else
						vim.api.nvim_set_hl(0, 'MiniIndentscopeSymbol', { fg = '#d8d8d8' })
						vim.api.nvim_set_hl(0, 'MiniIndentscopeSymbolOff', { fg = '#ff9900' })
					end
				end
				,
			})
		end
	}
}
