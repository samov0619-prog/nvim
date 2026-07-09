return {
  {
    "mfussenegger/nvim-lint",
    -- nixos
    -- enabled = false,
    config = function()
      local lint = require('lint')
      -- phpstan из vendor/bin проекта
      local phpstan = lint.linters.phpstan
      phpstan.cmd = function()
        local root = util.root_pattern("composer.json", ".git")(vim.api.nvim_buf_get_name(0)) or vim.fn.getcwd()
        return root .. "/vendor/bin/phpstan"
      end
      local util = require("lspconfig.util")
      local max_file_size = 1024 * 1024 -- 1MB

      local function has_eslint_config(bufnr)
        bufnr = bufnr or vim.api.nvim_get_current_buf()
        local fname = vim.api.nvim_buf_get_name(bufnr)
        local root = util.root_pattern(
          ".eslintrc",
          ".eslintrc.js",
          ".eslintrc.cjs",
          ".eslintrc.json",
          ".eslintrc.yaml",
          ".eslintrc.yml",
          "eslint.config.js",
          "eslint.config.cjs",
          "eslint.config.mjs",
          "eslint.config.ts"
        )(fname)
        return root ~= nil
      end

      local function has_phpstan_config(bufnr)
        local fname = vim.api.nvim_buf_get_name(bufnr or 0)
        return util.root_pattern("phpstan.neon", "phpstan.neon.dist", "phpstan.dist.neon")(fname) ~= nil
      end

      lint.linters_by_ft = {
        javascript = { 'eslint_d' },
        typescript = { 'eslint_d' },
        javascriptreact = { 'eslint_d' },
        typescriptreact = { 'eslint_d' },
        php = { 'phpstan' },
      }

      local lint_group = vim.api.nvim_create_augroup("lint", { clear = true })

      vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "InsertLeave" }, {
        group = lint_group,
        callback = function()
          local bufnr = vim.api.nvim_get_current_buf()
          local name = vim.api.nvim_buf_get_name(bufnr)

          if name ~= "" and vim.fn.filereadable(name) == 1 then
            local stat = vim.uv.fs_stat(name)
            if stat and stat.size > max_file_size then
              return
            end

            local ft = vim.bo[bufnr].filetype
            local needs_eslint = lint.linters_by_ft[ft]
                and vim.tbl_contains(lint.linters_by_ft[ft], "eslint_d")

            local needs_phpstan = lint.linters_by_ft[ft]
                and vim.tbl_contains(lint.linters_by_ft[ft], "phpstan")
            if needs_phpstan and not has_phpstan_config(bufnr) then
              return
            end
            -- если линтер eslint_d, но конфиг не найден — пропускаем
            if needs_eslint and not has_eslint_config(bufnr) then
              return
            end

            lint.try_lint()
          end
        end,
      })

      vim.api.nvim_create_autocmd("BufWritePost", {
        group = lint_group,
        pattern = "*.php",
        callback = function()
          if has_phpstan_config() then
            lint.try_lint()
          end
        end,
      })
    end
  }
}
