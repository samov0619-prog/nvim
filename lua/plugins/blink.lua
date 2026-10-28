return {
  {
    'saghen/blink.cmp',
    version = '1.*',
    -- enabled = false,
    dependencies = {
      'L3MON4D3/LuaSnip',
      "moyiz/blink-emoji.nvim",
    },
    ---@module 'blink.cmp'
    ---@type blink.cmp.Config
    opts = {
      snippets = { preset = 'luasnip' },
      completion = {
        ghost_text = {
          enabled = false,
        },
        list = {
          selection = { preselect = true, auto_insert = true }
        },
        menu = {
          auto_show = false,
          draw = {
            components = {
              label_description = {
                width = {
                  fill = true,
                  max = 60,
                },
              },
              label = {
                width = { fill = true, max = 100 },
                text = function(ctx)
                  local label = ctx.label or ''
                  local max_width = 100
                  local label_width = vim.fn.strdisplaywidth(label)

                  if label_width > max_width then
                    local start = label_width - max_width + 1
                    label = vim.fn.strcharpart(label, start, max_width)
                    label = '…' .. label
                  end

                  return label
                end
              }
            }
          }
        },
      },
      signature = { enabled = false },
      fuzzy = {
        implementation = 'lua',
        prebuilt_binaries = {
          download = false,
        },
      },
      keymap = {
        ['<C-space>'] = { 'show', 'show_documentation', 'hide_documentation', 'fallback' },
        ['<Tab>'] = {
          function(cmp) return require('config.completion').tab(cmp, 1) end,
          'fallback',
        },
        ['<S-Tab>'] = {
          function(cmp) return require('config.completion').tab(cmp, -1) end,
          'fallback',
        },
        -- With ghost text disabled, these only handle an open menu.
        ['<CR>'] = { 'accept', 'fallback' },
        ['<Esc>'] = { 'cancel', 'fallback' },
        ['<C-e>'] = false,
        -- Snippet navigation must not compete with completion or tabout.
        ['<C-j>'] = { 'snippet_forward', 'fallback' },
        ['<C-k>'] = { 'snippet_backward', 'fallback' },
      },
      sources = {
        default = { 'lsp', 'path', 'snippets', 'buffer', 'emoji' },
        providers = {
          emoji = {
            module = "blink-emoji",
            name = "Emoji",
            score_offset = 15, -- Tune by preference
            -- min_keyword_length = 2,
            opts = {
              ---@type string|table|fun():table
              trigger = { ":" }
            },
            should_show_items = function()
              return true
            end
          },
          cmdline = {
            min_keyword_length = function(ctx)
              -- when typing a command, only show when the keyword is 3 characters or longer
              if ctx.mode == 'cmdline' and string.find(ctx.line, ' ') == nil then return 3 end
              return 0
            end
          },
        }
      },
      cmdline = {
        completion = {
          menu = {
            auto_show = function(ctx)
              return vim.fn.getcmdtype() == ':' or vim.fn.getcmdtype() == '@'
              -- enable for inputs as well, with:
              -- or vim.fn.getcmdtype() == '@'
            end,
            draw = {
              columns = { { 'kind_icon' }, { 'label', gap = 1 } },
            }
          }
        },
        keymap = {
          ['<CR>'] = { 'accept', 'fallback' }
        }
      }
    },
    config = function(_, opts)
      require('blink.cmp').setup(opts)
      require('config.completion').setup()
    end,
    opts_extend = { "sources.default" }
  },
  {
    'windwp/nvim-autopairs',
    event = "InsertEnter",
    opts = {}
  },
  {
    "windwp/nvim-ts-autotag",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    event = "InsertEnter",
    opts = {}
  },
}
