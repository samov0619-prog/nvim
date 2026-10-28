return {
  {
    'numToStr/Comment.nvim',
    -- enabled = false,
    dependencies = {
      'JoosepAlviste/nvim-ts-context-commentstring'
    },
    config = function()
      require('ts_context_commentstring').setup {
        enable_autocmd = false,
      }
      local ft = require('Comment.ft')
      ft.set('env', '#%s')
      local calculate = ft.calculate
      ft.calculate = function(ctx)
        -- Neovim 0.12 returns nil for missing parsers instead of throwing.
        -- Comment.nvim only handles the old exception-based fallback.
        local ok, parser = pcall(vim.treesitter.get_parser, 0)
        if not ok or not parser then return ft.get(vim.bo.filetype, ctx.ctype) end
        return calculate(ctx)
      end
      require('Comment').setup {
        pre_hook = require('ts_context_commentstring.integrations.comment_nvim').create_pre_hook(),
      }
    end,
  }
}
