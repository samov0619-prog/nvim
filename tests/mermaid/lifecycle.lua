-- Regression tests use an in-memory request filesystem and no subprocesses/tty.
local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')
vim.opt.rtp:prepend(repo)
local root = repo .. '/scripts/mermaid-preview'
vim.g.mermaid_preview_data_dir = vim.fn.tempname()
local api = vim.api
vim.o.columns, vim.o.lines = 120, 40
vim.env.KITTY_WINDOW_ID, vim.env.TMUX = '1', nil
package.loaded['config.mermaid-preview.source'] = { source = function() return 'flowchart LR\nA --> B\n' end }
local files, jobs = {}, {}
local readfile = vim.fn.readfile
vim.fn.filereadable = function(file) return files[file] and 1 or 0 end
vim.fn.readfile = function(file, ...)
  if files[file] then return { files[file] } end
  return readfile(file, ...)
end
vim.fn.writefile = function(lines, file) files[file] = table.concat(lines, '\n'); return 0 end
vim.fn.delete = function(file) files[file] = nil; return 0 end
vim.system = function(cmd, _, callback)
  jobs[#jobs + 1] = { input = cmd[3], palette = cmd[5], callback = callback }
  return { kill = function() end }
end
local function load()
  local viewer = dofile(repo .. '/lua/config/mermaid-preview.lua')
  viewer.cell_size = function() return { width = 8, height = 16 } end
  viewer.send = function() end
  return viewer
end
local old = load()
old.toggle()
old.close()
local new = load()
new.toggle()
assert(jobs[1].input ~= jobs[2].input, 'Reload must not reuse a request path')
jobs[1].callback({ code = 143, stderr = 'cancelled' })
vim.wait(20, function() return false end)
assert(not files[jobs[1].input] and not files[jobs[1].palette])
assert(files[jobs[2].input] and files[jobs[2].palette], 'Old callback must not delete active inputs')
new.close()
jobs[2].callback({ code = 143, stderr = 'cancelled' })
vim.wait(20, function() return false end)
io.stdout:write('PASS: unique request files survive reload and stale callback cleanup\n')

local viewer = load()
local palette = viewer.palette()
local key = viewer.lookup_key('source', palette)
for _, file in ipairs({ 'pipeline.json', 'package-lock.json', 'render.mjs', 'palette.mjs', 'browser.mjs' }) do
  vim.fn.readfile = function(name, ...)
    local lines = readfile(name, ...)
    if name == root .. '/' .. file then lines[#lines + 1] = 'changed' end
    return lines
  end
  assert(viewer.lookup_key('source', palette) ~= key, 'Pipeline change must invalidate lookup: ' .. file)
end
vim.fn.readfile = readfile
assert(viewer.lookup_key('source', palette) == key)
io.stdout:write('PASS: pipeline, lockfile and renderer edits invalidate fast cache without Node\n')

local png = '/virtual/diagram.png'
local lookup = viewer.data_dir .. '/lookup/' .. viewer.lookup_key('flowchart LR\nA --> B\n', palette) .. '.json'
files[lookup], files[png] = vim.json.encode({ output = png }), 'PNG'
local open = io.open
io.open = function(file, ...)
  if file ~= png then return open(file, ...) end
  return { read = function() return '\137PNG\r\n\26\n\0\0\0\13IHDR\0\0\0\100\0\0\0\100' end,
    close = function() end }
end
vim.fn.readfile = function(file, ...)
  if files[file] then return { files[file] } end
  return readfile(file, ...)
end
local baseline = #api.nvim_list_wins()
local notifications = {}
vim.notify = function(message) notifications[#notifications + 1] = message end
viewer.toggle()
vim.wait(20, function() return false end)
local win = api.nvim_get_current_win()
local groups = api.nvim_get_autocmds({ event = 'VimLeavePre' })
local group = groups[#groups].group
viewer.send = function() error('simulated terminal failure') end
assert(pcall(viewer.close), 'Terminal errors must not escape close')
assert(not api.nvim_win_is_valid(win) and #api.nvim_list_wins() == baseline)
assert(not pcall(api.nvim_get_autocmds, { group = group }), 'Autocmd group must be removed')
assert(#notifications == 1 and notifications[1]:find('terminal failure', 1, true))
assert(pcall(viewer.close), 'Repeated close must be harmless')
vim.wait(20, function() return false end)
io.stdout:write('PASS: terminal failure still closes the float and removes its autocmd group\n')
vim.cmd('qa!')
