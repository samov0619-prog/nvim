local function goto_file_smart()
  local lib = require("diffview.lib")
  local view = lib.get_current_view()
  if not view then return end
  local file = view:infer_cur_file()
  if not file then return end
  local path = file.absolute_path
  local api = vim.api
  local file_buf
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_get_name(buf) == path then file_buf = buf; break end
  end

  local target
  for _, win in ipairs(api.nvim_list_wins()) do
    local buf = api.nvim_win_get_buf(win)
    if not lib.tabpage_to_view(api.nvim_win_get_tabpage(win))
        and not vim.wo[win].diff
        and api.nvim_win_get_config(win).relative == ""
        and not vim.wo[win].winfixbuf      -- отсекает окна графа (winfixbuf)
        and vim.bo[buf].buftype == "" then -- только реальное файловое окно (mini.files float = acwrite, отсеётся)
      -- Focus an existing file without :edit, which would reload unsaved edits.
      if buf == file_buf then target = win; break end
      if not target and not vim.bo[buf].modified then target = win end
    end
  end

  if target then
    api.nvim_set_current_win(target)
    if api.nvim_get_current_buf() ~= file_buf then
      if file_buf then vim.cmd.buffer(file_buf)
      else vim.cmd("edit " .. vim.fn.fnameescape(path)) end
    end
  else
    if file_buf then vim.cmd("0tab sbuffer " .. file_buf)
    else vim.cmd("0tabnew " .. vim.fn.fnameescape(path)) end
    -- A tab created from a diff pane inherits its window-local diff options.
    vim.cmd("diffoff")
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
      local presentation = require("config.diffview-presentation")
      local review = require("config.code-review")
      presentation.setup()
      review.setup()
      vim.keymap.set("n", "<leader>gdm", function()
        require("merge_preview").open()
      end, { desc = "Merge: isolated result preview" })
      require("diffview").setup({
        hooks = {
          diff_buf_win_enter = function(buf, win, ctx)
            presentation.enter(buf, win, ctx)
            review.sync()
          end,
          view_closed = presentation.close,
        },
        view = {
          default = { disable_diagnostics = false },
          file_history = { disable_diagnostics = false },
          merge_tool = {
            layout = "diff3_mixed",
            -- code-review restores namespace states; Diffview enables all on detach.
            disable_diagnostics = false,
            winbar_info = false,
          },
        },
        keymaps = {
          view               = {
            { "n", "gf", goto_file_smart, { desc = "goto file (skip graph)" } },
            { "n", "<leader>cf", "<Nop>" },
            { "n", "<leader>cx", "<Nop>" },
          },
          file_panel         = { { "n", "gf", goto_file_smart, { desc = "goto file (skip graph)" } } },
          file_history_panel = { { "n", "gf", goto_file_smart, { desc = "goto file (skip graph)" } } },
        },
      })
      vim.keymap.set("n", "<leader>gdo", "<cmd>DiffviewOpen<cr>", { desc = "diffview open" })
      vim.keymap.set("n", "<leader>gdO", "<cmd>DiffviewOpen origin<cr>", { desc = "diffview open origin" })
      vim.keymap.set("n", "<leader>gdu", "<cmd>DiffviewOpen @{u}<cr>", { desc = "diffview upstream" })
      vim.keymap.set("n", "<leader>gdh", "<cmd>DiffviewFileHistory %<cr>", { desc = "diffview file history" })
      vim.keymap.set("n", "<leader>gdH", "<cmd>DiffviewFileHistory<cr>", { desc = "diffview repository history" })
      vim.keymap.set("n", "<leader>gdc", "<cmd>DiffviewClose<cr>", { desc = "diffview close" })
    end
  },
}
