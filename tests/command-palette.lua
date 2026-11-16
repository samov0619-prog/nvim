-- Run: nvim -n --headless -u NONE -i NONE -l tests/command-palette.lua
-- Exercise FzfLua's actual serialization/pipe before real fzf filtering.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/fzf-lua')
local palette = require('config.command-palette')
local fzf = require('fzf-lua')
local core = require('fzf-lua.core')
local utils = require('fzf-lua.utils')
local actions = require('fzf-lua.actions')
vim.o.termguicolors = true
vim.api.nvim_set_hl(0, 'PaletteEx', { fg = '#112233' })
vim.api.nvim_set_hl(0, 'PaletteGlobal', { fg = '#445566' })
vim.api.nvim_set_hl(0, 'PaletteBuffer', { fg = '#778899' })
fzf.setup({ hls = { cmd_ex = 'PaletteEx', cmd_global = 'PaletteGlobal', cmd_buf = 'PaletteBuffer' } })

local executed = false
vim.api.nvim_create_user_command('PaletteUnmapped', function() executed = true end, {
  desc = 'Calibrate spectroscope\nwithout a key mapping',
})
vim.api.nvim_create_user_command('PaletteScoped', function() end, { desc = 'Global description' })
vim.api.nvim_buf_create_user_command(0, 'PaletteScoped', function() end, { desc = 'Buffer description' })
vim.api.nvim_create_user_command('PaletteDefinition', 'echo "DefinitionOnlyNeedle"', {})
local descriptions = palette.descriptions()
assert(descriptions.PaletteUnmapped == 'Calibrate spectroscope without a key mapping', 'Normalize multiline descriptions')
assert(descriptions.PaletteScoped == 'Buffer description', 'Buffer command overrides the global description')
assert(descriptions.edit == 'edit a file', 'Read builtin descriptions from the installed help')
assert(descriptions.all:find('argument list', 1, true), 'Include wrapped builtin descriptions')
assert(vim.fn.maparg('PaletteUnmapped', 'n') == '', 'Fixture command has no keymap')

local original_wrap = core.fzf_wrap
local rows, options
core.fzf_wrap = function(command, opts)
  local result
  local process = vim.system({ 'sh', '-c', command }, {
    text = true, env = { FZF_LUA_SERVER = vim.g.fzf_lua_server },
  }, function(output) result = output end)
  if not vim.wait(10000, function() return result ~= nil end, 10) then
    process:kill(9)
    error('FzfLua content pipeline timed out')
  end
  assert(result.code == 0, 'FzfLua content pipeline failed: ' .. vim.inspect(result))
  rows, options = vim.split(result.stdout, '\n', { trimempty = true }), opts
end
palette.open()
core.fzf_wrap = original_wrap
assert(#rows > 100, 'Palette must include builtin commands, not just fixtures')
assert(options.fzf_opts['--nth'] == false and options.fzf_opts['--with-nth'] == false,
  'Descriptions must participate in search and display')
local function row_for(name)
  for _, row in ipairs(rows) do
    if utils.strip_ansi_coloring(row):match('^[^\t]+') == name then return row end
  end
  error('Missing command row: ' .. name)
end
for name, group in pairs({ edit = 'PaletteEx', PaletteUnmapped = 'PaletteGlobal', PaletteScoped = 'PaletteBuffer' }) do
  local row = row_for(name)
  assert(row:find('\27[', 1, true), 'Emit ANSI highlighting for ' .. name)
  assert(row:sub(1, #utils.ansi_from_hl(group, name)) == utils.ansi_from_hl(group, name),
    'Respect the configured command-type highlight group for ' .. name)
end
assert(options.preview({ row_for('PaletteUnmapped') }) == vim.inspect(vim.api.nvim_get_commands({}).PaletteUnmapped),
  'Preview the full command registration, including callback and argument properties')
assert(options.preview({ row_for('PaletteScoped') }) == vim.inspect(vim.api.nvim_buf_get_commands(0, {}).PaletteScoped),
  'Prefer the complete buffer-local registration in the preview')
assert(options.preview({ row_for('spellundo') }) == vim.inspect('remove good or bad word'),
  'Keep the builtin description preview')
assert(options.preview({}) == '', 'Empty preview selection is safe')
local function filter(query)
  local result = vim.system({ 'fzf', '--ansi', '--filter', query }, {
    text = true, stdin = table.concat(rows, '\n'),
  }):wait()
  assert(result.code == 0, 'fzf could not match ' .. query .. ': ' .. (result.stderr or ''))
  return utils.strip_ansi_coloring(result.stdout)
end
assert(filter('spectroscope'):find('PaletteUnmapped', 1, true), 'Find an unmapped command by description')
assert(filter('PaletteUnmapped'):find('Calibrate spectroscope', 1, true), 'Find a command by name and display its description')
assert(filter("'edit 'a 'file"):find('edit\tedit a file', 1, true), 'Search builtin descriptions too')
assert(filter('remove good or bad word'):find('spellundo\tremove good or bad word', 1, true),
  'Find the builtin description shown in the reported preview')
assert(filter('DefinitionOnlyNeedle'):find('PaletteDefinition', 1, true),
  'Search the definition when the command has no desc')

local original_action, prefilled = actions.ex_run
actions.ex_run = function(selected) prefilled = selected[1] end
actions.act({ 'enter' }, options)
assert(not prefilled, 'Empty picker selection must do nothing')
actions.act({ 'enter', row_for('PaletteUnmapped') }, options)
actions.ex_run = original_action
assert(prefilled == 'PaletteUnmapped ', 'Pass only the command name to the native prefill action')
assert(not executed, 'Selecting a command must not execute it')

vim.api.nvim_create_user_command('PaletteLate', function() end, { desc = 'Registered after first picker' })
assert(palette.descriptions().PaletteLate == 'Registered after first picker', 'Refresh command registrations')
vim.cmd.enew()
assert(palette.descriptions().PaletteScoped == 'Global description', 'Refresh current-buffer scope')
print('PASS: actual FzfLua pipeline, command-type colors, complete previews, real fzf filtering, scope, and safe prefill')
