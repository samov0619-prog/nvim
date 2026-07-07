return {
  {
    "FylerOrg/fyler.nvim",
    dependencies = { "nvim-mini/mini.icons" },
    lazy = false,
    config = function()
      require("mini.icons").setup({})

      local fyler = require("fyler")
      fyler.setup({
        use_as_default_explorer = true, -- было несуществующее default_explorer
        follow_current_file = true,
        bound_cursor = true,
        auto_confirm_simple_mutation = false,

        integrations = {
          icon = "mini_icons", -- строка-пресет, НЕ функция
        },

        kind = "replace",
        kind_presets = {
          replace = {
            win_opts = {
              cursorline = true,
              number = false,
              signcolumn = "yes",
            },
            -- <CR> в replace и так select{close=true, pick=false} по дефолту
          },
        },

        mappings = {
          n = {
            ["."]     = { action = "toggle_ui", args = { "hidden_items" } },
            ["<C-h>"] = { action = "shrink", args = { parent = true } },
            ["`"]     = {
              action = function(self)
                local node = require("fyler.finder").parse_cursor_line(self)
                if not node then return end
                self:visit({ path = vim.fs.dirname(node.path) })
              end,
            },
            ["-"]     = {
              action = function(self)
                local prev = vim.fn.getcwd()
                self:visit({ parent = true }) -- корректный подъём + вся работа с буфером
                vim.cmd.tcd({                 -- откатываем ТОЛЬКО tcd
                  args = { vim.fn.fnameescape(prev) },
                  mods = { silent = true },
                })
              end,
            },
          },
        },

        ui = {
          hidden_items = { switches = { "dotfiles" } },
          indent_guides = true,
        },
      })
    end,
    keys = {
      { "<leader>e", function() require("fyler").open() end, desc = "Open Fyler View" },
    },
  },
}
