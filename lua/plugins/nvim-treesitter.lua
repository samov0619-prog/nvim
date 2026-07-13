local ensure_installed = {
  "bash", "comment", "go", "gomod", "gosum", "java", "javascript", "lua",
  "python", "scheme", "sql", "tsx", "typescript", "vue", "vim", "vimdoc",
  "css", "scss", "html", "markdown", "markdown_inline", "mermaid", "xml", "asm",
  "dot", "toml", "yaml", "csv", "json", "json5", "diff", "ssh_config", "printf",
  "disassembly", "dockerfile", "git_config", "git_rebase", "gitcommit",
  "gitignore", "http", "query",
  -- добавил под твой текущий стек:
  "php", "phpdoc", "nix",
}

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    build = ":TSUpdate",
    dependencies = {
      { "nvim-treesitter/nvim-treesitter-textobjects", branch = "main" },
      "eandrju/cellular-automaton.nvim",
    },
    config = function()
      require("nvim-treesitter").setup() -- на main опции не передаём

      -- 1) установка парсеров (замена ensure_installed)
      local installed = require("nvim-treesitter.config").get_installed()
      local to_install = vim.iter(ensure_installed)
          :filter(function(p) return not vim.tbl_contains(installed, p) end)
          :totable()
      if #to_install > 0 then
        require("nvim-treesitter").install(to_install)
      end

      vim.treesitter.language.register("bash", "zsh")

      -- 2) включение подсветки + indent по буферу (замена highlight.enable)
      local max_filesize = 500 * 1024
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("ts_start", { clear = true }),
        callback = function(ev)
          local name = vim.api.nvim_buf_get_name(ev.buf)
          local ok, st = pcall(vim.uv.fs_stat, name)
          if ok and st and st.size > max_filesize then return end
          if pcall(vim.treesitter.start, ev.buf) then
            vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })

      -- 3) textobjects — новый API
      require("nvim-treesitter-textobjects").setup({
        select = { lookahead = true, include_surrounding_whitespace = false },
        move = { set_jumps = true },
      })
      local select = require("nvim-treesitter-textobjects.select")
      local move   = require("nvim-treesitter-textobjects.move")
      local swap   = require("nvim-treesitter-textobjects.swap")

      local sel    = {
        ["a="] = "@assignment.outer",
        ["i="] = "@assignment.inner",
        ["r="] = "@assignment.rhs",
        ["aa"] = "@parameter.outer",
        ["ia"] = "@parameter.inner",
        ["al"] = "@loop.outer",
        ["il"] = "@loop.inner",
        ["ac"] = "@call.outer",
        ["ic"] = "@call.inner",
        ["af"] = "@function.outer",
        ["if"] = "@function.inner",
        ["at"] = "@class.outer",
        ["it"] = "@class.inner",
        ["an"] = "@block.outer",
        ["in"] = "@block.inner",
      }
      for lhs, q in pairs(sel) do
        vim.keymap.set({ "x", "o" }, lhs, function()
          select.select_textobject(q, "textobjects")
        end, { desc = "TS select " .. q })
      end

      local moves = {
        goto_next_start     = { ["]m"] = "@function.outer", ["]i"] = "@conditional.outer", ["]e"] = "@elem.outer" },
        goto_next_end       = { ["]M"] = "@function.outer", ["]I"] = "@conditional.outer", ["]E"] = "@elem.outer" },
        goto_previous_start = { ["[m"] = "@function.outer", ["[i"] = "@conditional.outer", ["[e"] = "@elem.outer" },
        goto_previous_end   = { ["[M"] = "@function.outer", ["[I"] = "@conditional.outer", ["[E"] = "@elem.outer" },
      }
      for method, maps in pairs(moves) do
        for lhs, q in pairs(maps) do
          vim.keymap.set({ "n", "x", "o" }, lhs, function()
            move[method](q, "textobjects")
          end, { desc = "TS " .. method .. " " .. q })
        end
      end

      local swaps = {
        ["<leader>man"] = { swap.swap_next, "@parameter.inner" },
        ["<leader>mfn"] = { swap.swap_next, "@function.outer" },
        ["<leader>mcn"] = { swap.swap_next, "@class.outer" },
        ["<leader>mpn"] = { swap.swap_next, "@attribute.outer" },
        ["<leader>map"] = { swap.swap_previous, "@parameter.inner" },
        ["<leader>mfp"] = { swap.swap_previous, "@function.outer" },
        ["<leader>mcp"] = { swap.swap_previous, "@class.outer" },
        ["<leader>mpp"] = { swap.swap_previous, "@attribute.outer" },
      }
      for lhs, spec in pairs(swaps) do
        vim.keymap.set("n", lhs, function() spec[1](spec[2]) end, { desc = "swap " .. spec[2] })
      end

      vim.keymap.set("n", "<leader>mir", "<cmd>CellularAutomaton make_it_rain<CR>")
    end,
  },
}
