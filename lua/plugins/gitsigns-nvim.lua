return {
  {
    "lewis6991/gitsigns.nvim",
    config = function()
      require('gitsigns').setup {
        on_attach = function(bufnr)
          local gitsigns = require('gitsigns')

          -- Navigation
          vim.keymap.set('n', ']c', function()
            if vim.wo.diff then
              vim.cmd.normal({ ']c', bang = true })
            else
              gitsigns.nav_hunk('next')
            end
          end, { desc = "next hunk", buffer = bufnr })

          vim.keymap.set('n', '[c', function()
            if vim.wo.diff then
              vim.cmd.normal({ '[c', bang = true })
            else
              gitsigns.nav_hunk('prev')
            end
          end, { desc = "prev hunk", buffer = bufnr })

          vim.keymap.set(
            "n",
            "<leader>gb",
            function()
              gitsigns.blame_line({ full = true })
            end,
            { desc = "blame current line", noremap = true, buffer = bufnr }
          )

          -- Actions
          vim.keymap.set('n', '<leader>hs', gitsigns.stage_hunk, { desc = "stage hunk", buffer = bufnr })
          vim.keymap.set('n', '<leader>hr', gitsigns.reset_hunk, { desc = "reset hunk", buffer = bufnr })
          vim.keymap.set('v', '<leader>hs', function()
            gitsigns.stage_hunk({ vim.fn.line('.'), vim.fn.line('v') })
          end, { desc = "stage hunk", buffer = bufnr })
          vim.keymap.set('v', '<leader>hr', function()
            gitsigns.reset_hunk({ vim.fn.line('.'), vim.fn.line('v') })
          end, { desc = "reset hunk", buffer = bufnr })
          vim.keymap.set('n', '<leader>hS', gitsigns.stage_buffer, { desc = "stage buffer", buffer = bufnr })
          vim.keymap.set('n', '<leader>hp', gitsigns.preview_hunk_inline,
            { desc = "preview hunk inline", buffer = bufnr })
          vim.keymap.set('n', '<leader>hd', gitsigns.diffthis, { desc = "diff this", buffer = bufnr })
          vim.keymap.set('n', '<leader>hD', function()
            gitsigns.diffthis('~')
          end, { desc = "diff this ~", buffer = bufnr })
        end
      }
    end,
  },
}
