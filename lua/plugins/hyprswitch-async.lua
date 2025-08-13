return {
	{
		dir = vim.fn.stdpath("config") .. "/lua/my-plugins/hyprswitch-async",
		name = "hyprswitch-async",
		config = function()
			require("my-plugins.hyprswitch-async").setup()
		end,
	}
}
