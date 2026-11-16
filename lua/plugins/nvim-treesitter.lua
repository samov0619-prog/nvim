-- ~/.config/nvim/lua/plugins/nvim-treesitter.lua
--
-- Neovim 0.12 + nvim-treesitter `main`.
--
-- Главное отличие `main` от `master`: выпилен "модульный фреймворк".
-- Раньше setup() принимал highlight/indent/textobjects/incremental_selection.
-- Теперь setup() умеет только установку парсеров, а всё остальное
-- (подсветка, indent, folds) включается руками.
-- Отсюда автокоманды и циклы ниже — это не оверинжиниринг, это компенсация.

local ensure_installed = {
  -- ядро (нужно самому nvim: vimdoc/query для :help и .scm-файлов)
  "lua", "vim", "vimdoc", "query", "bash", "diff", "printf",
  -- фронт
  "javascript", "typescript", "tsx", "vue", "html", "css", "scss",
  "json", "json5", -- jsonc-парсера НЕ существует: ft jsonc -> парсер json
  -- (nvim-treesitter: language.register("json", "jsonc"))
  -- бэк / инфра
  "php", "phpdoc", "sql", "nix", "dockerfile", "yaml", "toml", "rust",
  -- git
  "git_config", "git_rebase", "gitcommit", "gitignore",
  -- прочее по мелочи
  "markdown", "markdown_inline", "mermaid", "xml", "ssh_config", "http",

  -- редко используемые
  "go", "gomod", "gosum", "java", "python"

  -- УБРАНО как мёртвый груз под твой стек (на `main` каждый парсер
  -- компилируется локально через tree-sitter CLI — это время сборки):
  -- пока не используемые
  -- "scheme", "asm", "disassembly", "dot", "csv"

  -- УБРАНО осознанно:
  --   "comment" — инжектится внутрь КАЖДОГО комментария в буфере, известный
  --   тормоз на больших файлах. TODO/NOTE подсвечивай через todo-comments.nvim.
}

-- filetypes, где treesitter-indent объективно хуже штатного indentexpr.
local indent_blacklist = {
  yaml = true,
  markdown = true,
  python = true, -- в питоне TS-indent до сих пор ломается на многострочных выражениях
}

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    -- Последний тег репы древний и не работает с `main`-API.
    -- Страхует от глобального defaults.version = "*" в lazy.setup().
    version = false,
    build = ":TSUpdate",
    config = function()
      -- setup() НЕ зовём. На `main` он отвечает только за install_dir, дефолт
      -- которого (stdpath("data").."/site") и так верный, а явная передача
      -- значения лишь дублирует запись в rtp (config.lua: prepend в ветке
      -- `if user_data.install_dir`). get_installed()/install() работают без него.
      -- Звать имеет смысл, только если парсеры реально нужны не в site/.

      ------------------------------------------------------------------------
      -- 1) Установка парсеров — замена опции `ensure_installed`
      ------------------------------------------------------------------------
      -- На `main` ensure_installed как опции нет. install() зовём сами.
      -- Диф против уже установленных нужен, чтобы не дёргать компиляцию
      -- на каждом старте: install() асинхронный, но не бесплатный.
      local installed = require("nvim-treesitter.config").get_installed()
      local to_install = vim.iter(ensure_installed)
          :filter(function(p) return not vim.tbl_contains(installed, p) end)
          :totable()
      if #to_install > 0 then
        require("nvim-treesitter").install(to_install)
      end

      -- zsh-буферы парсим bash-грамматикой (своего парсера у zsh нет).
      vim.treesitter.language.register("bash", "zsh")

      ------------------------------------------------------------------------
      -- 2) Подсветка + indent + folds — замена highlight.enable / indent.enable
      ------------------------------------------------------------------------
      local max_filesize = 500 * 1024

      local function attach(buf)
        if not vim.api.nvim_buf_is_valid(buf) then return end
        if not vim.api.nvim_buf_is_loaded(buf) then return end

        -- Гейт по размеру: на файлах в мегабайты TS кладёт редактор.
        local name = vim.api.nvim_buf_get_name(buf)
        local ok, st = pcall(vim.uv.fs_stat, name)
        if ok and st and st.size > max_filesize then return end

        -- vim.treesitter.start() идемпотентен, повторный вызов безвреден.
        -- pcall — потому что для ft без парсера он кинет ошибку.
        if not pcall(vim.treesitter.start, buf) then return end

        local ft = vim.bo[buf].filetype
        if not indent_blacklist[ft] then
          vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end

        -- Folds. vim.wo[0][0] вместо vim.wo — иначе опция протечёт
        -- в другие буферы того же окна (window-local vs win-buf-local).
        vim.api.nvim_buf_call(buf, function()
          vim.wo[0][0].foldexpr = "v:lua.vim.treesitter.foldexpr()"
          vim.wo[0][0].foldmethod = "expr"
        end)
      end

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("ts_start", { clear = true }),
        callback = function(ev) attach(ev.buf) end,
      })
      -- Автокоманда создаётся в config(), т.е. уже открытые буферы её пропустят
      -- (актуально при :Lazy reload и при lazy-загрузке). Догоняем вручную.
      vim.tbl_map(attach, vim.api.nvim_list_bufs())

    end,
  },

  -- Пасхалка вынесена из dependencies: там она грузилась вместе с treesitter
  -- на каждом старте. Теперь — только по команде.
  {
    "eandrju/cellular-automaton.nvim",
    cmd = "CellularAutomaton",
    keys = {
      { "<leader>mir", "<cmd>CellularAutomaton make_it_rain<CR>", desc = "Make it rain" },
    },
  },
}
