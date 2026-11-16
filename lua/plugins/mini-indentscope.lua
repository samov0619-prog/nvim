return {
  {
    'echasnovski/mini.indentscope',
    version = '*',
    config = function()
      require("mini.indentscope").setup({
        mappings = {
          object_scope = '',
          object_scope_with_border = '',
          goto_top = '',
          goto_bottom = '',
        },
        draw = {
          animation = require('mini.indentscope').gen_animation.none()
        },
        options = {
          try_as_border = true,
        },
        symbol = '│'
      })
    end
  },
}
