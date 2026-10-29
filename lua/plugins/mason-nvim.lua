return {
  {
    "mason-org/mason.nvim",
    event = "VeryLazy",
    -- for nixos
    -- enabled = false,
    dependencies = {
      "mason-org/mason-lspconfig.nvim",
    },
    config = function()
      local mason = require "mason"
      local mason_lspconfig = require("mason-lspconfig")
      require("config.mason-fzf-autoclose").setup()

      mason.setup {
        PATH = "append",
        registries = {
          "lua:config.mason-registry",
          "github:mason-org/mason-registry",
        },
        ui = {
          icons = {
            package_installed = "✓",
            package_pending = "➜",
            package_uninstalled = "✗",
          },
        },
      }

      mason_lspconfig.setup(
        {
          -- Ruff's CLI is owned by Conform/nvim-lint, not a second LSP client.
          automatic_enable = { exclude = { "ruff" } },
          ensure_installed = {
            "bashls",
            "basedpyright",
            "cssls",
            "css_variables",
            "cssmodules_ls",
            "eslint",
            "html",
            "jsonls",
            "hyprls",
            "lua_ls",
            "lemminx",
            "jdtls",
            "ts_ls",
            "vue_ls",
            "intelephense",
            "yamlls",
            -- "tsgo", -- Устаревшее имя LSP для нативного TS7 (теперь tsc); текущая связка ts_ls + vue_ls требует TS < 7.
            -- "vtsls", -- Альтернатива ts_ls, а не дополнение: совместный запуск дублирует TS LSP; выбран ts_ls с Vue-плагином.
          }
        }
      )
    end,
  },
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "mason-org/mason.nvim" },
    -- for nixos
    -- enabled = false,
    config = function()
      require('mason-tool-installer').setup {
        ensure_installed = {
          -- Not an lspconfig server name: selected by config.ts-toolchain.
          { "vue-language-server-vue2", auto_update = false },
          "prettier",
          "eslint_d",
          "biome",
          "stylelint",
          "beautysh",
          "mdformat",
          "markdown-oxide",
          "js-debug-adapter",
          "yamllint",
          "ruff",
          "stylelint-language-server",
        },
        run_on_start = true,
        debounce_hours = 5, -- at least 5 hours between attempts to install/update
      }
    end
  }
}
