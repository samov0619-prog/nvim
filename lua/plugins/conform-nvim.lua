return {
  {
    "stevearc/conform.nvim",
    config = function()
      local tools = require("config.code-tools")
      local function select_formatter(bufnr)
        local selected = tools.resolve(bufnr).formatter
        return selected and selected.cmd and { selected.id } or {}
      end
      local formatters_by_ft = {}
      for ft in pairs(tools.format_filetypes) do formatters_by_ft[ft] = select_formatter end
      formatters_by_ft.python = select_formatter
      formatters_by_ft.sh = { "beautysh" }
      formatters_by_ft.bash = { "beautysh" }
      formatters_by_ft.zsh = { "beautysh" }
      formatters_by_ft.php = { "pint" }

      local function formatter(id)
        local function selected(ctx)
          local tool = tools.resolve(ctx.buf).formatter
          return tool and tool.id == id and tool or nil
        end
        return {
          inherit = false,
          command = function(_, ctx)
            local tool = selected(ctx)
            return tool and tool.cmd or id
          end,
          args = function(_, ctx)
            local tool = selected(ctx)
            return tool and tool.args or {}
          end,
          cwd = function(_, ctx)
            local tool = selected(ctx)
            return tool and tool.cwd or nil
          end,
          condition = function(_, ctx)
            local tool = selected(ctx)
            return tool ~= nil and tool.cmd ~= nil
          end,
          stdin = true,
        }
      end

      require("conform").setup({
        default_format_opts = { lsp_format = "fallback" },
        formatters_by_ft = formatters_by_ft,
        formatters = {
          biome = formatter("biome"),
          prettier = formatter("prettier"),
          ruff_format = formatter("ruff_format"),
          beautysh = { prepend_args = { "--force-function-style", "paronly" } },
          pint = {
            inherit = false,
            command = function(_, ctx)
              local bin = tools.find_config(ctx.buf, { "vendor/bin/pint" })
              return bin and bin.path or "pint"
            end,
            condition = function(_, ctx)
              local bin = tools.find_config(ctx.buf, { "vendor/bin/pint" })
              return bin ~= nil and vim.fn.executable(bin.path) == 1
            end,
            args = function(_, ctx)
              local config = tools.find_config(ctx.buf, { "pint.json" })
              local args = config and { "--config", config.path } or {}
              return vim.list_extend(args, { "$FILENAME" })
            end,
            cwd = function(_, ctx)
              local config = tools.find_config(ctx.buf, { "composer.json", "pint.json" })
              return config and config.root or tools.project(ctx.buf).boundary
            end,
            stdin = false,
          },
        },
      })
    end,
  },
}
