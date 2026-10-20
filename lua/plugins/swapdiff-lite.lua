return {
	{
    dir = vim.fn.stdpath("config") .. "/lua/my-plugins/swapdiff-lite",
		name = "swapdiff-lite",
		init = function()
			require("my-plugins.swapdiff-lite").setup()
		end,
	}
}
