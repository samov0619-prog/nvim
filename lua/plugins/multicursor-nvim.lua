return {
	{
		"jake-stewart/multicursor.nvim",
		-- enabled=false,
		config = function()
			local mc = require("multicursor-nvim")

			-- fix native neovim undo
			vim.keymap.set("i", "<left>", "<Left>", { silent = true })
			vim.keymap.set("i", "<right>", "<Right>", { silent = true })
			mc.setup()

			-- Add or skip cursor above/below the main cursor.
			vim.keymap.set({ "n", "x" }, "<up>",
				function() mc.lineAddCursor(-1) end, { desc = "add cursor above" })
			vim.keymap.set({ "n", "x" }, "<down>",
				function() mc.lineAddCursor(1) end, { desc = "add cursor below" })
			vim.keymap.set({ "n", "x" }, "<leader><up>",
				function() mc.lineSkipCursor(-1) end, { desc = "skip cursor above" })
			vim.keymap.set({ "n", "x" }, "<leader><down>",
				function() mc.lineSkipCursor(1) end, { desc = "skip cursor below" })
			-- Add or skip adding a new cursor by matching word/selection
			vim.keymap.set({ "n", "x" }, "<leader>n",
				function() mc.matchAddCursor(1) end, { desc = "add cursor next match" })
			vim.keymap.set({ "n", "x" }, "<leader>s",
				function() mc.matchSkipCursor(1) end, { desc = "skip cursor next match" })
			vim.keymap.set({ "n", "x" }, "<leader>N",
				function() mc.matchAddCursor(-1) end, { desc = "add cursor prev match" })
			vim.keymap.set({ "n", "x" }, "<leader>S",
				function() mc.matchSkipCursor(-1) end, { desc = "skip cursor prev match" })
			vim.keymap.set("n", "<esc>", function()
				if not mc.cursorsEnabled() then
					mc.enableCursors()
				elseif mc.hasCursors() then
					mc.clearCursors()
				else
					-- Default <esc> handler.
				end
			end, { desc = "toggle/clear cursors" })
		end
	}
}
