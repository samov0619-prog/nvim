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

      vim.api.nvim_create_autocmd("User", {
        pattern = "SwapDiffPrompt",
        callback = function() mf.close() end,
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

      local function go_in(opts)
        local entry = mf.get_fs_entry()
        if entry and entry.fs_type == "file" then
          local buf = vim.fn.bufadd(entry.path)
          if not vim.api.nvim_buf_is_loaded(buf) then
            -- nvim_win_set_buf() in MiniFiles bypasses SwapExists; :edit runs it.
            local state = mf.get_explorer_state()
            vim.api.nvim_win_call(state.target_window, function()
              vim.cmd.edit(vim.fn.fnameescape(entry.path))
            end)
          end
        end
        mf.go_in(opts)
      end

      vim.api.nvim_create_autocmd("User", {
        pattern = "MiniFilesBufferCreate",
        callback = function(args)
          local buf = args.data.buf_id

          vim.keymap.set("n", mf.config.mappings.go_in, function()
            for _ = 1, vim.v.count1 do go_in() end
          end, { buffer = buf, nowait = true, desc = "Go in entry" })
          vim.keymap.set("n", mf.config.mappings.go_in_plus, function()
            go_in({ close_on_file = true })
          end, { buffer = buf, nowait = true, desc = "Go in entry plus" })

          -- cwd по желанию
          vim.keymap.set("n", "`", function() set_cwd("cd") end,
            { buffer = buf, desc = "cd here" })
          vim.keymap.set("n", "~", function() set_cwd("tcd") end,
            { buffer = buf, desc = "tcd here" })

          -- Если захочу CR go_in т.е. переход в файл по ентеру а не l q
          -- vim.keymap.set("n", "<CR>", function()
          --   require("mini.files").go_in({ close_on_file = true })
          -- end, { buffer = buf, desc = "open file & close" })


          -- :w requires acwrite. Internal list updates are marked clean below;
          -- user edits retain modified and keep Neovim's normal quit protection.
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

      vim.api.nvim_create_autocmd("User", {
        pattern = "MiniFilesBufferUpdate",
        callback = function(args)
          -- MiniFiles normally uses nofile and tracks edits itself. With
          -- acwrite, rendering/synchronizing a listing also sets 'modified'.
          -- This event only follows an internal content update, not user edits.
          local buf = args.data.buf_id
          if vim.api.nvim_buf_is_valid(buf) then vim.bo[buf].modified = false end
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
