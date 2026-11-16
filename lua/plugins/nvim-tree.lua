return {
  {
    "nvim-tree/nvim-tree.lua",
    version = "*",
    lazy = true,
    dependencies = {
      "nvim-tree/nvim-web-devicons",
    },
    keys = {
      { "<leader>tr", "<cmd>NvimTreeToggle<CR>", desc = "toggle tree" }
    },
    config = function()
      require("nvim-tree").setup({
        view = { float = { open_win_config = { border = require('config.float-style').border } } },
        actions = { file_popup = { open_win_config = { border = require('config.float-style').border } } },
        hijack_netrw = false,
        hijack_directories = {
          enable    = false,
          auto_open = false,
        },
        -- git = { enable = false },
        filters = { dotfiles = true },
        filesystem_watchers = { enable = false },
      })
    end,
  }
}
