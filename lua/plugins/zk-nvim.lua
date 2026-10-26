return {
  {
    "zk-org/zk-nvim",
    config = function()
      local os_name = vim.uv.os_uname().sysname
      if os_name == "Darwin" then
        return
      end
      local tools = require("config.code-tools")
      local zk = require("zk")
      zk.setup({
        picker = "fzf_lua",
        lsp = {
          -- `config` is passed to `vim.lsp.start_client(config)`
          config = {
            cmd  = { "zk", "lsp" },
            name = "zk",
            -- on_attach = ...
            -- etc, see `:h vim.lsp.start_client()`
          },

          -- automatically attach buffers in a zk notebook that match the given filetypes
          auto_attach = {
            enabled = false,
          },
        },
      })

      -- zk's own auto-attach only excludes nofile buffers. Share the same file
      -- gate as our native LSP/tooling callbacks before notebook discovery.
      local function attach(bufnr)
        if tools.is_file_buffer(bufnr) and vim.bo[bufnr].filetype == "markdown"
            and require("zk.util").notebook_root(vim.api.nvim_buf_get_name(bufnr)) then
          require("zk.lsp").buf_add(bufnr)
        end
      end
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("ZkLspAttach", { clear = true }),
        pattern = "markdown",
        callback = function(args) attach(args.buf) end,
      })
      attach(vim.api.nvim_get_current_buf())

      local opts = { noremap = true, silent = false }
      vim.keymap.set("n", "<leader>zkn", "<Cmd>ZkNew<CR>", { desc = "new note" })
      vim.keymap.set("n", "<leader>zkN", "<Cmd>ZkNew { title = vim.fn.input('Title: ') }<CR>",
        { desc = "new note with title" })
      -- Open notes.
      vim.keymap.set("n", "<leader>zko", "<Cmd>ZkNotes { sort = { 'modified' } }<CR>", { desc = "open notes" })
      -- Open notes associated with the selected tags.
      vim.keymap.set("n", "<leader>zkt", "<Cmd>ZkTags<CR>", { desc = "open tags" })
      -- Search for the notes matching a given query.
      vim.keymap.set("n", "<leader>zkf",
        "<Cmd>ZkNotes { sort = { 'modified' }, match = { vim.fn.input('Search: ') } }<CR>",
        { desc = "find notes" })
      -- Search for the notes matching the current visual selection.
      vim.keymap.set("v", "<leader>zkf", ":'<,'>ZkMatch<CR>", { desc = "find notes" })
    end
  }
}
