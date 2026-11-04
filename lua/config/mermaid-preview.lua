-- Official Mermaid rendered on demand, displayed locally through Kitty.
local M = {}
local api = vim.api
local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')
local root = repo .. '/scripts/mermaid-preview'
local data = vim.g.mermaid_preview_data_dir or (vim.fn.stdpath('data') .. '/mermaid-preview')
M.data_dir = data
M.source = require('config.mermaid-preview.source').source
local current
local serial = 0
local kitty = require('config.mermaid-preview.kitty')
M.cell_size, M.send, M.geometry = kitty.cell_size, kitty.send, kitty.geometry
local graphics = kitty.graphics
local pipeline = vim.json.decode(table.concat(vim.fn.readfile(root .. '/pipeline.json'), '\n'))

local function clear(state, release)
  if state.image then
    M.send(graphics('a=d,d=' .. (release and 'I' or 'i') .. ',i=' .. state.id .. ',q=2'))
  end
end

function M.palette()
  local mode = vim.o.background
  local function color(group, field, fallback)
    local hl = api.nvim_get_hl(0, { name = group, link = false, create = false })
    return hl[field] and ('#%06x'):format(hl[field]) or fallback
  end
  local bg = color('NormalFloat', 'bg', color('Normal', 'bg', mode == 'dark' and '#1e1e2e' or '#ffffff'))
  local fg = color('NormalFloat', 'fg', color('Normal', 'fg', mode == 'dark' and '#cdd6f4' or '#222222'))
  local accent = color('Identifier', 'fg', fg)
  local function blend(a, b, amount)
    local rgb = {}
    for i = 2, 6, 2 do
      rgb[#rgb + 1] = ('%02x'):format(math.floor(tonumber(a:sub(i, i + 1), 16) * (1 - amount)
        + tonumber(b:sub(i, i + 1), 16) * amount + 0.5))
    end
    return '#' .. table.concat(rgb)
  end
  -- Wire order: mode, background, text, primary, border, line, secondary, tertiary, accent.
  return { mode, bg, fg, blend(bg, accent, 0.12), blend(bg, accent, 0.65), fg,
    blend(bg, color('Statement', 'fg', accent), 0.12), blend(bg, color('Type', 'fg', accent), 0.12), accent }
end

function M.palette_key(palette)
  return vim.fn.sha256(table.concat(palette, '\n'))
end

