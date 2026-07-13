return {
  {
    "nvim-mini/mini.files",
    dependencies = { "nvim-mini/mini.icons" },
    config = function()
      local mf = require("mini.files")

      mf.setup({
        options = {
          use_as_default_explorer = true,
          permanent_delete = true, -- корзина на маке всё равно не работает — удаляем насовсем
        },
        mappings = {
          synchronize = "", -- отключаем '=' : применяем только через :w
        },
        windows = {
          preview = true,
          width_focus = 40,
          width_preview = 40,
        },
      })

      -- cwd на директорию текущей колонки (аналог actions.cd в oil).
      -- dirname(entry) = каталог, который сейчас показан (у всех записей колонки
      -- общий родитель), поэтому не важно, на какой строке курсор.
      local function set_cwd(scope) -- "cd" | "tcd"
        local entry = mf.get_fs_entry()
        if not entry then return end
        local dir = vim.fs.dirname(entry.path)
        if not dir then return end
        vim.cmd[scope]({ args = { vim.fn.fnameescape(dir) }, mods = { silent = true } })
        -- zoxide подхватит через DirChanged-автокоманду из fzf-конфига
      end

      vim.api.nvim_create_autocmd("User", {
        pattern = "MiniFilesBufferCreate",
        callback = function(args)
          local buf = args.data.buf_id

          -- cwd по желанию
          vim.keymap.set("n", "`", function() set_cwd("cd") end,
            { buffer = buf, desc = "cd here" })
          vim.keymap.set("n", "~", function() set_cwd("tcd") end,
            { buffer = buf, desc = "tcd here" })

          -- Если захочу CR go_in т.е. переход в файл по ентеру а не l q
          -- vim.keymap.set("n", "<CR>", function()
          --   require("mini.files").go_in({ close_on_file = true })
          -- end, { buffer = buf, desc = "open file & close" })


          -- гарантируем, что :w перехватывается (иначе E382 на не-acwrite буфере).
          -- если mini сломается — убери эту строку.
          if vim.bo[buf].buftype ~= "acwrite" then
            vim.bo[buf].buftype = "acwrite"
          end

          -- :w -> synchronize (подтверждение y/n = твой ":w -> y")
          vim.api.nvim_create_autocmd("BufWriteCmd", {
            buffer = buf,
            callback = function()
              require("mini.files").synchronize()
            end,
          })
        end,
      })
    end,
    keys = {
      {
        "<leader>e",
        function()
          local mf = require("mini.files")
          -- toggle: открыть на директории текущего файла
          if not mf.close() then
            mf.open(vim.api.nvim_buf_get_name(0))
          end
        end,
        desc = "mini.files",
      },
    },
  }
}
