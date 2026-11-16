-- Run: nvim -n --headless -u NONE -i NONE -l tests/float-style.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp:prepend(root)
for _, plugin in ipairs({ 'mini.files', 'mini.icons', 'blink.cmp', 'sonokai' }) do
  vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/' .. plugin)
end
local api = vim.api
local style = require('config.float-style')
vim.o.lines, vim.o.columns = 50, 160
style.setup()
assert(vim.deep_equal(vim.opt.winborder:get(), style.border), 'Public global border option')
local function background(name) return api.nvim_get_hl(0, { name = name, link = false }).bg end
for _, colors in ipairs({ { 0x202020, 0x303030, 0x404040 }, { 0xffffff, 0xf0f0f0, 0xe0e0e0 } }) do
  api.nvim_set_hl(0, 'Normal', { fg = 0x888888, bg = colors[1] })
  api.nvim_set_hl(0, 'NormalFloat', { fg = 0x888888, bg = colors[2] })
  api.nvim_set_hl(0, 'Pmenu', { fg = 0x888888, bg = colors[3] })
  api.nvim_set_hl(0, 'Comment', { fg = 0x777777, bg = 0x000000 })
  api.nvim_set_hl(0, 'DiagnosticWarn', { fg = 0xffaa00 })
  api.nvim_exec_autocmds('ColorScheme', { pattern = 'float-style-test' })
  assert(background('FloatBorder') == colors[2] and background('FloatTitle') == colors[2])
  assert(background('UserFloatNormalBorder') == colors[1] and background('UserFloatNormalTitle') == colors[1])
  assert(background('UserFloatMenuBorder') == colors[3])
  assert(background('MiniFilesBorderModified') == colors[2])
  assert(api.nvim_get_hl(0, { name = 'MiniFilesBorderModified', link = false }).fg == 0xffaa00,
    'Unsaved-change warning colour survives')
end
vim.cmd.colorscheme('sonokai')
assert(background('FloatBorder') == background('NormalFloat'), 'Real theme reload reapplies matching background')
assert(background('UserFloatNormalBorder') == background('Normal'), 'Fzf/UFO retain their original Normal surface')
local dark_border = api.nvim_get_hl(0, { name = 'UserFzfBorder', link = false })
assert(dark_border.fg == api.nvim_get_hl(0, { name = 'Comment', link = false }).fg, 'Dark Fzf border remains neutral')
-- Use the actual custom light palette, not background=light (the theme overrides RGB values).
local theme_source = table.concat(vim.fn.readfile(root .. '/lua/plugins/themes.lua'), '\n')
vim.g.sonokai_colors_override = assert(loadstring('return ' .. theme_source:match('local light = (%b{})')))()
vim.cmd.colorscheme('sonokai')
local border = api.nvim_get_hl(0, { name = 'UserFzfBorder', link = false })
assert(border.bg == background('Normal') and border.fg == 0x303030,
  'Actual Sonokai light Fzf outline is dark on white, irrespective of background option')
assert(api.nvim_get_hl(0, { name = 'UserFloatNormalBorder', link = false }).fg == 0x7f8490,
  'Only Fzf contrast changes, not UFO or other float borders')
local function check(win, label)
  assert(vim.deep_equal(api.nvim_win_get_config(win).border, style.border), label)
end
local buf = api.nvim_create_buf(false, true)
local win = api.nvim_open_win(buf, false, { relative = 'editor', row = 1, col = 1, width = 30, height = 4, style = 'minimal' })
check(win, 'Native float inherits global Unicode border')
api.nvim_win_close(win, true)
local _, hover = vim.lsp.util.open_floating_preview({ 'Hover fixture' }, 'plaintext', { focusable = false })
check(hover, 'Native LSP floating preview inherits border')
api.nvim_win_close(hover, true)
vim.api.nvim_create_augroup('FileExplorer', { clear = true })
local mf = require('mini.files')
mf.setup({ windows = { preview = false } })
mf.open(root .. '/doc')
local count = 0
for _, window in ipairs(api.nvim_list_wins()) do
  if vim.bo[api.nvim_win_get_buf(window)].filetype == 'minifiles' then
    check(window, 'Real MiniFiles columns inherit border')
    count = count + 1
  end
end
assert(count > 0, 'Real MiniFiles opened')
mf.close()
local blink = require('blink.cmp.config')
blink.merge_with(dofile(root .. '/lua/plugins/blink.lua')[1].opts)
-- The installed public configuration accepts inherited custom Unicode borders.
assert(blink.completion.menu.winhighlight:find('FloatBorder:UserFloatMenuBorder', 1, true))
assert(blink.completion.documentation.window.winhighlight:find('FloatBorder:FloatBorder', 1, true))
assert(require('merge_preview.layout').help_config(api.nvim_create_buf(false, true)).border == style.border)
print('PASS: global/native/LSP/MiniFiles borders, Blink config, theme reloads and surface-specific backgrounds.')
