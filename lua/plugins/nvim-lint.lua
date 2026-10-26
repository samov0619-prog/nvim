return {
  {
    "mfussenegger/nvim-lint",
    -- nixos
    -- enabled = false,
    config = function()
      local lint = require("lint")
      local tools = require("config.code-tools")

      local function parse_biome(output)
        local diagnostics = {}
        -- nvim-lint concatenates stdout before stderr for stream="both".
        -- The JSON reporter emits one line; drain but don't parse stderr's
        -- experimental-reporter/config warnings as JSON.
        local json = output:match("^%s*({[^\n]*})") or output
        local ok, decoded = pcall(vim.json.decode, json)
        if not ok or type(decoded) ~= "table" or type(decoded.diagnostics) ~= "table" then
          return { {
            source = "biomejs",
            lnum = 0,
            col = 0,
            severity = vim.diagnostic.severity.ERROR,
            message = "Biome check failed: " .. (vim.trim(output) ~= "" and vim.trim(output) or "no JSON output"),
          } }
        end
        local levels = {
          error = vim.diagnostic.severity.ERROR,
          fatal = vim.diagnostic.severity.ERROR,
          warning = vim.diagnostic.severity.WARN,
          info = vim.diagnostic.severity.INFO,
          hint = vim.diagnostic.severity.HINT,
        }
        for _, d in ipairs(decoded.diagnostics or {}) do
          local loc = d.location or {}
          local start = loc.start or {}
          local finish = loc["end"] or {}
          table.insert(diagnostics, {
            source = "biomejs",
            lnum = (tonumber(start.line) or 1) - 1,
            col = (tonumber(start.column) or 1) - 1,
            end_lnum = finish.line and (finish.line - 1) or nil,
            end_col = finish.column and (finish.column - 1) or nil,
            message = d.message or "",
            code = d.category,
            severity = levels[d.severity] or vim.diagnostic.severity.WARN,
          })
        end
        return diagnostics
      end

      -- Keep the bundled parsers, but resolve commands/config arguments through
      -- the same project policy used by formatting and fixing.
      local definitions = {
        biomejs = { stdin = false, stream = "both", ignore_exitcode = true, parser = parse_biome },
        eslint_d = vim.deepcopy(require("lint.linters.eslint_d")),
        stylelint = vim.deepcopy(require("lint.linters.stylelint")),
        yamllint = vim.deepcopy(require("lint.linters.yamllint")),
        phpstan = vim.deepcopy(require("lint.linters.phpstan")),
        ruff = vim.deepcopy(require("lint.linters.ruff")),
      }
      local extra_args = {
        biomejs = { "--reporter=json", "--max-diagnostics=none" },
        eslint_d = { "--format", "json", "--stdin", "--stdin-filename" },
        stylelint = { "--formatter", "json", "--stdin", "--stdin-filename" },
        yamllint = { "--format", "parsable", "-" },
        phpstan = {},
        ruff = { "--quiet", "--no-fix", "--output-format", "json", "-" },
      }
      local function selected_tool(ctx, id)
        for _, tool in ipairs(ctx.linters) do
          if tool.id == id then return tool end
        end
      end
      for id, definition in pairs(definitions) do
        lint.linters[id] = function()
          local bufnr = vim.api.nvim_get_current_buf()
          local ctx = tools.resolve(0)
          local tool = assert(selected_tool(ctx, id), "Linter not selected: " .. id)
          local linter = vim.deepcopy(definition)
          linter.cmd, linter.cwd = tool.cmd or id, tool.cwd
          if tool.env then linter.env = vim.tbl_extend("force", vim.fn.environ(), tool.env) end
          linter.args = vim.list_extend(vim.deepcopy(tool.args), extra_args[id])
          if id == "eslint_d" or id == "stylelint" then linter.args[#linter.args + 1] = ctx.filename end
          linter.parser = function(output, _, cwd)
            if not tools.is_file_buffer(bufnr) then return {} end
            local selected = selected_tool(tools.resolve(bufnr), id)
            if not selected or not vim.deep_equal(selected.args, tool.args) or selected.config ~= tool.config then
              return {}
            end
            return definition.parser(output, bufnr, cwd)
          end
          return linter
        end
      end

      require("config.code-diagnostics").setup()
    end,
  },
}
