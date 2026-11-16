-- Passive, contextual help. Native window scrolling; progress stays in the browser-owned JSON.
local M = {}
local api = vim.api
local ns = api.nvim_create_namespace('keymap-trainer')
local state = { entries = {}, enabled = false, view = 'learn', pending = false }
local order = { 'Общее', 'Поиск', 'Git', 'Diff', 'Правки', 'LSP', 'Ввод', 'Логи', 'Отладка' }
local groups = {
  ['Файлы, окна и вкладки'] = 'Общее', ['Диагностика'] = 'Общее', ['Прочее'] = 'Общее',
  ['Редактирование'] = 'Правки', ['Комментарии'] = 'Правки', ['Surround'] = 'Правки',
  ['Командная строка'] = 'Ввод', ['Completion и сниппеты'] = 'Ввод',
  ['Обычный diff'] = 'Diff', ['Логирование'] = 'Логи',
}
local logging_types = { javascript = true, javascriptreact = true, typescript = true,
  typescriptreact = true, vue = true, astro = true, lua = true }
local diff_keys = { ['[c'] = true, [']c'] = true, ['␣dc'] = true,
  ['␣dg'] = true, ['␣dp'] = true, ['␣do'] = true }

local function valid(win) return win and api.nvim_win_is_valid(win) end
local function own(win) return win == state.list_win or win == state.controls_win end

local function dap_view_open()
  -- The documented window marker survives switching to the integrated REPL.
  -- Loading dap-view alone does not make a standalone dap-repl its pane.
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    local ft = vim.bo[api.nvim_win_get_buf(win)].filetype
    if ft == 'dap-view' or (ft == 'dap-repl' and vim.w[win].dapview_win) then return true end
  end
  return false
end

local function highlights()
  -- Inherit the float's text colour; no search-match background or theme accent.
  api.nvim_set_hl(0, 'KeymapTrainerActive', { default = true, bold = true, underline = true })
  local surface = api.nvim_get_hl(0, { name = 'NormalFloat', link = false })
  local comment = api.nvim_get_hl(0, { name = 'Comment', link = false })
  api.nvim_set_hl(0, 'KeymapTrainerBorder', {
    fg = comment.fg or surface.fg, bg = surface.bg,
    ctermfg = comment.ctermfg or surface.ctermfg, ctermbg = surface.ctermbg,
  })
end

local function category(entry)
  local key = entry.key
  if key:match('^␣g') or key:match('^␣h') or key == ']c' or key == '[c' then return 'Git' end
  if key == '␣fp' then return 'Общее' end
  if key == '␣z' or key == '␣Z' or key:match('^␣f') then return 'Поиск' end
  if key == 'zg' or key == '␣cf' or key == '␣cx' then return 'Правки' end
  return groups[entry.category] or entry.category
end

local function mode()
  local raw = api.nvim_get_mode().mode
  if raw:match('^[vV\22sS\19]') then return 'V' end
  if raw:match('^[iR]') then return 'I' end
  if raw:sub(1, 1) == 'c' then return 'C' end
  if raw:sub(1, 1) == 't' then return 'T' end
  return 'N'
end

function M.context()
  local win = api.nvim_get_current_win()
  if own(win) then return state.source end
  local buf = api.nvim_win_get_buf(win)
  local bt, ft = vim.bo[buf].buftype, vim.bo[buf].filetype
  local diff = vim.wo[win].diff
  if api.nvim_win_get_config(win).relative ~= '' or (bt ~= '' and bt ~= 'terminal' and not diff) then return end
  local name = api.nvim_buf_get_name(buf)
  local git = bt == '' and vim.fs.root(name ~= '' and name or vim.fn.getcwd(), '.git') ~= nil
  local ctx = { win = win, buf = buf, mode = mode(), ft = ft, terminal = bt == 'terminal',
    git = git, diff = diff, lsp = #vim.lsp.get_clients({ bufnr = buf }) > 0, modifiable = vim.bo[buf].modifiable,
    hunks = vim.b[buf].gitsigns_head ~= nil, dap_view = dap_view_open() }
  ctx.key = table.concat({ buf, ctx.mode, ft, tostring(git), tostring(ctx.diff), tostring(ctx.lsp),
    tostring(ctx.hunks), tostring(ctx.modifiable), tostring(ctx.dap_view) }, ':')
  return ctx
