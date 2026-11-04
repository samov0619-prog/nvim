-- Run: nvim -n --headless -u NONE -i NONE -l tests/markdown-viewport.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp:prepend(root)
local lazy = vim.fn.stdpath('data') .. '/lazy/'
for _, name in ipairs({ 'nvim-treesitter', 'nvim-ufo', 'promise-async', 'render-markdown.nvim', 'nvim-web-devicons' }) do
  vim.opt.rtp:append(lazy .. name)
end
vim.opt.rtp:append(lazy .. 'nvim-treesitter/runtime')
vim.o.swapfile, vim.o.hidden = false, true
vim.o.lines, vim.o.columns = 42, 120
local notices = {}
vim.notify = function(message, level) notices[#notices + 1] = { message, level } end
local function wait(predicate, label)
  assert(vim.wait(5000, predicate, 10), label .. '\n' .. vim.inspect(notices))
end
local lines, headings, tables = { '# Notes', '' }, {}, {}
for i = 1, 12 do
  headings[i] = #lines
  vim.list_extend(lines, {
    '## [ ] ' .. i .. '. Note', '', '<details>', '<summary>Summary ' .. i .. '</summary>', '',
  })
  for j = 1, 18 do lines[#lines + 1] = 'Body ' .. j end
  vim.list_extend(lines, { '', '</details>', '', '| Name | Value |', '| ---- | ----- |', '| A | 1 |', '| B | 2 |', '' })
  tables[i] = #lines - 2
end
local path = '/tmp/opencode/markdown-viewport-' .. vim.fn.getpid() .. '.md'
vim.fn.writefile(lines, path)
vim.cmd('filetype on')
dofile(root .. '/lua/plugins/render-markdown-nvim.lua')[1].config()
vim.cmd('runtime plugin/render-markdown.lua')
vim.cmd.edit(vim.fn.fnameescape(path))
local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
local ns = vim.api.nvim_get_namespaces()['render-markdown.nvim']
local function decorated(row)
  return #vim.api.nvim_buf_get_extmarks(buf, ns, { row, 0 }, { row, -1 }, {}) > 0
end
wait(function() return decorated(headings[1]) end, 'Initial heading decoration')
vim.cmd('redraw!')
local before = vim.fn.line('w$')
-- Deliberately let the renderer run before UFO applies its first fold ranges.
-- The final view is much larger in buffer lines, despite an unchanged topline.
dofile(root .. '/lua/plugins/nvim-ufo.lua')[1].config()
wait(function() return vim.fn.foldclosed(5) == 5 end, 'Initial UFO folds')
vim.cmd('redraw!')
local after = vim.fn.line('w$')
assert(after > before, 'Folding must expose new buffer rows at the bottom')
local target
for i, row in ipairs(headings) do
  if row > before + 10 and tables[i] + 1 < after then target = i end
end
assert(target, 'Fixture must expose a previously unrendered heading')
wait(function() return decorated(headings[target]) end,
  ('Newly visible heading %d must render without input (bottom %d -> %d)'):format(target, before, after))
wait(function() return decorated(tables[target]) end, 'Newly visible tables render too')
-- Neither a no-op redraw nor native rendering may cause an unbounded render loop.
local renders = 0
local md = require('render-markdown')
local render = md.render
md.render = function(...) renders = renders + 1; return render(...) end
for _ = 1, 4 do vim.cmd('redraw!'); vim.wait(150, function() return false end) end
assert(renders == 0, 'An unchanged viewport must not request another render')
md.render = render
assert(vim.api.nvim_win_get_cursor(win)[1] == 1, 'Recovery must not move the cursor')
-- Manual folding changes the visible buffer range without moving the cursor too.
vim.fn.maparg('zR', 'n', false, true).callback()
vim.cmd('redraw!')
vim.wait(150, function() return false end)
vim.fn.maparg('zM', 'n', false, true).callback()
-- zM also closes headings; reopen only those to expose the compact note list.
for _, heading in ipairs(headings) do
  vim.cmd((heading + 1) .. 'foldopen')
end
vim.api.nvim_win_set_cursor(win, { 1, 0 })
vim.cmd('redraw!')
wait(function() return decorated(headings[target]) end, 'Manual folding refreshes the view without another key')
-- Rendering stays disabled even if the viewport observer sees a resize.
md.disable()
wait(function() return #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) == 0 end, 'Disable clears decorations')
local width = vim.api.nvim_win_get_width(win)
vim.cmd('vsplit')
assert(vim.api.nvim_win_get_width(win) < width, 'The test must actually resize the Markdown window')
vim.cmd('redraw!')
vim.wait(200, function() return false end)
assert(not md.get() and #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) == 0,
  'Viewport recovery must respect disabled rendering')
md.enable()
vim.cmd('redraw!')
wait(function() return decorated(headings[target]) end, 'Re-enable restores visible decorations')
-- Closing a window with a pending redraw must not leave a stale window request.
vim.cmd('redraw!')
vim.cmd('close')
vim.cmd('redraw!')
vim.wait(200, function() return false end)
vim.bo.modified = false
vim.fn.delete(path)
for _, notice in ipairs(notices) do
  assert(not notice[2] or notice[2] < vim.log.levels.WARN, vim.inspect(notices))
end
print('PASS: Post-fold viewport renders headings and tables without input')
vim.cmd('qa!')