function M.pipeline_key()
  local hashes = {}
  for _, file in ipairs({ 'pipeline.json', 'package-lock.json', 'render.mjs', 'palette.mjs', 'browser.mjs' }) do
    hashes[#hashes + 1] = vim.fn.sha256(table.concat(vim.fn.readfile(root .. '/' .. file, 'b'), '\n'))
  end
  return vim.fn.sha256(table.concat(hashes, '\n'))
end

function M.lookup_key(source, palette)
  return vim.fn.sha256(M.pipeline_key() .. '\n' .. M.palette_key(palette) .. '\n' .. source)
end

local function layout()
  local w, h = math.max(1, math.floor(vim.o.columns * 0.9)), math.max(1, math.floor((vim.o.lines - 3) * 0.85))
  return { relative = 'editor', row = math.max(0, math.floor((vim.o.lines - h - 2) / 2)),
    col = math.max(0, math.floor((vim.o.columns - w - 2) / 2)), width = w, height = h }
end

local function text(state, message)
  vim.bo[state.buf].modifiable = true
  api.nvim_buf_set_lines(state.buf, 0, -1, false, vim.split(message, '\n'))
  vim.bo[state.buf].modifiable = false
end

local function draw(state)
  if current ~= state or not state.image or not api.nvim_win_is_valid(state.win) then return end
  if api.nvim_get_current_win() ~= state.win then return end
  local width, height = api.nvim_win_get_width(state.win), api.nvim_win_get_height(state.win)
  local g = M.geometry(state.iw, state.ih, width, height, state.cell.width, state.cell.height,
    state.zoom, state.x, state.y)
  state.x, state.y, state.geometry = g.x, g.y, g
  clear(state, false)
  api.nvim_win_set_config(state.win, { title = (' Mermaid · fit ×%.2f · %s '):format(state.zoom, state.status) })
  vim.cmd('redraw')
  local pos = api.nvim_win_get_position(state.win)
  M.send(('\27[s\27[%d;%dH'):format(pos[1] + 2 + g.top, pos[2] + 2 + g.left)
    .. graphics(('a=p,i=%d,x=%d,y=%d,w=%d,h=%d,c=%d,r=%d,C=1,q=2,z=1'):format(
      state.id, g.x, g.y, g.w, g.h, g.c, g.r)) .. '\27[u')
end

local function png_size(file)
  local f = assert(io.open(file, 'rb'))
  local header = f:read(24)
  f:close()
  assert(header and #header == 24 and header:sub(1, 8) == '\137PNG\r\n\26\n', 'Invalid PNG')
  local function integer(i)
    local a, b, c, d = header:byte(i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
  end
  return integer(17), integer(21)
end

local function display(state, file, status)
  local ok, iw, ih = pcall(png_size, file)
  if not ok then text(state, tostring(iw)); return end
  if iw < 1 or ih < 1 or iw * ih > pipeline.size * pipeline.size then
    text(state, 'PNG exceeds the pixel limit or has invalid dimensions'); return
  end
  state.iw, state.ih, state.image, state.status = iw, ih, file, status
  text(state, '')
  -- Lower-case t=f reads a regular file: Kitty must not delete our disk cache.
  M.send(graphics('a=t,t=f,f=100,i=' .. state.id .. ',q=2', vim.base64.encode(file)))
  vim.schedule(function() draw(state) end)
end

local function render(state)
  if current ~= state then return end
  state.request = state.request + 1
  local request = state.request
  if state.job then state.job:kill(15); state.job = nil end
  clear(state, true)
  state.image, state.geometry = nil, nil
  local palette = M.palette()
  state.theme_key = M.palette_key(palette)
  local lookup = data .. '/lookup/' .. M.lookup_key(state.source, palette) .. '.json'
  if vim.fn.filereadable(lookup) == 1 then
    local ok, result = pcall(vim.json.decode, table.concat(vim.fn.readfile(lookup), '\n'))
    if ok and type(result) == 'table' and type(result.output) == 'string'
      and vim.fn.filereadable(result.output) == 1 then display(state, result.output, 'cache'); return end
  end
  api.nvim_win_set_config(state.win, { title = ' Mermaid · rendering ' .. palette[1] .. ' theme ' })
  text(state, 'Rendering official Mermaid for the current Neovim palette…\nChromium exits before display.\nq / Esc: cancel')
  -- Neovim tempname is unique across module reloads and image-ID wraparound.
  local prefix = vim.fn.tempname()
  local input, theme_file = prefix .. '.mmd', prefix .. '.json'
  vim.fn.writefile(vim.split(state.source, '\n'), input, 'b')
  vim.fn.writefile({ vim.json.encode(palette) }, theme_file)
  local chromium = vim.env.MERMAID_CHROMIUM or vim.fn.exepath('chromium')
  if chromium == '' then chromium = data .. '/chromium/bin/chromium' end
  local ok, job = pcall(vim.system, { 'node', root .. '/render.mjs', input, '--theme-file', theme_file },
    { text = true, timeout = 45000, env = { MERMAID_DATA_DIR = data, MERMAID_CHROMIUM = chromium } }, function(result)
      vim.schedule(function()
        vim.fn.delete(input)
        vim.fn.delete(theme_file)
        if current ~= state or request ~= state.request then return end
        state.job = nil
        if result.code ~= 0 then text(state, (result.stderr or 'Renderer failed'):sub(-4000)); return end
        local parsed, data = pcall(vim.json.decode, vim.trim(result.stdout))
        if not parsed then text(state, result.stdout); return end
        display(state, data.output, ('%.1fs · browser stopped'):format(data.ms / 1000))
      end)
    end)
  if ok then state.job = job else
    vim.fn.delete(input)
    vim.fn.delete(theme_file)
    text(state, 'Cannot start renderer: ' .. tostring(job))
  end
end

function M.close()
  local state = current
  if not state then return end
  current = nil
  local errors = {}
  local function cleanup(fn)
    local ok, err = pcall(fn)
    if not ok then errors[#errors + 1] = tostring(err) end
  end
  if state.job then cleanup(function() state.job:kill(15) end) end
  cleanup(function() clear(state, true) end)
  if api.nvim_win_is_valid(state.win) then cleanup(function() api.nvim_win_close(state.win, true) end) end
  if state.group then cleanup(function() api.nvim_del_augroup_by_id(state.group) end) end
  if #errors > 0 then
    vim.notify('Mermaid cleanup: ' .. table.concat(errors, '; '), vim.log.levels.WARN)
  end
end

function M.toggle()
  if current then M.close(); return end
  if not vim.env.KITTY_WINDOW_ID or vim.env.TMUX then
    vim.notify('Mermaid preview requires local Kitty without tmux', vim.log.levels.ERROR)
    return
  end
  local source, err = M.source(api.nvim_get_current_buf(), api.nvim_win_get_cursor(0)[1] - 1)
  if not source or #source > 256 * 1024 then
    vim.notify(err or 'Source exceeds 256 KiB', vim.log.levels.ERROR); return
  end
  local cell, cell_error = M.cell_size()
  if not cell then
    vim.notify('Cannot read terminal pixel size: ' .. cell_error, vim.log.levels.ERROR); return
  end
  serial = serial + 1
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden, vim.bo[buf].swapfile, vim.bo[buf].filetype = 'wipe', false, 'mermaid_preview'
  local win = api.nvim_open_win(buf, true, vim.tbl_extend('force', layout(), {
    style = 'minimal', border = 'rounded', title = ' Mermaid · rendering ',
    footer = ' hjkl: pan · +/-: zoom · 0: fit · q/Esc: close ', footer_pos = 'center',
  }))
  vim.wo[win].wrap, vim.wo[win].winblend = false, 0
  local state = { win = win, buf = buf, cell = cell, zoom = 1, x = 0, y = 0, source = source, request = 0,
    id = 23000000 + (vim.fn.getpid() % 100000) * 100 + (serial % 100) }
  current = state
  local function map(key, callback)
    vim.keymap.set('n', key, callback, { buffer = buf, silent = true, nowait = true })
  end
  for _, key in ipairs({ 'q', '<Esc>', '<leader>rd' }) do map(key, M.close) end
  for key, delta in pairs({ h = { -1, 0 }, l = { 1, 0 }, k = { 0, -1 }, j = { 0, 1 },
    ['<Left>'] = { -1, 0 }, ['<Right>'] = { 1, 0 }, ['<Up>'] = { 0, -1 }, ['<Down>'] = { 0, 1 } }) do
    map(key, function()
      if not state.geometry then return end
      local n = math.max(1, vim.v.count1)
      state.x = state.x + delta[1] * 4 * state.cell.width / state.geometry.scale * n
      state.y = state.y + delta[2] * 2 * state.cell.height / state.geometry.scale * n
      draw(state)
    end)
  end
  local function zoom(factor)
    if not state.geometry then return end
    local old = state.geometry
    state.zoom = math.max(1, math.min(8, state.zoom * factor))
    local new = M.geometry(state.iw, state.ih, api.nvim_win_get_width(win), api.nvim_win_get_height(win),
      state.cell.width, state.cell.height, state.zoom, 0, 0)
    state.x, state.y = old.x + (old.w - new.w) / 2, old.y + (old.h - new.h) / 2
    draw(state)
  end
  map('+', function() zoom(1.25) end)
  map('=', function() zoom(1.25) end)
  map('-', function() zoom(1 / 1.25) end)
  map('0', function() state.zoom, state.x, state.y = 1, 0, 0; draw(state) end)
  state.group = api.nvim_create_augroup('MermaidPreview' .. state.id, { clear = true })
  api.nvim_create_autocmd('WinClosed', { group = state.group, pattern = tostring(win), once = true,
    callback = function() if current == state then M.close() end end })
  api.nvim_create_autocmd('VimLeavePre', { group = state.group, callback = M.close })
  api.nvim_create_autocmd('WinLeave', { group = state.group, callback = function()
    if current == state then clear(state, false) end
  end })
  api.nvim_create_autocmd({ 'WinEnter', 'CmdlineLeave' }, { group = state.group,
    callback = function() vim.schedule(function() draw(state) end) end })
  api.nvim_create_autocmd('CmdlineEnter', { group = state.group, callback = function() clear(state, false) end })
  api.nvim_create_autocmd('VimResized', { group = state.group, callback = function()
    clear(state, false)
    state.cell = M.cell_size() or state.cell
    api.nvim_win_set_config(win, layout())
    vim.schedule(function() draw(state) end)
  end })
  local function theme_changed()
    state.theme_event = (state.theme_event or 0) + 1
    local event = state.theme_event
    vim.defer_fn(function()
      if current == state and state.theme_event == event and M.palette_key(M.palette()) ~= state.theme_key then
        render(state)
      end
    end, 100)
  end
  api.nvim_create_autocmd('ColorScheme', { group = state.group, callback = theme_changed })
  api.nvim_create_autocmd('OptionSet', { group = state.group, pattern = 'background', callback = theme_changed })
  render(state)
end

return M