end

local function available(entry, ctx)
  if not vim.tbl_contains(entry.modes, ctx.mode) then return false end
  local key, group = entry.key, entry.group
  if key == '␣rd' then return false end -- Mermaid preview already provides its own hints.
  if ctx.diff then return diff_keys[key] == true end
  if not ctx.modifiable and (group == 'Правки' or group == 'Логи' or group == 'Отладка') then return false end
  if ctx.terminal and ctx.mode ~= 'C' then return key:match('^Alt%-') ~= nil or key == '␣tc' end
  if group == 'LSP' and not ctx.lsp then return false end
  if key == ']c' or key == '[c' then return ctx.hunks or ctx.diff end
  if group == 'Git' and not ctx.git then return false end
  if (key:match('^␣h') or key == '␣gb') and not ctx.hunks then return false end
  if group == 'Diff' and key ~= '␣do' and not ctx.diff then return false end
  if group == 'Логи' and not logging_types[ctx.ft] then return false end
  if group == 'Отладка' then
    local dap = package.loaded.dap
    if not dap then return false end
    if ctx.dap_view then return true end
    local configurations = dap.configurations[ctx.ft]
    return key == 'F5' and ((configurations ~= nil and #configurations > 0) or dap.session() ~= nil)
  end
  return true
end

function M.items(ctx, view)
  local result = {}
  for _, entry in ipairs(state.entries) do
    if (entry.status == 'known') == ((view or state.view) == 'known') and available(entry, ctx) then
      -- Navigation belongs to Git normally; never change the cached catalogue for a diff view.
      result[#result + 1] = ctx.diff and vim.tbl_extend('force', entry, { group = 'Diff' }) or entry
    end
  end
  table.sort(result, function(a, b)
    if a.motion ~= b.motion then return not a.motion end
    return a.index < b.index
  end)
  return result
end

local function load()
  local ok, data = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(state.path), '\n'))
  end)
  if not ok then return false, 'Не удалось прочитать ' .. state.path end
  if type(data) ~= 'table' or data.format ~= 'nvim-keymap-progress' or data.version ~= 1
    or type(data.mappings) ~= 'table' then return false, 'Неизвестный формат JSON' end
  local entries = {}
  for id, entry in pairs(data.mappings) do
    if type(id) ~= 'string' or type(entry) ~= 'table' or type(entry.key) ~= 'string'
      or type(entry.description) ~= 'string' or type(entry.category) ~= 'string'
      or not vim.islist(entry.modes) or #entry.modes == 0
      or not vim.tbl_contains({ 'unknown', 'learning', 'known' }, entry.status) then
      return false, 'Некорректная запись JSON: ' .. tostring(id)
    end
    for _, value in ipairs(entry.modes) do
      if not vim.tbl_contains({ 'N', 'V', 'I', 'C', 'T' }, value) then return false, 'Некорректный режим: ' .. id end
    end
    entry.id, entry.index = id, tonumber(id:match('^m(%d+)$'))
    if not entry.index then return false, 'Неизвестный ID: ' .. id end
    entry.group = category(entry)
    if not vim.tbl_contains(order, entry.group) then return false, 'Неизвестная категория: ' .. entry.category end
    entry.motion = entry.key:find('движение', 1, true) ~= nil or entry.key == '␣y'
    entries[#entries + 1] = entry
  end
  if #entries == 0 then return false, 'В JSON нет команд' end
  state.entries, state.error = entries, nil
  return true
end

local function close()
  for _, field in ipairs({ 'controls_win', 'list_win' }) do
    local win = state[field]
    state[field] = nil
    if valid(win) then api.nvim_win_close(win, true) end
  end
end

function M.back()
  if not own(api.nvim_get_current_win()) then return end
  local ctx = state.source
  if not ctx or not valid(ctx.win) or api.nvim_win_get_buf(ctx.win) ~= ctx.buf then return end
  -- Native double/triple clicks may start a selection in the help buffer.
  if mode() == 'V' then
    vim.cmd.normal({ api.nvim_replace_termcodes('<Esc>', true, false, true), bang = true })
  end
  if api.nvim_get_current_win() ~= ctx.win then api.nvim_set_current_win(ctx.win) end
  if ctx.mode == 'V' and mode() ~= 'V' then vim.cmd('normal! gv') end
  if ctx.mode == 'I' and mode() ~= 'I' then vim.cmd.startinsert() end
end

local function buffer(kind)
  local field = kind .. '_buf'
  if state[field] and api.nvim_buf_is_valid(state[field]) then return state[field] end
  local buf = api.nvim_create_buf(false, true)
  state[field] = buf
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'keymap-trainer' .. (kind == 'list' and '' or '-' .. kind)
  vim.keymap.set({ 'n', 'x', 'i' }, 'q', M.back, { buffer = buf, silent = true, desc = 'return to editor' })
  local function release()
    local mouse = vim.fn.getmousepos()
    if kind ~= 'list' and mouse.winid == api.nvim_get_current_win() then
      M.activate(kind, mouse.line, vim.fn.virtcol({ mouse.line, mouse.column }))
    else
      M.back()
    end
  end
  for _, key in ipairs({ '<LeftRelease>', '<2-LeftRelease>', '<3-LeftRelease>', '<4-LeftRelease>' }) do
    vim.keymap.set({ 'n', 'x', 'i', 's' }, key, release, { buffer = buf, silent = true })
  end
  if kind ~= 'list' then
    vim.keymap.set('n', '<CR>', function()
      local cursor = api.nvim_win_get_cursor(0)
      M.activate(kind, cursor[1], vim.fn.virtcol('.'))
    end, { buffer = buf, silent = true })
  end
  return buf
end

local function text(buf, lines)
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function window(kind, config)
  config.relative = 'editor'
  local field = kind .. '_win'
  if valid(state[field]) then
    api.nvim_win_set_config(state[field], config)
    return state[field]
  end
  config.style = 'minimal'
  -- Thin block glyphs place the outline at the outer cell edges (font/terminal dependent).
  -- Omit the touching edges to keep controls and list joined without a gap.
  if kind == 'controls' then config.border = { '🭽', '▔', '🭾', '▕', '', '', '', '▏' } end
  if kind == 'list' then config.border = { '', '', '', '▕', '🭿', '▁', '🭼', '▏' } end
  -- Wheel scrolling stays native. Click release returns focus; keyboard navigation skips all floats.
  config.focusable, config.mouse, config.zindex = false, true, 40
  local win = api.nvim_open_win(buffer(kind), false, config)
  state[field] = win
  for option, value in pairs({ wrap = kind == 'list', linebreak = true, breakindent = true,
    scrolloff = 0, sidescrolloff = 0, spell = false, foldenable = false, cursorline = false,
    diff = false, scrollbind = false, cursorbind = false,
    winblend = 0, winhighlight = 'Normal:NormalFloat,FloatBorder:KeymapTrainerBorder,FloatTitle:NormalFloat' }) do
    api.nvim_set_option_value(option, value, { win = win })
  end
  return win
end

function M.scroll(amount)
  if not valid(state.list_win) then return end
  api.nvim_win_call(state.list_win, function()
    local key = api.nvim_replace_termcodes(amount > 0 and '<C-e>' or '<C-y>', true, false, true)
    vim.cmd.normal({ math.abs(amount) .. key, bang = true })
  end)
end

function M.activate(kind, row, column)
  for _, button in ipairs((state.buttons or {})[kind] or {}) do
    if row == button.row and column >= button.first and column <= button.last then
      M.back()
      button.action()
      return
    end
  end
  M.back()
end

function M.refresh()
  if not state.path or state.stopped then return end
  -- :tabclose destroys floats before TabLeave. Resolve external component
  -- closes after that lifecycle finishes, so closing a tab is not a user hide.
  if state.closed_tab then
    if api.nvim_tabpage_is_valid(state.closed_tab) then state.enabled = false end
    state.closed_tab = nil
  end
  for _, field in ipairs({ 'controls_win', 'list_win' }) do
    local win = state[field]
    if valid(win) and api.nvim_win_get_tabpage(win) ~= api.nvim_get_current_tabpage() then
      close()
      break
    end
  end
  if own(api.nvim_get_current_win()) then return end
  local ctx = M.context()
  if not ctx then close(); return end
  state.source = ctx
  if not state.enabled or vim.o.columns < 48 or vim.o.lines < 18 then close(); return end
  local base_width = math.min(52, math.max(32, math.floor(vim.o.columns * 0.34)))
  local width = math.min(math.floor(base_width * 1.4 + 0.5), vim.o.columns - 6)
  local items, content, marks = M.items(ctx), {}, {}
  for _, name in ipairs(order) do
    local heading = false
    for _, entry in ipairs(items) do
      if entry.group == name then
        if not heading then
          content[#content + 1] = name
          marks[#marks + 1] = { row = #content - 1, length = #name, group = 'KeymapTrainerActive' }
          heading = true
        end
        content[#content + 1] = entry.key .. '  ' .. entry.description:gsub(';.*$', '')
        marks[#marks + 1] = { row = #content - 1, length = #entry.key, group = 'Identifier' }
      end
    end
  end
  if #content == 0 then content = { state.error or 'Нет команд для этого режима и фильтра.' } end
  local controls, buttons = { '' }, {}
  local function button(label, action, selected)
    local label_width = vim.fn.strdisplaywidth(label)
    local first = vim.fn.strdisplaywidth(controls[1]) + 1
    controls[1] = controls[1] .. label .. ' '
    buttons[#buttons + 1] = { row = 1, first = first, last = first + label_width - 1,
      action = action, selected = selected }
  end
  button(state.view == 'learn' and '[Учить ⇄]' or '[Помню ⇄]',
    function() M.view(state.view == 'learn' and 'known' or 'learn') end, true)
  button('[×]', M.hide)
  state.buttons = { controls = buttons }
  -- Reserve top inset/border/controls, bottom border, status/command area and inset.
  local max_height = vim.o.lines - vim.o.cmdheight - 5
  if max_height < 1 then close(); return end
  local col = vim.o.columns - width - 4
  window('controls', { row = 1, col = col, width = width, height = 1,
    title = ' Клавиши · ' .. ctx.mode .. ' ', title_pos = 'left' })
  text(state.controls_buf, controls)
  api.nvim_buf_clear_namespace(state.controls_buf, ns, 0, -1)
  for _, item in ipairs(buttons) do
    local start = vim.fn.byteidx(controls[1], item.first - 1)
    local finish = vim.fn.byteidx(controls[1], item.last)
    api.nvim_buf_set_extmark(state.controls_buf, ns, 0, start, {
      end_col = finish == -1 and #controls[1] or finish, hl_group = item.selected and 'KeymapTrainerActive' or 'Comment',
    })
  end
  local signature = table.concat({ ctx.key, state.view, table.concat(content, '\n') }, '\0')
  local changed = signature ~= state.signature or not valid(state.list_win)
  local height = valid(state.list_win) and math.min(max_height, api.nvim_win_get_height(state.list_win)) or max_height
  window('list', { row = 3, col = col, width = width, height = height })
  if changed then
    text(state.list_buf, content)
    api.nvim_buf_clear_namespace(state.list_buf, ns, 0, -1)
    for _, mark in ipairs(marks) do
      api.nvim_buf_set_extmark(state.list_buf, ns, mark.row, 0, { end_col = mark.length, hl_group = mark.group })
    end
  end
  -- Count actual wrapped screen rows using the public Neovim API, not string length estimates.
  local rows = api.nvim_win_text_height(state.list_win, { start_row = 0, end_row = #content - 1 }).all
  api.nvim_win_set_height(state.list_win, math.min(max_height, math.max(1, rows)))
  if changed then
    api.nvim_win_set_cursor(state.list_win, { 1, 0 })
    api.nvim_win_call(state.list_win, function() vim.fn.winrestview({ topline = 1, skipcol = 0 }) end)
  end
  state.signature = signature
end

local function schedule()
  if state.pending then return end
  state.pending = true
  vim.schedule(function() state.pending = false; M.refresh() end)
end

function M.hide()
  M.back()
  state.closed_tab = nil
  state.enabled = false
  close()
end

function M.show()
  state.closed_tab = nil
  state.enabled = true
  M.back()
  M.refresh()
end

function M.toggle()
  if state.enabled then M.hide() else M.show() end
end

function M.view(view)
  assert(view == 'learn' or view == 'known', 'Unknown trainer view')
  M.back()
  state.view = view
  M.refresh()
end

function M.reload()
  local ok, err = load()
  if not ok then
    if #state.entries == 0 then state.error = err end
    vim.notify('Keymap trainer: ' .. err, vim.log.levels.WARN)
  end
  schedule()
  return ok
end

function M.setup(opts)
  opts = opts or {}
  close()
  highlights()
  state.path = opts.path or vim.fn.expand('~/scratch/mappings-tbl/mapping-progress.json')
  state.stopped, state.enabled, state.signature, state.closed_tab = false, false, nil, nil
  M.reload()
  api.nvim_create_user_command('KeymapTrainer', function(args)
    local actions = { toggle = M.toggle, show = M.show, hide = M.hide, reload = M.reload,
      learn = function() M.view('learn') end, known = function() M.view('known') end,
      up = function() M.scroll(-3) end, down = function() M.scroll(3) end }
    local action = actions[args.args ~= '' and args.args or 'toggle']
    if not action then vim.notify('Use: KeymapTrainer toggle|show|hide|reload|learn|known|up|down', vim.log.levels.WARN); return end
    action()
  end, { nargs = '?', desc = 'keymap learning panel', complete = function()
    return { 'toggle', 'show', 'hide', 'reload', 'learn', 'known', 'up', 'down' }
  end })
  if opts.keymap ~= false then
    for _, map_mode in ipairs({ 'n', 'x' }) do
      if vim.fn.maparg('<leader>?', map_mode) == '' then
        vim.keymap.set(map_mode, '<leader>?', M.toggle, { silent = true, desc = 'keymap learning panel' })
      end
    end
  end
  local group = api.nvim_create_augroup('KeymapTrainer', { clear = true })
  -- Clearing our handles in close() keeps WinClosed from treating ordinary tab
  -- switches as explicit user hides. :tabclose is resolved by refresh().
  api.nvim_create_autocmd('TabLeave', { group = group, callback = close })
  api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter', 'WinEnter', 'TabEnter', 'FileType', 'ModeChanged', 'LspAttach', 'LspDetach',
    'VimResized', 'DirChanged', 'OptionSet' }, { group = group,
    callback = function(ev)
      if ev.event ~= 'OptionSet' or ev.match == 'diff' then schedule() end
    end })
  api.nvim_create_autocmd('User', { group = group, pattern = { 'VeryLazy', 'GitSignsUpdate' }, callback = schedule })
  api.nvim_create_autocmd('ColorScheme', { group = group, callback = function() highlights(); schedule() end })
  api.nvim_create_autocmd('WinClosed', { group = group, callback = function(ev)
    if own(tonumber(ev.match)) then
      state.closed_tab = api.nvim_win_get_tabpage(tonumber(ev.match))
    end
    schedule()
  end })
  api.nvim_create_autocmd('FocusGained', { group = group, callback = M.reload })
  api.nvim_create_autocmd('BufWritePost', { group = group, callback = function(ev)
    if api.nvim_buf_get_name(ev.buf) == state.path then M.reload() end
  end })
  api.nvim_create_autocmd('VimLeavePre', { group = group, callback = function() state.stopped = true end })
  schedule()
end

return M
