local opts = { noremap = true, silent = true }

return {
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "folke/lazydev.nvim",
      "Bilal2453/luvit-meta"
    },
    config = function()
      local tools = require("config.code-tools")
      require("lazydev").setup(
        {
          library = {
            { path = "luvit-meta/library", words = { "vim%.uv" } },
          },
        }
      )

      local function lsp_on_attach(bufnr)
        vim.keymap.set("n", "<space>lgd", vim.lsp.buf.definition,
          vim.tbl_extend('force', { buffer = bufnr, desc = "go to definition" }, opts))
        vim.keymap.set("n", "<space>lgt", vim.lsp.buf.type_definition,
          vim.tbl_extend('force', { buffer = bufnr, desc = "go to type definition" }, opts))
        vim.keymap.set("n", "<space>lgr", vim.lsp.buf.references,
          vim.tbl_extend('force', { buffer = bufnr, desc = "go to references" }, opts))
        vim.keymap.set("n", "<space>lgi", vim.lsp.buf.implementation,
          vim.tbl_extend('force', { buffer = bufnr, desc = "go to implementation" }, opts))
        vim.keymap.set({ "n", "i" }, "<C-s>", vim.lsp.buf.signature_help,
          vim.tbl_extend('force', { buffer = bufnr, desc = "signature help" }, opts))
        vim.keymap.set({ "n", "i" }, "<C-a>", vim.lsp.buf.hover,
          vim.tbl_extend('force', { buffer = bufnr, desc = "hover" }, opts))
        vim.keymap.set("n", "<space>lrn", vim.lsp.buf.rename,
          vim.tbl_extend('force', { buffer = bufnr, desc = "rename" }, opts))
        vim.keymap.set({ "n", "v" }, "<leader>lca", vim.lsp.buf.code_action,
          vim.tbl_extend('force', { buffer = bufnr, desc = "code action" }, opts))
        vim.keymap.set("n", "<leader>lrs", function()
          if #vim.lsp.get_clients({ bufnr = bufnr }) == 0 then
            vim.notify("No LSP clients attached", vim.log.levels.WARN)
            return
          end

          vim.diagnostic.reset(nil, bufnr)
          vim.cmd.lsp({ args = { "restart" } })
          vim.notify("LSP restarted", vim.log.levels.INFO)
        end, { buffer = bufnr, desc = "reset diagnostics & restart lsp" })
      end

      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("LspKeymaps", { clear = true }),
        callback = function(args)
          if tools.is_file_buffer(args.buf) and vim.lsp.get_client_by_id(args.data.client_id) then
            lsp_on_attach(args.buf)
          end
        end,
      })


      vim.lsp.config("bashls", {
        filetypes = {
          "sh", "zsh"
        }
      })

      vim.lsp.config("basedpyright", {
        -- basedpyright discovers the project's .venv itself; explicit project
        -- interpreter/type-checking settings retain their native precedence.
        settings = {
          basedpyright = {
            analysis = {
              typeCheckingMode = "standard",
              diagnosticMode = "openFilesOnly",
            },
          },
        },
      })

      require("config.ts-toolchain").setup()

      local function disable_lint_pull_diagnostics(client)
        -- The shared scheduler owns diagnostics, including pull-based servers
        -- and explicit Biome workspace requests for unsaved buffers.
        client.server_capabilities.diagnosticProvider = nil
      end

      local lint_servers = { "biome", "eslint", "stylelint_lsp" }
      for _, name in ipairs(lint_servers) do
        vim.lsp.config(name, {
          -- Automatic diagnostics would duplicate the shared scheduler's results.
          handlers = { ["textDocument/publishDiagnostics"] = function() end },
          on_init = disable_lint_pull_diagnostics,
          root_dir = function(bufnr, on_dir)
            if not tools.is_file_buffer(bufnr) then return end
            local tool = tools.resolve(bufnr).lsp[name]
            if tool then on_dir(tool.cwd) end
          end,
        })
      end
      vim.lsp.config("eslint", {
        filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "vue" },
      })
      local biome_filetypes = vim.deepcopy(vim.lsp.config.biome.filetypes or {})
      for ft in pairs(tools.format_filetypes) do
        if not vim.tbl_contains(biome_filetypes, ft) then biome_filetypes[#biome_filetypes + 1] = ft end
      end
      vim.lsp.config("biome", {
        filetypes = biome_filetypes,
        handlers = { ["textDocument/publishDiagnostics"] = function(err, params, context)
          local diagnostics = package.loaded["config.code-diagnostics"]
          if not err and diagnostics then diagnostics.biome_changed(params, context) end
        end },
        cmd = function(dispatchers, config)
          -- root_dir includes the selected package binary's scope; resolution
          -- can still reach a hoisted binary within the Git/package boundary.
          config._code_tools_cmd = assert(tools.executable("biome", config.root_dir), "Biome executable not found")
          return vim.lsp.rpc.start({ config._code_tools_cmd, "lsp-proxy" }, dispatchers)
        end,
        reuse_client = function(client, config)
          return not client:is_stopped() and tools.biome_client_matches(client, {
            cwd = config.root_dir, cmd = tools.executable("biome", config.root_dir),
          })
        end,
      })

      local function sync_lint_clients(bufnr)
        if not tools.is_file_buffer(bufnr) then return end
        local ctx = tools.resolve(bufnr)
        for _, name in ipairs(lint_servers) do
          if vim.lsp.is_enabled(name) then
            local lsp_config = vim.lsp.config[name]
            local tool = vim.tbl_contains(lsp_config.filetypes, ctx.ft) and ctx.lsp[name] or nil
            local attached = false
            for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr, name = name })) do
              if tool and client.config.root_dir == tool.cwd
                  and (name ~= "biome" or tools.biome_client_matches(client, tool)) then
                attached = true
              else
                vim.lsp.buf_detach_client(bufnr, client.id)
              end
            end
            if tool and not attached then
              local config = vim.deepcopy(lsp_config)
              config.root_dir = tool.cwd
              vim.lsp.start(config, { bufnr = bufnr, reuse_client = config.reuse_client })
            end
          end
        end
      end

      -- Moving/adding a config does not fire FileType again. Keep all lint
      -- clients in sync so an old profile cannot survive through LSP fallback.
      vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "FocusGained" }, {
        group = vim.api.nvim_create_augroup("CodeProjectConfig", { clear = true }),
        callback = function(args) sync_lint_clients(args.buf) end,
      })
      -- local vue_language_server_path = vim.fn.exepath('vue-language-server')
      --   :gsub('/bin/vue%-language%-server$', '')
      --   .. '/lib/node_modules/@vue/language-server'
      -- local tsserver_filetypes = { 'typescript', 'javascript', 'javascriptreact', 'typescriptreact', 'vue' }
      -- local vue_plugin = {
      --   name = '@vue/typescript-plugin',
      --   location = vue_language_server_path,
      --   languages = { 'vue' },
      --   configNamespace = 'typescript',
      -- }
      -- local vtsls_config = {
      --   settings = {
      --     vtsls = {
      --       tsserver = {
      --         globalPlugins = {
      --           vue_plugin,
      --         },
      --       },
      --     },
      --   },
      --   on_attach = function(client)
      --     local existing_capabilities = client.server_capabilities
      --     if vim.bo.filetype == 'vue' then
      --       existing_capabilities.semanticTokensProvider.full = false
      --     else
      --       existing_capabilities.semanticTokensProvider.full = true
      --     end
      --   end,
      --   filetypes = tsserver_filetypes,
      -- }
      -- local vue_ls_config = {}
      -- vim.lsp.config('vtsls', vtsls_config)
      -- vim.lsp.config('vue_ls', vue_ls_config)

      vim.lsp.config("lua_ls", {
        root_markers = {
          "init.lua",
          ".luarc.json",
          ".luarc.jsonc",
          ".luacheckrc",
          ".stylua.toml",
          "stylua.toml",
          "selene.toml",
          "selene.yml",
          ".git"
        }

      })

      vim.lsp.config("lemminx", {
        init_options = {
          settings = {
            xml = {
              -- Когда в fonts.conf встретится SYSTEM "urn:fontconfig:fonts.dtd",
              -- подставлять локальный файл /etc/fonts/fonts.dtd
              fileAssociations = {
                {
                  systemId = "urn:fontconfig:fonts.dtd",
                  uri      = "file:///etc/fonts/fonts.dtd",
                  pattern  = "**/fonts.conf",
                },
              },
              -- Необязательно: OASIS‑каталоги мы не используем
              catalogs = {},
            },
          },
        },
      })

      vim.lsp.config("nixd", {
        settings = {
          nixd = {
            formatting = {
              command = { "nixfmt" }
            }
          },
        },
      })

      -- vim.lsp.config("gopls", {
      --   settings = {
      --     gopls = {
      --       completeUnimported = true,
      --       usePlaceholders = false,
      --       matcher = "Fuzzy",
      --       analyses = {
      --         unusedparams = false,
      --         shadow = false,
      --       },
      --       staticcheck = false,
      --       codelenses = {
      --         gc_details = false,
      --       },
      --     },
      --   },
      --   flags = {
      --     debounce_text_changes = 300,
      --   },
      -- })

      vim.lsp.config("yamlls", {
        settings = {
          yaml = {
            validate = true,
            hover = true,
            completion = true,
            format = { enable = false },
            schemaStore = { enable = true },
          },
        },
      })

      -- Let the enabled hyprls config own attachment, like other native LSPs.
      -- Preserve the filenames previously handled by the manual BufEnter start.
      vim.filetype.add({
        extension = { hl = "hyprlang" },
        pattern = { [".*/hypr[^/]*%.conf"] = "hyprlang" },
      })

      vim.lsp.enable({
        "gopls",
        "basedpyright",
        "bashls",
        "hyprls",
        "lua_ls",
        "nixd",
        -- "marksman",
        "ts_ls",
        "vue_ls",
        "eslint",
        "yamlls",
      })

      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("DisableLspForTempFiles", { clear = true }),
        callback = function(args)
          local buf = args.buf
          if not tools.is_file_buffer(buf) then return end
          local filepath = vim.api.nvim_buf_get_name(buf)

          if filepath:match("^/tmp/nvim") then
            vim.diagnostic.enable(false, { bufnr = buf })
          end
        end,
      })
    end,
  }
}
