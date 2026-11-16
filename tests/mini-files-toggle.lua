-- Run: nvim -n --headless -u NONE -i NONE -l tests/mini-files-toggle.lua
-- Real MiniFiles API; virtual Gitsigns buffer name is a fixture, no Git process needed.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp:prepend(root)
for _, plugin in ipairs({ 'mini.files', 'mini.icons' }) do
  vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/' .. plugin)
end
vim.o.hidden, vim.o.swapfile = true, false
vim.o.lines, vim.o.columns = 50, 160
local task = '/tmp/opencode/mini-files-toggle-' .. vim.fn.getpid()
vim.fn.mkdir(task .. '/nested', 'p', 448)
vim.fn.writefile({ 'source' }, task .. '/nested/file.lua')
vim.cmd.cd(vim.fn.fnameescape(task))
local spec = dofile(root .. '/lua/plugins/mini-files.lua')[1]
-- -u NONE omits netrw's normal startup group, which MiniFiles clears when taking over.
vim.api.nvim_create_augroup('FileExplorer', { clear = true })
spec.config()
local mf = require('mini.files')
local toggle = spec.keys[1][2]
local api = vim.api
local source = api.nvim_get_current_win()
local progress = task .. '/progress.json'
vim.fn.writefile({ vim.json.encode({ format = 'nvim-keymap-progress', version = 1, mappings = {
  m0 = { key = '␣do', description = 'Diff', category = 'Обычный diff', modes = { 'N' }, status = 'unknown' },
} }) }, progress)
local trainer = require('config.keymap-trainer')
trainer.setup({ path = progress, keymap = false })
trainer.show()
local function panel_windows()
  local count = 0
  for _, win in ipairs(api.nvim_list_wins()) do
    if vim.bo[api.nvim_win_get_buf(win)].filetype:match('^keymap%-trainer') then count = count + 1 end
  end
  return count
end

local ok, err = xpcall(function()
  local function check(name, expected_anchor, buftype)
    vim.cmd.enew()
    if name then api.nvim_buf_set_name(0, name) end
    vim.bo.buftype = buftype or ''
    vim.bo.modifiable = buftype ~= 'nowrite'
    -- A revision comparison has two diff windows. A lone diff is auto-disabled by 'closeoff'.
    local comparison
    if buftype == 'nowrite' then
      comparison = api.nvim_open_win(api.nvim_create_buf(false, true), false, { split = 'right', win = source })
      vim.wo[comparison].diff = true
    end
    vim.wo.diff = buftype == 'nowrite'
    local was_diff = vim.wo.diff
    trainer.refresh()
    toggle()
    assert(vim.wait(1000, function() return mf.get_explorer_state() ~= nil end, 10), 'Explorer opens')
    assert(vim.wait(1000, function() return panel_windows() == 0 end, 10), 'Help does not overlay file explorer')
    assert(mf.get_explorer_state().anchor == expected_anchor, 'Expected anchor for ' .. tostring(name))
    toggle()
    assert(mf.get_explorer_state() == nil, 'Second invocation closes explorer')
    assert(api.nvim_get_current_win() == source, 'Closing explorer returns to source')
    assert(vim.wo.diff == was_diff, 'Help and explorer must preserve the source diff state')
    if buftype ~= 'nofile' then
      assert(vim.wait(1000, function() return panel_windows() == 2 end, 10),
        'Help returns in ordinary and virtual diff buffers: ' .. vim.inspect({ name = name, context = trainer.context(),
          diff = vim.wo.diff, buftype = vim.bo.buftype, windows = api.nvim_list_wins(), error = vim.v.errmsg }))
    end
    if comparison then api.nvim_win_close(comparison, true) end
  end
  check(task .. '/nested/file.lua', task .. '/nested')
  check('gitsigns://' .. task .. '/.git//HEAD~:flake.nix', task, 'nowrite')
  check(nil, task, 'nofile')
  check(task .. '/nested/not-saved.lua', task)
  assert(vim.v.errmsg == '', 'No invalid-path, readonly-buffer or last-window error: ' .. vim.v.errmsg)
  print('PASS: real MiniFiles toggle + trainer lifecycle for filesystem, virtual diff, unnamed and unsaved buffers.')
end, debug.traceback)
mf.close()
trainer.hide()
vim.cmd.cd(vim.fn.fnameescape(root))
vim.fn.delete(task .. '/nested/file.lua')
vim.fn.delete(progress)
vim.fn.delete(task .. '/nested', 'd')
vim.fn.delete(task, 'd')
if not ok then error(err) end
