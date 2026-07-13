local function goto_file_smart()
  local lib = require("diffview.lib")
  local view = lib.get_current_view()
  if not view then return end
  local file = view:infer_cur_file()
  if not file then return end
  local path = file.absolute_path

  local target
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_win_get_tabpage(win) ~= view.tabpage
      and not vim.wo[win].winfixbuf      -- отсекает окна графа (winfixbuf)
      and vim.bo[buf].buftype == "" then  -- только реальное файловое окно (mini.files float = acwrite, отсеётся)
      target = win
      break
    end
  end

if target then
    vim.api.nvim_set_current_win(target)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  else
    vim.cmd("0tabnew " .. vim.fn.fnameescape(path))
  end

  -- закрыть mini.files ПОСЛЕ перехода, отложенно (иначе фокус/тайминг мешают)
  vim.schedule(function()
    pcall(function() require("mini.files").close() end)
  end)
end

return {
	{
		"sindrets/diffview.nvim",
		config = function()
			require("diffview").setup({
				view = {
					merge_tool = {
						layout = "diff3_mixed",
						disable_diagnostics = true,
						winbar_info = false,
					},
				},
        keymaps = {
          view               = { { "n", "gf", goto_file_smart, { desc = "goto file (skip graph)" } } },
          file_panel         = { { "n", "gf", goto_file_smart, { desc = "goto file (skip graph)" } } },
          file_history_panel = { { "n", "gf", goto_file_smart, { desc = "goto file (skip graph)" } } },
        },
			})
			vim.keymap.set("n", "<leader>gdo", "<cmd>DiffviewOpen<cr>", { desc = "diffview open" })
			vim.keymap.set("n", "<leader>gdO", "<cmd>DiffviewOpen origin<cr>", { desc = "diffview open origin" })
			vim.keymap.set("n", "<leader>gdu", "<cmd>DiffviewOpen @{u}<cr>", { desc = "diffview upstream" })
			vim.keymap.set("n", "<leader>gdc", "<cmd>DiffviewClose<cr>", { desc = "diffview close" })
		end
	},
}
