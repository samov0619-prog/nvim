return {
  {
    'stevearc/conform.nvim',
    config = function()
      local util = require("conform.util")
      local project_markers = {
        "package.json",
        "tsconfig.json",
        "biome.json",
        "biome.jsonc",
        ".git",
      }

      local function find_biome_config(self, ctx)
        -- Сначала ищем в корне проекта
        local project_root = util.root_file(project_markers)(self, ctx)

        if project_root then
          local project_configs = {
            "biome.json",
            "biome.jsonc",
          }

          for _, config in ipairs(project_configs) do
            local config_path = project_root .. "/" .. config
            if vim.fn.filereadable(config_path) == 1 then
              print("config_path", config_path)
              return config_path
            end
          end
        end

        -- Затем в домашней директории
        local home_config = vim.fn.expand("~/biome.jsonc")
        if vim.fn.filereadable(home_config) == 1 then
          print("home_config", home_config)
          return home_config
        end

        return nil
      end

      local function create_biome_formatter()
        return {
          command = util.from_node_modules("biome") or
              vim.fn.expand("~/.local/share/nvim/mason/packages/biome/node_modules/@biomejs/biome/bin/biome"),
          args = function(self, ctx)
            local config_path = find_biome_config(self, ctx)
            local args = {
              "format",
              "--stdin-file-path",
              "$FILENAME",
            }

            if config_path then
              table.insert(args, 2, "--config-path")
              table.insert(args, 3, config_path)
            end

            return args
          end,
          stdin = true,
          cwd = function(self, ctx)
            -- Пытаемся найти корень проекта
            return util.root_file(project_markers)(self, ctx) or vim.fn.getcwd()
          end,
        }
      end

      local prettier_config_names = {
        ".prettierrc", ".prettierrc.json", ".prettierrc.yml", ".prettierrc.yaml", ".prettierrc.json5",
        ".prettierrc.js", ".prettierrc.cjs", ".prettierrc.mjs", ".prettierrc.ts", ".prettierrc.cts",
        ".prettierrc.mts", ".prettierrc.toml", "prettier.config.js", "prettier.config.cjs",
        "prettier.config.mjs", "prettier.config.ts", "prettier.config.cts", "prettier.config.mts",
      }

      local function has_prettier_config(bufnr)
        local filename = vim.api.nvim_buf_get_name(bufnr)
        if filename == "" then return false end
        return vim.fs.root(vim.fs.dirname(filename), function(name, path)
          if vim.tbl_contains(prettier_config_names, name) then return true end
          if name ~= "package.json" then return false end
          local ok, package_json = pcall(vim.json.decode, table.concat(vim.fn.readfile(path .. "/package.json"), "\n"))
          return ok and package_json.prettier ~= nil
        end) ~= nil
      end

      local function js_formatters(bufnr)
        if has_prettier_config(bufnr) and require("conform").get_formatter_info("prettier", bufnr).available then
          return { "prettier" }
        end
        return { "biome" }
      end

      require("conform").setup({
        -- log_level = vim.log.levels.DEBUG,
        formatters_by_ft = {
          javascript      = js_formatters,
          javascriptreact = js_formatters,
          typescript      = js_formatters,
          typescriptreact = js_formatters,
          vue             = js_formatters,
          json            = js_formatters,
          html            = { "biome" },
          yaml            = { "biome" },

          css             = { "stylelint" },
          scss            = { "stylelint" },
          markdown        = { "mdformat" },

          sh              = { "beautysh" },
          bash            = { "beautysh" },
          zsh             = { "beautysh" },
          php             = { "pint" },
        },

        formatters = {
          beautysh = {
            prepend_args = {
              -- "--indent-size", "4",
              -- "--tab",
              "--force-function-style", "paronly",
            },
          },
          biome = create_biome_formatter(),
          pint = {
            command = function(self, ctx)
              local root = util.root_file({ "composer.json", ".git" })(self, ctx) or vim.fn.getcwd()
              return root .. "/vendor/bin/pint"
            end,
            args = { "$FILENAME" },
            stdin = false,
            cwd = function(self, ctx)
              return util.root_file({ "composer.json", ".git" })(self, ctx) or vim.fn.getcwd()
            end,
          },
        }
      })

      vim.keymap.set({ "n", "v" }, "<leader>lfr", function()
        require("conform").format(
          {
            async = true,
            timeout_ms = 4000,
            lsp_format = "fallback",
          },
          function(err, _)
            if not err then
              local mode = vim.api.nvim_get_mode().mode
              if vim.startswith(mode, "v") then
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n",
                  true)
              end
            end
          end)
      end, { desc = "format range or file" })
    end
  },
}
