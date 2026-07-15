-- ~/.config/nvim/lua/plugins/nvim-treesitter.lua
--
-- Neovim 0.12 + nvim-treesitter `main`.
--
-- Главное отличие `main` от `master`: выпилен "модульный фреймворк".
-- Раньше setup() принимал highlight/indent/textobjects/incremental_selection.
-- Теперь setup() умеет только установку парсеров, а всё остальное
-- (подсветка, indent, folds, keymaps) включается руками.
-- Отсюда автокоманды и циклы ниже — это не оверинжиниринг, это компенсация.

local ensure_installed = {
  -- ядро (нужно самому nvim: vimdoc/query для :help и .scm-файлов)
  "lua", "vim", "vimdoc", "query", "bash", "diff", "printf",
  -- фронт
  "javascript", "typescript", "tsx", "vue", "html", "css", "scss",
  "json", "json5", -- jsonc-парсера НЕ существует: ft jsonc -> парсер json
  -- (nvim-treesitter: language.register("json", "jsonc"))
  -- бэк / инфра
  "php", "phpdoc", "sql", "nix", "dockerfile", "yaml", "toml",
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
    dependencies = {
      {
        "nvim-treesitter/nvim-treesitter-textobjects",
        branch = "main",
        version = false,
        init = function()
          -- Встроенные ftplugin'ы Neovim (runtime/ftplugin/*.vim) вешают свои
          -- ]] [[ ]m [m ]M [M для php/python/ruby/etc. Они конфликтуют с
          -- move-маппингами ниже и выигрывают, т.к. буфер-локальные.
          -- README textobjects прямо рекомендует эту строку.
          -- Если что-то из ftplugin-маппингов нужно — отключай точечно:
          --   vim.g.no_php_maps = true
          vim.g.no_plugin_maps = true
        end,
      },
    },
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

      ------------------------------------------------------------------------
      -- 3) Textobjects
      ------------------------------------------------------------------------
      require("nvim-treesitter-textobjects").setup({
        select = {
          -- Прыгнуть вперёд к ближайшему объекту, если курсор не внутри (как targets.vim)
          lookahead = true,
          include_surrounding_whitespace = false,
        },
        move = { set_jumps = true }, -- прыжки попадают в jumplist, работает <C-o>
      })
      local select = require("nvim-treesitter-textobjects.select")
      local move   = require("nvim-treesitter-textobjects.move")
      local swap   = require("nvim-treesitter-textobjects.swap")

      ------------------------------------------------------------------------
      -- 3a) SELECT
      ------------------------------------------------------------------------
      -- Цикл — просто чтобы не плодить 20 одинаковых vim.keymap.set.
      -- Замыкание над `q` безопасно: Lua создаёт новую локалку на итерацию.
      --
      -- Свободны намеренно:
      --   at/it — встроенный tag-объект (cit в JSX/TSX, не отдавать!)
      --   an/in — incremental selection Neovim 0.12
      --   ab/ib — встроенные () и {}
      local sel    = {
        ["af"] = "@function.outer",    -- определение функции целиком
        ["if"] = "@function.inner",    -- тело функции
        ["ac"] = "@class.outer",       -- class / interface / type / enum
        ["ic"] = "@class.inner",
        ["am"] = "@call.outer",        -- m = method call: foo(a, b)
        ["im"] = "@call.inner",        -- только аргументы внутри скобок
        ["aa"] = "@parameter.outer",   -- аргумент вместе с запятой
        ["ia"] = "@parameter.inner",   -- только сам аргумент
        ["ai"] = "@conditional.outer", -- i = if
        ["ii"] = "@conditional.inner",
        ["al"] = "@loop.outer",
        ["il"] = "@loop.inner",
        ["ao"] = "@block.outer",      -- o вместо занятого n
        ["io"] = "@block.inner",
        ["a="] = "@assignment.outer", -- const x = foo()
        ["i="] = "@assignment.inner",
        ["ar"] = "@return.outer",
        ["ir"] = "@return.inner",
        -- кастомные, из after/queries/ecma/textobjects.scm:
        ["aO"] = "@obj.outer",  -- объектный литерал целиком, со скобками
        ["iO"] = "@obj.inner",  -- содержимое между { }
        ["ae"] = "@elem.outer", -- элемент массива
      }
      for lhs, q in pairs(sel) do
        vim.keymap.set({ "x", "o" }, lhs, function()
          select.select_textobject(q, "textobjects")
        end, { desc = "TS select " .. q })
      end

      -- lhs/rhs присваивания — ТОЛЬКО в operator-pending.
      -- В visual `r` — это оператор замены (v_r), маппинг r= его убивал:
      -- каждое `r` ждало timeoutlen, а `vr=` становился невозможен.
      -- В "o" конфликта нет: dr= / cr= / yr= работают, v_r цел.
      vim.keymap.set("o", "r=", function()
        select.select_textobject("@assignment.rhs", "textobjects")
      end, { desc = "TS select @assignment.rhs" })
      vim.keymap.set("o", "l=", function()
        select.select_textobject("@assignment.lhs", "textobjects")
      end, { desc = "TS select @assignment.lhs" })

      ------------------------------------------------------------------------
      -- 3b) MOVE
      ------------------------------------------------------------------------
      -- move.* принимает СПИСОК captures и берёт первый подошедший —
      -- бесплатный фолбэк для языков, где определён не весь набор.
      --
      -- ]] [[ ][ [] для классов — канон README. Перекрывают встроенные
      -- section-motions (прыжок к { в первой колонке) — TS-версия строго лучше.
      -- ]c/[c брать нельзя (diff), ]s/[s нельзя (spell).
      -- ]i/[i перекрывают include-search — легаси из C-эпохи, не жалко.
      -- ]a/[a перекрывают :next/:previous по arglist — если пользуешься, замени.
      local moves = {
        goto_next_start = {
          ["]m"] = "@function.outer",
          ["]]"] = "@class.outer",
          ["]o"] = { "@loop.inner", "@loop.outer" },
          ["]i"] = "@conditional.outer",
          ["]a"] = "@parameter.inner",
          ["]e"] = "@elem.outer", -- кастомный: элемент массива (after/queries/ecma)
        },
        goto_next_end = {
          ["]M"] = "@function.outer",
          ["]["] = "@class.outer",
        },
        goto_previous_start = {
          ["[m"] = "@function.outer",
          ["[["] = "@class.outer",
          ["[o"] = { "@loop.inner", "@loop.outer" },
          ["[i"] = "@conditional.outer",
          ["[a"] = "@parameter.inner",
          ["[e"] = "@elem.outer", -- кастомный: элемент массива (after/queries/ecma)
        },
        goto_previous_end = {
          ["[M"] = "@function.outer",
          ["[]"] = "@class.outer",
        },
      }
      for method, maps in pairs(moves) do
        for lhs, q in pairs(maps) do
          vim.keymap.set({ "n", "x", "o" }, lhs, function()
            -- В diff-режиме не перехватываем ]c/[c — на будущее, если добавишь.
            move[method](q, "textobjects")
          end, { desc = "TS " .. method .. " " .. vim.inspect(q) })
        end
      end

      -- ; и , повторяют последний move-прыжок. Одна из лучших фич плагина,
      -- и она же чинит штатные f/t/F/T (их repeat тоже проксируется).
      local rep = require("nvim-treesitter-textobjects.repeatable_move")
      vim.keymap.set({ "n", "x", "o" }, ";", rep.repeat_last_move_next)
      vim.keymap.set({ "n", "x", "o" }, ",", rep.repeat_last_move_previous)
      vim.keymap.set({ "n", "x", "o" }, "f", rep.builtin_f_expr, { expr = true })
      vim.keymap.set({ "n", "x", "o" }, "F", rep.builtin_F_expr, { expr = true })
      vim.keymap.set({ "n", "x", "o" }, "t", rep.builtin_t_expr, { expr = true })
      vim.keymap.set({ "n", "x", "o" }, "T", rep.builtin_T_expr, { expr = true })

      ------------------------------------------------------------------------
      -- 3c) SWAP — одна клавиша, capture подбирается сам
      ------------------------------------------------------------------------
      -- swap_next/swap_previous ПРИНИМАЮТ СПИСОК и сами перебирают кандидатов
      -- через shared.textobject_at_point, останавливаясь на первом, что попал
      -- под курсор (swap.lua: `for _, query_string_iter in ipairs(query_strings)`).
      -- Перебирать вручную нельзя: swap_* асинхронный — он лишь ставит opfunc и
      -- кидает `g@l` в typeahead, а сам своп случается позже. Ручной цикл
      -- перезатирает opfunc последним кандидатом и копит N штук `g@l`,
      -- отчего узел уезжает через весь список.
      --
      -- Порядок = приоритет, от специфичного к общему.
      local swap_candidates = {
        -- кастомный (after/queries): свойства объекта, элементы массива,
        -- члены класса, ветки тернарника; в json/json5 — пары; в css — свойства,
        -- селекторы в списке, вложенные правила; в scss — ещё параметры и аргументы
        "@swappable.outer",
        -- стоковый, queries/jsx: (jsx_attribute) @attribute.outer.
        -- javascript/tsx наследуют jsx, так что JSX-пропсы работают из коробки.
        "@attribute.outer",
        -- стоковый: аргументы вызова и параметры сигнатуры
        "@parameter.inner",
      }

      -- Нужны ОБЕ клавиши, и это не вкусовщина.
      --
      -- swap_* оборачивает себя в opfunc (make_dot_repeatable), поэтому `.`
      -- повторяет своп. Но курсор едет за узлом, НА КОТОРОМ ТЫ СТОИШЬ, а не
      -- за тем, который двигаешь (swap_nodes: cursor_to_second). Отсюда:
      --
      --   <leader>a + . . .  -> узел под курсором едет ВПРАВО, курсор с ним
      --   <leader>A + . . .  -> узел под курсором едет ВЛЕВО, курсор с ним
      --
      -- Заменить <leader>A на "<leader>a с левого соседа" нельзя: состояние
      -- буфера выйдет то же, но курсор останется на соседе — который теперь
      -- СПРАВА от цели, — и `.` свопнет их обратно. Пинг-понг:
      --   f(aaa, bbb, ccc, ddd);  курсор на ccc
      --   <leader>a  ->  f(aaa, bbb, ddd, ccc);  курсор на ccc
      --   .          ->  f(aaa, bbb, ccc, ddd);  откат
      -- Так узел двигается влево ровно на один шаг за ручную навигацию.
      vim.keymap.set("n", "<leader>a", function()
        swap.swap_next(swap_candidates)
      end, { desc = "TS swap -> (auto)" })

      vim.keymap.set("n", "<leader>A", function()
        swap.swap_previous(swap_candidates)
      end, { desc = "TS swap <- (auto)" })
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
