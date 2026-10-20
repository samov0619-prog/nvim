return {
  {
    "mfussenegger/nvim-lint",
    -- nixos
    -- enabled = false,
    config = function()
      local lint = require('lint')
      local max_file_size = 1024 * 1024

      local function root(markers) return vim.fs.root(0, markers) or vim.fn.getcwd() end
      local function has_eslint_config()
        return vim.fs.root(0, {
          ".eslintrc", ".eslintrc.js", ".eslintrc.cjs", ".eslintrc.json",
          ".eslintrc.yaml", ".eslintrc.yml", "eslint.config.js",
          "eslint.config.cjs", "eslint.config.mjs", "eslint.config.ts",
        }) ~= nil
      end
      local function has_phpstan_config()
        return vim.fs.root(0, { "phpstan.neon", "phpstan.neon.dist", "phpstan.dist.neon" }) ~= nil
      end

      lint.linters.phpstan.cmd = function()
        return root({ "composer.json", ".git" }) .. "/vendor/bin/phpstan"
      end

      lint.linters_by_ft = {
        javascript = { 'eslint_d' },
        typescript = { 'eslint_d' },
        javascriptreact = { 'eslint_d' },
        typescriptreact = { 'eslint_d' },
        php = { 'phpstan' },
        yaml = { 'yamllint' },
      }

      local lint_group = vim.api.nvim_create_augroup("lint", { clear = true })

      vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "InsertLeave", "BufWritePost" }, {
        group = lint_group,
        callback = function(args)
          local bufnr = args.buf
          local name = vim.api.nvim_buf_get_name(bufnr)
          local ft = vim.bo[bufnr].filetype
          if ft:match("^yaml%.") then ft = "yaml" end
          local linters = lint.linters_by_ft[ft]

          if not linters or name == "" then return end

          -- yamllint читает stdin и может проверять ещё не сохранённый YAML.
          if ft ~= "yaml" and vim.fn.filereadable(name) ~= 1 then return end

          vim.api.nvim_buf_call(bufnr, function()
            local stat = vim.uv.fs_stat(name)
            if stat and stat.size > max_file_size then
              return
            end

            local needs_eslint = vim.tbl_contains(linters, "eslint_d")

            local needs_phpstan = vim.tbl_contains(linters, "phpstan")
            -- PHPStan запускаем только после сохранения и при наличии конфига.
            if needs_phpstan and (args.event ~= "BufWritePost" or not has_phpstan_config()) then
              return
            end
            -- если линтер eslint_d, но конфиг не найден — пропускаем
            if needs_eslint and not has_eslint_config() then
              return
            end

            lint.try_lint(linters)
          end)
        end,
      })
    end
  }
}
