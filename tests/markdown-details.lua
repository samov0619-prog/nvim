-- Run: nvim -n --headless -u NONE -i NONE -l tests/markdown-details.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp:prepend(root)
local lazy = vim.fn.stdpath('data') .. '/lazy/'
for _, name in ipairs({ 'nvim-treesitter', 'nvim-ufo', 'promise-async', 'render-markdown.nvim', 'nvim-web-devicons' }) do
  vim.opt.rtp:append(lazy .. name)
end
vim.opt.rtp:append(lazy .. 'nvim-treesitter/runtime')
vim.o.swapfile, vim.o.hidden = false, true
vim.o.lines, vim.o.columns = 60, 120
local notices = {}
vim.notify = function(message, level) notices[#notices + 1] = { message, level } end
local function wait(predicate, label)
  assert(vim.wait(5000, predicate, 10), label .. '\n' .. vim.inspect(notices))
end
local fixture = {
  '# Notes', '',
  '<details>', '<summary>Краткое <b>резюме</b></summary>', '',
  '**Markdown body**', '', '</details>', '',
  '<details open="false">', '<summary>Open is a boolean attribute</summary>', '',
  '<details>', '<summary>Nested</summary>', '', 'Nested body', '', '</details>', '',
  'Visible body', '', '</details>', '',
  '<details><summary>Adjacent</summary>', '', 'Adjacent body', '', '</details>', '',
  '```html', '<details>', '<summary>Example, not a spoiler</summary>', '', 'Example body', '</details>', '```', '',
  '<details>', '', 'No summary', '', '</details>', '',
  '<details>', '<summary>Incomplete</summary>', '',
}
local path = '/tmp/opencode/markdown-details-' .. vim.fn.getpid() .. '.md'
vim.fn.writefile(fixture, path)
vim.cmd('filetype on')
dofile(root .. '/lua/plugins/render-markdown-nvim.lua')[1].config()
vim.cmd('runtime plugin/render-markdown.lua')
dofile(root .. '/lua/plugins/nvim-ufo.lua')[1].config()
vim.cmd.edit(vim.fn.fnameescape(path))
local buf = vim.api.nvim_get_current_buf()
local details = require('config.markdown-details')
local function row(line)
  for i, value in ipairs(fixture) do if value == line then return i end end
  error('Missing fixture: ' .. line)
end
local closed, opened, nested, adjacent = 3, 10, 13, 24
local missing = row('No summary') - 2
local items = details.get(buf)
assert(items[closed - 1].summary == 'Краткое резюме')
assert(items[opened - 1].open and not items[nested - 1].open)
assert(items[missing - 1].summary == 'Details')
assert(not items[row('<summary>Example, not a spoiler</summary>') - 2], 'Ignore HTML fenced examples')
assert(not items[row('<summary>Incomplete</summary>') - 2], 'Ignore unclosed details')
wait(function() return vim.fn.foldclosed(closed) == closed end, 'Close ordinary details on first open')
assert(vim.fn.foldclosed(opened) == -1, 'Keep details open even with open="false"')
assert(vim.fn.foldclosed(nested) == nested, 'Close nested details independently')
assert(vim.fn.foldclosed(adjacent) == adjacent, 'Close adjacent details')
assert(vim.fn.foldclosed(1) == -1, 'Do not close the Markdown heading')
vim.cmd('redraw!')
assert(vim.fn.foldtextresult(closed):find('▸ Краткое резюме', 1, true), 'UFO renders the configured summary label')
local native = require('ufo').getFolds(buf, 'treesitter')
local original = vim.deepcopy(native)
local ranges = details.folds(buf)
assert(vim.deep_equal(native, original), 'Do not mutate builtin ranges')
local seen = {}
for _, range in ipairs(ranges) do
  local key = range.startLine .. ':' .. range.endLine
  assert(not seen[key], 'No duplicate ranges')
  seen[key] = true
  if range.startLine == closed - 1 and range.endLine == items[closed - 1].last then
    assert(range.kind == 'details')
  end
end
local captured
local function fallback(chunks) captured = chunks; return chunks end
details.fold_text({}, closed, items[closed - 1].last + 1, 80, function(s) return s end, { bufnr = buf }, fallback)
assert(captured[1][1] == '▸ Краткое резюме', 'Closed label uses summary, not details tag')
local ordinary = { { '# Notes', 'Title' } }
details.fold_text(ordinary, 1, #fixture, 80, function(s) return s end, { bufnr = buf }, fallback)
assert(captured == ordinary, 'Keep the existing handler for other folds')
vim.api.nvim_win_set_cursor(0, { closed, 0 })
vim.cmd('normal! za')
assert(vim.fn.foldclosed(closed) == -1, 'za opens details')
-- UFO records manual fold changes during screen redraw, as in an interactive UI.
vim.cmd('redraw!')
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local md = require('render-markdown')
local ns = vim.api.nvim_get_namespaces()['render-markdown.nvim']
local function marks() return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true }) end
md.render({ buf = buf })
wait(function()
  for _, mark in ipairs(marks()) do
    if mark[2] == closed - 1 and mark[4].conceal == '' then return true end
  end
  return false
end, 'Conceal details tag')
local summary_hidden = false
for _, mark in ipairs(marks()) do
  if mark[2] == closed and mark[4].conceal == '' then summary_hidden = true end
