return {
  {
    "A7Lavinraj/fyler.nvim",
    dependencies = { "nvim-mini/mini.icons" },
    branch = "stable", -- Use stable branch for production
    lazy = false,      -- Necessary for `default_explorer` to work properly
    opts = {
      views = {
        finder = {

          default_explorer = true,
          mappings = {
            ---@param self Finder
            ["<C-h>"] = function(self)
              local current_node = self:cursor_node_entry()
              local parent_ref_id = self.files:find_parent(current_node.ref_id)
              if not parent_ref_id then
                return
              end

              if self.files.trie.value == parent_ref_id then
                self:exec_action("n_goto_parent")
              else
                self:exec_action("n_collapse_node")
              end
            end,
            ["`"] = function(self)
              local node = self:cursor_node_entry()
              if not node then return end

              local path = node.path

              vim.cmd.cd(vim.fs.dirname(path))
              self:exec_action("n_goto_cwd")
            end,
          },
          win = {
            win_opts = {
              cursorline = true,
              number = true,
              signcolumn = "yes",
            },
          }
        },
      }
    },
    keys = {
      { "<leader>e", "<Cmd>Fyler<Cr>", desc = "Open Fyler View" },
    }
  }
}
