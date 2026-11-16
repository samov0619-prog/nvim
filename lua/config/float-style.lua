-- Shared presentation through public Neovim/plugin settings; no window/API interception.
local M = {}
M.border = { '🭽', '▔', '🭾', '▕', '🭿', '▁', '🭼', '▏' }
local api = vim.api

local function surface_highlight(name, foreground, background)
  local fg = api.nvim_get_hl(0, { name = foreground, link = false })
  local bg = api.nvim_get_hl(0, { name = background, link = false })
  api.nvim_set_hl(0, name, {
    fg = fg.fg or bg.fg, bg = bg.bg,
    ctermfg = fg.ctermfg or bg.ctermfg, ctermbg = bg.ctermbg,
  })
end

function M.highlights()
  surface_highlight('FloatBorder', 'Comment', 'NormalFloat')
  surface_highlight('FloatTitle', 'Title', 'NormalFloat')
  surface_highlight('UserFloatNormalBorder', 'Comment', 'Normal')
  -- A dimmed Fzf backdrop can visually swallow the neutral outline on white.
  -- Detect the actual surface: this Sonokai light palette can still report background=dark.
  local bg = api.nvim_get_hl(0, { name = 'Normal', link = false }).bg
  local light = bg and (math.floor(bg / 65536) * 299 + math.floor(bg / 256) % 256 * 587 + bg % 256 * 114) / 1000 > 128
  surface_highlight('UserFzfBorder', light and 'Normal' or 'Comment', 'Normal')
  surface_highlight('UserFloatNormalTitle', 'Title', 'Normal')
  surface_highlight('UserFloatMenuBorder', 'Comment', 'Pmenu')
  -- Preserve MiniFiles' unsaved-change warning, but not a mismatched background.
  surface_highlight('MiniFilesBorderModified', 'DiagnosticWarn', 'NormalFloat')
end

function M.setup()
  vim.opt.winborder = M.border
  M.highlights()
  api.nvim_create_autocmd('ColorScheme', {
    group = api.nvim_create_augroup('UserFloatStyle', { clear = true }),
    callback = M.highlights,
  })
end

return M
