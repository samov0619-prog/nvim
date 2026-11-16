-- Run: nvim -n --headless -u NONE -i NONE -l tests/keymap-trainer-dap.lua
-- Real DAP View open/close/REPL, without starting an adapter or building the project.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp:prepend(root)
for _, plugin in ipairs({ 'nvim-dap', 'nvim-dap-view' }) do
  vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/' .. plugin)
end
local api = vim.api
vim.o.lines, vim.o.columns = 50, 160
vim.bo.filetype = 'javascript'
local source, source_buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
local task = '/tmp/opencode/keymap-trainer-dap-' .. vim.fn.getpid()
vim.fn.mkdir(task, 'p', 448)
local path = task .. '/progress.json'
local mappings = {}
for index, key in ipairs({ 'F5', 'F2', 'F7', 'F10', 'F11', 'F12', '␣Db', '␣DB' }) do
  mappings['m' .. index] = { key = key, description = key, category = 'Отладка', modes = { 'N' }, status = 'unknown' }
end
vim.fn.writefile({ vim.json.encode({ format = 'nvim-keymap-progress', version = 1, mappings = mappings }) }, path)
local trainer = require('config.keymap-trainer')
local function panel()
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    local buf = api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == 'keymap-trainer' then return api.nvim_buf_get_lines(buf, 0, -1, false) end
  end
end
local function count(expected, label)
  assert(vim.wait(1000, function()
    local ctx = trainer.context()
    return ctx and #trainer.items(ctx) == expected
  end, 10), label)
end
local dv
local ok, err = xpcall(function()
  trainer.setup({ path = path, keymap = false })
  trainer.refresh()
  assert(panel() == nil, 'Starts hidden, including in supported DAP languages')
  count(0, 'Unloaded DAP does not create launch hints')
  dofile(root .. '/lua/plugins/nvim-dap.lua')[1].config()
  dv = require('dap-view')
  dv.setup({ auto_toggle = false })
  trainer.show()
  count(1, 'Closed DAP View shows only F5 for configured languages')
  assert(panel()[2] == 'F5  F5', 'Actual rendered launch hint')
  vim.bo.filetype = 'nix'
  trainer.refresh()
  count(0, 'No launch hint for an unconfigured filetype')
  vim.bo.filetype = 'javascript'
  require('dap').repl.open()
  api.nvim_set_current_win(source)
  count(1, 'Standalone REPL with DAP View loaded still permits only F5')
  assert(not trainer.context().dap_view, 'Standalone REPL is not DAP View')
  trainer.refresh()
  assert(panel()[2] == 'F5  F5' and #panel() == 2, 'Standalone REPL renders launch-only hints')
  require('dap').repl.close()
  dv.open()
  api.nvim_set_current_win(source)
  count(8, 'Visible DAP View enables all debugger hints from the source')
  assert(trainer.context().dap_view, 'Context detects the real visible pane')
  assert(vim.wait(1000, function() return panel() and #panel() == 9 end, 10), 'All DAP hints render with one heading')
  local view_win
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if vim.bo[api.nvim_win_get_buf(win)].filetype == 'dap-view' then view_win = win end
  end
  api.nvim_set_current_win(assert(view_win))
  trainer.refresh()
  assert(panel() == nil, 'Does not cover DAP View itself')
  api.nvim_set_current_win(source)
  dv.show_view('repl')
  assert(vim.bo[api.nvim_win_get_buf(view_win)].filetype == 'dap-repl', 'Real integrated REPL replaces the view buffer')
  count(8, 'DAP View REPL counts as an open view too')
  trainer.refresh()
  assert(panel() and #panel() == 9, 'Integrated REPL keeps the internal hints rendered in the source')
  vim.cmd.tabnew()
  vim.bo.filetype = 'javascript'
  local other_source = api.nvim_get_current_win()
  require('dap').repl.open()
  api.nvim_set_current_win(other_source)
  count(1, 'DAP View in another tab does not enable internal hints')
  assert(vim.wait(1000, function() return panel() and #panel() == 2 end, 10), 'Launch-only panel is visible in the current tab')
  -- dap.repl.close() closes the shared REPL in every tab, including DAP View.
  -- Closing this tab should remove only its standalone window.
  vim.cmd.tabclose()
  api.nvim_set_current_win(source)
  count(8, 'Returning to the DAP View tab restores internal hints')
  assert(vim.wait(1000, function() return panel() and #panel() == 9 end, 10), 'Internal hints render in the restored tab')
  dv.close(true)
  count(1, 'Closing the real DAP View removes internal hints')
  assert(vim.wait(1000, function() return panel() and #panel() == 2 end, 10), 'Rendered list refreshes on close without an extra key')
  require('dap').repl.open()
  api.nvim_set_current_win(source)
  count(1, 'Standalone REPL after closing integrated REPL still permits only F5')
  assert(not trainer.context().dap_view, 'Closed DAP View leaves no REPL ownership behind')
  require('dap').repl.close()
  trainer.hide()
  dv.open()
  api.nvim_set_current_win(source)
  trainer.refresh()
  assert(panel() == nil, 'Opening DAP View does not override explicit hiding')
  assert(api.nvim_buf_get_lines(source_buf, 0, -1, false)[1] == '', 'Source remains unchanged')
  assert(vim.v.errmsg == '', 'No DAP UI or trainer errors: ' .. vim.v.errmsg)
  print('PASS: real DAP View open/close, integrated/standalone REPL, current-tab rendering, launch-only fallback and hidden preference.')
end, debug.traceback)
trainer.hide()
if dv then dv.close(true) end
vim.fn.delete(path)
vim.fn.delete(task, 'd')
if not ok then error(err) end
