-- Run: nvim -n --headless -u NONE -i NONE -l tests/comment.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp:prepend(root)
for _, plugin in ipairs({ 'Comment.nvim', 'nvim-ts-context-commentstring' }) do
  vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/' .. plugin)
end
vim.o.swapfile = false
local notices = {}
vim.notify = function(message) notices[#notices + 1] = tostring(message) end
dofile(root .. '/lua/plugins/Comment.lua')[1].config()
vim.cmd('runtime plugin/Comment.lua')
local comment = require('Comment.api')
local function open(name, lines, filetype)
  vim.cmd.enew({ bang = true })
  vim.api.nvim_buf_set_name(0, '/tmp/opencode/comment-fixture/' .. name)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.filetype = filetype or vim.filetype.match({ buf = 0 })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
end
local function check(expected)
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), expected), vim.inspect({
    lines = vim.api.nvim_buf_get_lines(0, 0, -1, false), notices = notices,
  }))
end

for _, name in ipairs({ '.env', '.env.local', '.env.production', '.env.example', 'app.env' }) do
  open(name, { 'APP_MODE=development', 'PORT=3000' })
  assert(vim.bo.filetype == 'env', name .. ' must be detected as env')
  vim.cmd('normal gcc')
  check({ '# APP_MODE=development', 'PORT=3000' })
  vim.cmd('normal gcc')
  check({ 'APP_MODE=development', 'PORT=3000' })
  comment.toggle.linewise.count(2)
  check({ '# APP_MODE=development', '# PORT=3000' })
  comment.toggle.linewise.count(2)
  check({ 'APP_MODE=development', 'PORT=3000' })
end
assert(#notices == 0, vim.inspect(notices))
print('PASS: gcc and line ranges toggle comments in .env and its variants without a parser')

comment.toggle.blockwise.current()
check({ 'APP_MODE=development', 'PORT=3000' })
assert(#notices == 1 and notices[1]:find("env doesn't support block comments!", 1, true), vim.inspect(notices))
notices = {}
print('PASS: unsupported .env block comments report a useful warning instead of nil')

-- Unknown filetypes must still reach the native commentstring fallback.
open('custom.conf', { 'sample' }, 'comment_fixture')
vim.bo.commentstring = '# %s'
comment.toggle.linewise.current()
check({ '# sample' })
comment.toggle.linewise.current()
check({ 'sample' })
assert(#notices == 0, vim.inspect(notices))
print('PASS: native commentstring fallback works without a parser')

-- Existing parsers must keep the normal Treesitter calculation path.
open('sample.lua', { 'local value = 1' })
assert(vim.treesitter.get_parser(0), 'Install the Lua parser before running this test')
vim.treesitter.get_parser(0):parse()
local ft = require('Comment.ft')
local linewise = require('Comment.utils').ctype.linewise
assert(ft.calculate({ ctype = linewise, range = { srow = 1, scol = 0, erow = 1, ecol = 15 } }) == ft.get('lua', linewise))
comment.toggle.linewise.current()
check({ '-- local value = 1' })
comment.toggle.linewise.current()
check({ 'local value = 1' })
assert(#notices == 0, vim.inspect(notices))
print('PASS: Treesitter-backed Lua comments still toggle normally')
vim.cmd('qa!')
