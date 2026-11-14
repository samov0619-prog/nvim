return {
  {
    "luukvbaal/statuscol.nvim",
    lazy = false,
    opts = function()
      local builtin = require("statuscol.builtin")

      return {
        ft_ignore = { "minifiles", "NvimTree", "oil", "fyler", "lazy" },
        bt_ignore = { "nofile", "prompt", "quickfix", "terminal", "help" },
        segments = {
          {
            sign = {
              namespace = { "^gitsigns" },
              maxwidth = 1,
              colwidth = 1,
              auto = false,
            },
          },
          {
            sign = {
              name = { ".*" },
              namespace = { ".*" },
              maxwidth = 1,
              colwidth = 1,
              auto = false,
            },
          },
          { text = { " " } },
          { text = { "%C" } },
          {
            -- Unlike %l, an expression does not insert an implicit left spacer.
            text = {
              "%{v:virtnum != 0 || (!&nu && !&rnu) ? ''"
                .. " : &rnu && (v:relnum != 0 || !&nu) ? v:relnum : v:lnum}%=",
              " ",
            },
            condition = { true, builtin.not_empty },
          },
        },
      }
    end,
  },
}
