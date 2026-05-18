return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    dependencies = {
      "nvim-treesitter/nvim-treesitter-textobjects",
      "eandrju/cellular-automaton.nvim",
    },
    config = function()
      -- setup принимает только install_dir
      require("nvim-treesitter").setup()

      -- ensure_installed теперь явный вызов install()
      -- vim.defer_fn нужен чтобы не блокировать старт
      vim.defer_fn(function()
        require("nvim-treesitter").install({
          -- languages
          "bash", "comment", "go", "gomod", "gosum",
          "java", "javascript", "lua", "python",
          "scheme", "sql", "tsx", "typescript", "vue",
          "vim", "vimdoc",
          -- markup
          "css", "html", "markdown", "markdown_inline",
          "mermaid", "xml", "asm",
          -- config
          "dot", "toml", "yaml",
          -- data
          "csv", "json", "json5",
          -- utility
          "diff", "ssh_config", "printf", "disassembly",
          "dockerfile", "git_config", "git_rebase",
          "gitcommit", "gitignore", "http", "query",
        }):wait(300000)
      end, 0)

      -- highlight теперь включается через FileType autocmd
      -- список языков должен совпадать с install выше
      local langs = {
        "bash", "comment", "go", "gomod", "gosum",
        "java", "javascript", "lua", "python",
        "scheme", "sql", "tsx", "typescript", "vue",
        "vim", "vimdoc", "css", "html", "markdown",
        "markdown_inline", "mermaid", "xml", "asm",
        "dot", "toml", "yaml", "csv", "json", "json5",
        "diff", "ssh_config", "printf", "disassembly",
        "dockerfile", "git_config", "git_rebase",
        "gitcommit", "gitignore", "http", "query",
      }
      vim.api.nvim_create_autocmd("FileType", {
        pattern = langs,
        callback = function(args)
          local ok, stats = pcall(vim.loop.fs_stat, vim.api.nvim_buf_get_name(args.buf))
          -- отключать highlight для файлов больше 500kb
          if ok and stats and stats.size > 500 * 1024 then return end
          vim.treesitter.start(args.buf)
        end,
      })

      vim.treesitter.language.register("bash", "zsh")
      vim.keymap.set("n", "<leader>mir", "<cmd>CellularAutomaton make_it_rain<CR>")
    end,
  },
  {
    -- textobjects тоже переехал на main
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main",
    config = function()
      require("nvim-treesitter-textobjects").setup {
        select = { lookahead = true },
        move   = { set_jumps = true },
      }

      local select   = require("nvim-treesitter-textobjects.select")
      local move     = require("nvim-treesitter-textobjects.move")
      local swap     = require("nvim-treesitter-textobjects.swap")

      -- SELECT
      local sel_maps = {
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
      for key, query in pairs(sel_maps) do
        vim.keymap.set({ "x", "o" }, key, function()
          select.select_textobject(query, "textobjects")
        end)
      end

      -- MOVE
      local move_maps = {
        { "]m", "goto_next_start",     "@function.outer" },
        { "]i", "goto_next_start",     "@conditional.outer" },
        { "]e", "goto_next_start",     "@elem.outer" },
        { "]M", "goto_next_end",       "@function.outer" },
        { "]I", "goto_next_end",       "@conditional.outer" },
        { "]E", "goto_next_end",       "@elem.outer" },
        { "[m", "goto_previous_start", "@function.outer" },
        { "[i", "goto_previous_start", "@conditional.outer" },
        { "[e", "goto_previous_start", "@elem.outer" },
        { "[M", "goto_previous_end",   "@function.outer" },
        { "[I", "goto_previous_end",   "@conditional.outer" },
        { "[E", "goto_previous_end",   "@elem.outer" },
      }
      for _, m in ipairs(move_maps) do
        local key, method, query = m[1], m[2], m[3]
        vim.keymap.set({ "n", "x", "o" }, key, function()
          move[method](query, "textobjects")
        end)
      end

      -- SWAP
      local swap_next_maps = {
        ["<leader>man"] = "@parameter.inner",
        ["<leader>mfn"] = "@function.outer",
        ["<leader>mcn"] = "@class.outer",
        ["<leader>mpn"] = "@attribute.outer",
      }
      local swap_prev_maps = {
        ["<leader>map"] = "@parameter.inner",
        ["<leader>mfp"] = "@function.outer",
        ["<leader>mcp"] = "@class.outer",
        ["<leader>mpp"] = "@attribute.outer",
      }
      for key, query in pairs(swap_next_maps) do
        vim.keymap.set("n", key, function() swap.swap_next(query, "textobjects") end)
      end
      for key, query in pairs(swap_prev_maps) do
        vim.keymap.set("n", key, function() swap.swap_previous(query, "textobjects") end)
      end
    end,
  },
  {
    "MeanderingProgrammer/treesitter-modules.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {
      incremental_selection = {
        enable = true,
        keymaps = {
          init_selection    = "<C-space>",
          node_incremental  = "<C-space>",
          -- scope_incremental = false,       -- у тебя было false
          node_decremental  = "<C-backspace>",
        },
      },
    },
  },
}