end
assert(summary_hidden, 'Conceal summary tag')
vim.api.nvim_buf_set_lines(buf, 5, 6, false, { 'Edited **Markdown body**' })
require('ufo').applyFolds(buf, details.folds(buf))
assert(vim.fn.foldclosed(closed) == -1, 'Editing/recomputation keeps a manually opened fold open')
vim.api.nvim_buf_set_lines(buf, closed, closed + 1, false, { '<summary>Новое резюме</summary>' })
assert(details.get(buf)[closed - 1].summary == 'Новое резюме', 'Invalidate cached summaries after edits')
vim.api.nvim_win_set_cursor(0, { closed, 0 })
vim.cmd('normal! zc')
assert(vim.fn.foldclosed(closed) == closed, 'zc closes details')
vim.cmd('redraw!')
require('ufo').applyFolds(buf, details.folds(buf))
assert(vim.fn.foldclosed(closed) == closed, 'Recomputation keeps a manually closed fold closed')
vim.cmd('normal! zo')
assert(vim.fn.foldclosed(closed) == -1, 'zo opens details')
vim.cmd('redraw!')
vim.fn.maparg('zR', 'n', false, true).callback()
assert(vim.fn.foldclosed(nested) == -1, 'zR opens nested details too')
vim.cmd('redraw!')
require('ufo').applyFolds(buf, details.folds(buf))
assert(vim.fn.foldclosed(nested) == -1, 'Recomputation does not reclose details after zR')
vim.wait(150, function() return false end) -- Let the renderer's native debounce expire.
md.disable()
wait(function() return #marks() == 0 end, 'Disabling rendering reveals source')
md.enable()
vim.bo.modified = false
vim.cmd('bwipeout!')
-- A spoiler without a preceding heading can share its exact range with a section.
vim.cmd.enew()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '<details>', '<summary>Standalone</summary>', '', 'Body', '', '</details>' })
vim.bo.filetype = 'markdown'
wait(function() return vim.fn.foldclosed(1) == 1 end, 'Standalone details close on cold attachment')
assert(details.get(vim.api.nvim_get_current_buf())[0].summary == 'Standalone')
vim.fn.delete(path)
for _, notice in ipairs(notices) do
  assert(not notice[2] or notice[2] < vim.log.levels.WARN, vim.inspect(notices))
end
print('PASS: Markdown details parsing, rendering, initial state and fold lifecycle')
vim.cmd('qa!')
