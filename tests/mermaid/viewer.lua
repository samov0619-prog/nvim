local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')
vim.opt.rtp:prepend(root)
vim.env.KITTY_WINDOW_ID, vim.env.TMUX = 'test', nil
vim.g.mermaid_preview_data_dir = vim.fn.tempname()
local viewer = require('config.mermaid-preview')
for _, image in ipairs({ { 2400, 1000 }, { 800, 2400 }, { 1, 1 } }) do
  for _, zoom in ipairs({ 1, 2, 8 }) do
    for _, offset in ipairs({ -10000, 0, 10000 }) do
      local g = viewer.geometry(image[1], image[2], 90, 30, 8, 16, zoom, offset, offset)
      assert(g.x >= 0 and g.y >= 0 and g.x + g.w <= image[1] and g.y + g.h <= image[2])
      assert(g.c >= 1 and g.c + g.left <= 90 and g.r >= 1 and g.r + g.top <= 30)
    end
  end
end
print('PASS: bounded fit/zoom/crop geometry')
vim.o.columns, vim.o.lines = 120, 40
local api = vim.api
local sent = {}
viewer.send = function(bytes) sent[#sent + 1] = bytes end
local system = vim.system
vim.system = function(cmd) error('Cache hits must not spawn any helper: ' .. vim.inspect(cmd)) end
viewer.cell_size = function() return { width = 8, height = 16 } end
local source = api.nvim_get_current_buf()
vim.bo[source].filetype = 'mermaid'
api.nvim_buf_set_lines(source, 0, -1, false, vim.fn.readfile(root .. '/tests/mermaid/flowchart.mmd'))
local source_text = table.concat(api.nvim_buf_get_lines(source, 0, -1, false), '\n') .. '\n'
local png = dofile(root .. '/tests/mermaid/fixture.lua')()
local readable, readfile = vim.fn.filereadable, vim.fn.readfile
local lookups = {}
local function index()
  local key = viewer.data_dir .. '/lookup/' .. viewer.lookup_key(source_text, viewer.palette()) .. '.json'
  lookups[key] = { vim.json.encode({ output = png }) }
  return key
end
vim.fn.filereadable = function(file) if lookups[file] then return 1 end; return readable(file) end
vim.fn.readfile = function(file, ...) if lookups[file] then return lookups[file] end; return readfile(file, ...) end
local original_key = index()
local windows = #api.nvim_list_wins()
viewer.toggle()
vim.wait(30, function() return false end)
assert(#api.nvim_list_wins() == windows + 1)
assert(table.concat(sent):find('a=t,t=f,f=100', 1, true), 'Transfer PNG file from disk cache')
assert(table.concat(sent):find('a=p,i=', 1, true), 'Place image in float')
for _, key in ipairs({ '+', 'l', 'j', '-', '0' }) do
  local mapping = vim.fn.maparg(key, 'n', false, true)
  assert(mapping.buffer == 1 and mapping.callback)
  mapping.callback()
end
api.nvim_exec_autocmds('VimResized', {})
vim.wait(30, function() return false end)
viewer.close()
assert(#api.nvim_list_wins() == windows)
assert(table.concat(sent):find('a=d,d=I,i=', 1, true), 'Release only our image data on close')
viewer.toggle()
vim.wait(30, function() return false end)
api.nvim_win_close(0, true)
viewer.toggle()
assert(#api.nvim_list_wins() == windows + 1, 'External close releases state')
viewer.close()
-- The same source must select a different cache after a palette change, and
-- reopening/reloading must derive exactly the same palette identity.
local old_mode = vim.o.background
vim.o.background = 'light'
api.nvim_set_hl(0, 'NormalFloat', { bg = '#fafafa', fg = '#141414' })
local light_key = index()
assert(light_key ~= original_key)
viewer.toggle()
vim.wait(30, function() return false end)
assert(dofile(root .. '/lua/config/mermaid-preview.lua').lookup_key(source_text, viewer.palette())
  == viewer.lookup_key(source_text, viewer.palette()), 'Cache identity survives module reload')
local before = #sent
api.nvim_set_hl(0, 'NormalFloat', { bg = '#eeeeee', fg = '#141414' })
assert(index() ~= light_key, 'Changes within light mode must also invalidate cache')
api.nvim_exec_autocmds('ColorScheme', {})
assert(vim.wait(500, function() return #sent > before end), 'Open preview reacts to ColorScheme')
viewer.close()
-- Cache misses pass the actual palette; rapid changes cancel earlier work and
-- its late callback cannot replace the current theme's image or reopen a float.
local jobs = {}
vim.system = function(cmd, opts, callback)
  assert(cmd[1] == 'node' and cmd[4] == '--theme-file')
  local palette = vim.json.decode(table.concat(readfile(cmd[5]), '\n'))
  assert(palette[2] == viewer.palette()[2])
  local job = { callback = callback, killed = false }
  jobs[#jobs + 1] = job
  return { kill = function() job.killed = true end }
end
api.nvim_set_hl(0, 'NormalFloat', { bg = '#dddddd', fg = '#141414' })
viewer.toggle()
assert(#jobs == 1)
api.nvim_set_hl(0, 'NormalFloat', { bg = '#cccccc', fg = '#141414' })
api.nvim_exec_autocmds('ColorScheme', {})
assert(vim.wait(500, function() return #jobs == 2 end))
assert(jobs[1].killed)
before = #sent
jobs[1].callback({ code = 0, stdout = vim.json.encode({ output = png, ms = 10 }) })
vim.wait(30, function() return false end)
assert(#sent == before, 'Discard a stale palette render')
viewer.close()
assert(jobs[2].killed)
jobs[2].callback({ code = 0, stdout = vim.json.encode({ output = png, ms = 10 }) })
vim.wait(30, function() return false end)
assert(#api.nvim_list_wins() == windows)
-- Exercise cleanup after a displayed cache hit, not just while rendering.
index()
viewer.toggle()
vim.wait(30, function() return false end)
local notify, send = vim.notify, viewer.send
local warnings = {}
vim.notify = function(message) warnings[#warnings + 1] = message end
viewer.send = function() error('simulated tty failure') end
assert(pcall(viewer.close))
assert(#api.nvim_list_wins() == windows and #warnings == 1)
viewer.send, vim.notify = send, notify
vim.fn.filereadable, vim.fn.readfile = readable, readfile
vim.o.background = old_mode
vim.system = system
print('PASS: real PNG/cache hit, no Node spawn, mappings, resize, cleanup, external close')
print('PASS: palette cache identity, ColorScheme refresh, themed requests, cancellation, stale palette callbacks')
print('PASS: closing a displayed PNG still succeeds after terminal failure')
vim.cmd('qa!')
