return {
	{
		dir = vim.fn.stdpath("config") .. "/lua/my-plugins/keyboardswitch-async",
		name = "keyboardswitch-async",
		config = function()
			require("my-plugins.keyboardswitch-async").setup()
		end,
	}
}
