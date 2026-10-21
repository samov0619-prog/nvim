local M = {}

-- Work around the intermediate WinEnter exposed by fzf-lua PR #2813:
-- https://github.com/ibhagwan/fzf-lua/pull/2813
-- Disable at startup with vim.g.mason_fzf_autoclose_workaround = false.
-- Remove once Enter/Esc keep Mason open without this adapter and a real
-- departure still closes it (test in a fresh Neovim after updating plugins).
function M.setup()
  if vim.g.mason_fzf_autoclose_workaround == false then return end

  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("MasonFzfAutoclose", { clear = true }),
    pattern = "mason",
    callback = function(event)
      local buf = event.buf
      local win = vim.api.nvim_get_current_win()
      -- Mason registers its own autoclose handler after setting filetype.
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf)
            or not vim.api.nvim_win_is_valid(win)
            or vim.api.nvim_win_get_buf(win) ~= buf
        then
          return
        end

        -- Keep Mason's BufHidden/BufUnload handlers. Use its own group so
        -- the replacement follows the normal close/reopen lifecycle.
        vim.api.nvim_clear_autocmds({ group = "MasonWindow", event = "WinEnter" })
        vim.api.nvim_create_autocmd("WinEnter", {
          group = "MasonWindow",
          desc = "Mason autoclose except during fzf-lua teardown",
          callback = function()
            if not vim.api.nvim_win_is_valid(win)
                or vim.api.nvim_win_get_buf(win) ~= buf
            then
              return true
            end

            -- Do not load fzf-lua just to handle an unrelated window.
            local utils = package.loaded["fzf-lua.utils"]
            local picker = utils and utils.fzf_winobj()
            if picker and picker.closing then return end

            local buftype = vim.bo.buftype
            if buftype ~= "prompt" and buftype ~= "nofile" then
              require("mason.ui.instance").window.close()
              return true
            end
          end,
        })
      end)
    end,
  })
end

return M
