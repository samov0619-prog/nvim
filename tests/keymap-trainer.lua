-- Run: nvim -n --headless -u NONE -i NONE -l tests/keymap-trainer.lua
-- Real embedded Neovim UI/mouse; fixture catalogue and simulated LSP/Gitsigns attachment flags.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local task = '/tmp/opencode/keymap-trainer-' .. vim.fn.getpid()
vim.fn.mkdir(task, 'p', 448)
local path = task .. '/progress.json'
local data = { format = 'nvim-keymap-progress', version = 1, mappings = {} }
local function entry(id, key, category, description, modes, status)
  data.mappings['m' .. id] = { key = key, category = category, description = description,
    modes = modes or { 'N' }, status = status or 'unknown' }
end
entry(0, '␣ff', 'Поиск', 'Поиск файлов', { 'N', 'V' })
entry(1, '␣gs', 'Согласованные назначения', 'Git status')
entry(2, '␣gO', 'Согласованные назначения', 'Diff с origin', nil, 'learning')
entry(3, '␣hp', 'Согласованные назначения', 'Hunk preview')
entry(4, '␣lgd', 'LSP', 'Определение')
entry(5, '␣dc', 'Обычный diff', 'Показ идентичных строк в diff')
entry(6, '␣cf', 'Согласованные назначения', 'Форматировать файл')
entry(7, 'ys + движение + обрамление', 'Surround', 'Обрамить диапазон')
entry(8, 'ds + обрамление', 'Surround', 'Удалить обрамление')
entry(9, 'yss + обрамление', 'Surround', 'Обрамить строку', nil, 'known')
entry(10, 'Tab', 'Командная строка', 'Дополнение команд', { 'C' })
entry(11, 'Tab', 'Completion и сниппеты', 'Дополнение текста', { 'I' })
entry(12, 'Alt-h', 'Файлы, окна и вкладки', 'Левое окно', { 'N', 'I', 'T' })
entry(13, 'glj', 'Логирование', 'Лог ниже', { 'N', 'V' })
entry(14, 'F5', 'Отладка', 'Отладка')
entry(15, '[c', 'Git', 'Предыдущий hunk')
entry(16, ']c', 'Git', 'Следующий hunk', nil, 'learning')
entry(17, '␣dg', 'Обычный diff', 'Забрать изменение из другого diff-окна')
entry(18, '␣dp', 'Обычный diff', 'Передать изменение в другое diff-окно', nil, 'known')
entry(19, '␣do', 'Обычный diff', 'Включить/выключить diff во всех окнах')
for i = 20, 60 do entry(i, 'fixture-' .. i, 'Редактирование', 'Тестовая строка ' .. i) end
for i = 61, 125 do entry(i, 'insert-' .. i, 'Completion и сниппеты', 'Подсказка ввода ' .. i, { 'I' }) end
entry(126, '␣rd', 'Прочее', 'Открыть/закрыть Mermaid-preview')
entry(127, '␣rd', 'Прочее', 'Открыть/закрыть Mermaid-preview', nil, 'known')
vim.fn.writefile({ vim.json.encode(data) }, path)
local stderr = {}
local child = vim.fn.jobstart({ vim.v.progpath, '--embed', '--headless', '-n', '-u', 'NONE', '-i', 'NONE' }, {
  rpc = true, on_stderr = function(_, lines) vim.list_extend(stderr, lines) end,
})
local function lua(code, ...)
  local ok, result = pcall(vim.rpcrequest, child, 'nvim_exec_lua', code, { ... })
  if not ok then
    local _, messages = pcall(vim.rpcrequest, child, 'nvim_exec2', 'messages', { output = true })
    error(vim.inspect(result) .. '\n' .. vim.inspect(messages) .. '\n' .. vim.inspect(vim.fn.jobwait({ child }, 100)) .. '\n' .. table.concat(stderr, '\n'))
  end
  return result
end
local function input(keys) vim.rpcrequest(child, 'nvim_input', keys) end
local function snapshot()
  return lua([[
    local result = { mode = vim.api.nvim_get_mode().mode, current = vim.api.nvim_get_current_win(),
      tab = vim.api.nvim_get_current_tabpage(), floats = {}, total = 0 }
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      local ft = vim.bo[buf].filetype
      if ft:match('^keymap%-trainer') then
        result.total = result.total + 1
        if vim.api.nvim_win_get_tabpage(win) == result.tab then
          result.floats[ft] = { win = win, buf = buf, lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
            position = vim.api.nvim_win_get_position(win), config = vim.api.nvim_win_get_config(win),
            view = vim.api.nvim_win_call(win, vim.fn.winsaveview) }
        end
      end
    end
    return result
  ]])
end
local function wait(predicate, label)
  assert(vim.wait(2000, function() return predicate(snapshot()) end, 10), label .. '\n' .. vim.inspect(snapshot()))
end
local function mouse(button, action, row, col)
  lua('vim.cmd("redraw!")')
  vim.rpcrequest(child, 'nvim_input_mouse', button, action, '', 0, row, col)
end
local function click(label)
  for _, name in ipairs({ 'keymap-trainer-controls' }) do
    local controls = assert(snapshot().floats[name])
    for row, line in ipairs(controls.lines) do
      local offset = line:find(label, 1, true)
      if offset then
        local column = vim.fn.strdisplaywidth(line:sub(1, offset - 1)) + 1
        local y, x = controls.position[1] + row, controls.position[2] + column
        mouse('left', 'press', y, x)
        mouse('left', 'release', y, x)
        return
      end
    end
  end
  error('Control not found: ' .. label)
end
local ok, err = xpcall(function()
  lua([[
    local root, path = ...
    vim.opt.rtp:prepend(root)
    vim.g.mapleader = ' '
    dofile(root .. '/lua/config/mapping.lua')
    vim.o.columns, vim.o.lines = 160, 50
    vim.o.mouse = 'a'
    vim.o.mousescroll = 'ver:3,hor:6'
    vim.api.nvim_buf_set_name(0, root .. '/tests/trainer-fixture.lua')
    vim.bo.filetype = 'lua'
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'one', 'two', 'three' })
    vim.g.source_win = vim.api.nvim_get_current_win()
    vim.g.source_buf = vim.api.nvim_get_current_buf()
    local notices = {}
    vim.g.notices = notices
    vim.notify = function(message)
      notices[#notices + 1] = message
      vim.g.notices = notices
    end
    require('config.keymap-trainer').setup({ path = path })
  ]], root, path)
  lua('require("config.keymap-trainer").refresh()')
  assert(vim.tbl_isempty(snapshot().floats), 'Panel starts hidden')
  input('<Space>?')
  wait(function(s) return s.floats['keymap-trainer'] and s.floats['keymap-trainer-controls'] end,
    'Space ? explicitly opens the panel')
  assert(vim.tbl_count(snapshot().floats) == 2, 'Joined controls and list, no category tabs')
  local source = lua('return vim.g.source_win')
  assert(snapshot().current == source, 'Opening must not enter either float')
  assert(snapshot().floats['keymap-trainer'].config.focusable == false, 'List excluded from window navigation')
  for _, window in pairs(snapshot().floats) do assert(not window.config.focusable, 'All trainer windows skip keyboard traversal') end
  assert(#snapshot().floats['keymap-trainer-controls'].lines == 1, 'Top bar is one line')
  assert(not table.concat(snapshot().floats['keymap-trainer-controls'].lines):find('[↑]', 1, true), 'No scroll buttons')
  assert(lua('return vim.api.nvim_get_hl(0, { name = "KeymapTrainerActive", link = false }).bg') == vim.NIL,
    'Active selection has no bright background')
  assert(vim.deep_equal(snapshot().floats['keymap-trainer-controls'].config.border,
    { '🭽', '▔', '🭾', '▕', '', '', '', '▏' }), 'Top border uses square thin-block outer-edge glyphs')
  assert(vim.deep_equal(snapshot().floats['keymap-trainer'].config.border,
    { '', '', '', '▕', '🭿', '▁', '🭼', '▏' }), 'Bottom border has no extra edge at the controls/list join')
  assert(lua([[
    local before = vim.api.nvim_get_hl(0, { name = 'FloatBorder', link = true })
    for _, bg in ipairs({ 0x353840, 0xf0f0f0 }) do
      vim.api.nvim_set_hl(0, 'NormalFloat', { fg = 0x888888, bg = bg })
      vim.api.nvim_set_hl(0, 'Comment', { fg = 0x777777, bg = 0x101010 })
      vim.api.nvim_exec_autocmds('ColorScheme', { pattern = 'trainer-test' })
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.bo[vim.api.nvim_win_get_buf(win)].filetype:match('^keymap%-trainer') then
          local mapped = {}
          for from, to in vim.wo[win].winhighlight:gmatch('([^,:]+):([^,]+)') do mapped[from] = to end
          for _, part in ipairs({ 'Normal', 'FloatBorder', 'FloatTitle' }) do
            assert(mapped[part] == (part == 'FloatBorder' and 'KeymapTrainerBorder' or 'NormalFloat'),
              'Only the outline uses a panel-local border highlight')
            assert(vim.api.nvim_get_hl(0, { name = mapped[part], link = false }).bg == bg,
              'No different-colour strip after dark/light theme changes')
          end
          assert(vim.api.nvim_get_hl(0, { name = mapped.FloatBorder, link = false }).fg == 0x777777,
            'Thin outline keeps the neutral Comment foreground without its different background')
          for _, char in ipairs(vim.api.nvim_win_get_config(win).border) do
            assert(char == '' or vim.fn.strdisplaywidth(char) == 1, 'Border glyphs occupy one cell')
          end
        end
      end
    end
    assert(vim.deep_equal(before, vim.api.nvim_get_hl(0, { name = 'FloatBorder', link = true })),
      'Other floats retain their global border highlight')
    return true
  ]]))
  local ctx = lua('return require("config.keymap-trainer").context()')
  assert(ctx.git and not ctx.lsp and not ctx.hunks and not ctx.diff)
  assert(lua([[
    local m = require('config.keymap-trainer')
    local ctx = m.context()
    local function contains(key, view)
      for _, item in ipairs(m.items(ctx, view)) do if item.key == key then return true end end
      return false
    end
    assert(contains('␣gO') and contains('␣gs'), 'Repository Git + learning status')
    assert(not contains('␣hp') and not contains('␣lgd') and not contains('␣dc'), 'Attachment/diff restrictions')
    assert(not contains('yss + обрамление') and contains('yss + обрамление', 'known'), 'Known view excludes both learning states')
    for _, ft in ipairs({ 'markdown', 'mermaid', 'lua' }) do
      ctx.ft = ft
      assert(not contains('␣rd') and not contains('␣rd', 'known'), 'Mermaid has its own hints in both progress views')
    end
    ctx.hunks, ctx.lsp = true, true
    assert(contains('␣hp') and contains('␣lgd') and contains('[c') and contains(']c'))
    ctx.diff = true
    local expected = { ['[c'] = true, [']c'] = true, ['␣dc'] = true, ['␣dg'] = true, ['␣do'] = true }
    local items = m.items(ctx)
    assert(#items == 5, 'Diff learning view contains only the five unlearned diff entries')
    for _, item in ipairs(items) do
      assert(expected[item.key] and item.group == 'Diff', 'Only diff actions in a single group')
    end
    local known = m.items(ctx, 'known')
    assert(#known == 1 and known[1].key == '␣dp' and known[1].group == 'Diff', 'Known diff entries stay separate')
    assert(not contains('␣hp') and not contains('␣lgd') and not contains('␣cf') and not contains('␣ff'))
    ctx.diff = false
    for _, item in ipairs(m.items(ctx)) do
      if item.key == '[c' or item.key == ']c' then assert(item.group == 'Git', 'No cached-category leakage') end
    end
    ctx.git, ctx.diff, ctx.hunks = false, false, false
    assert(not contains('␣gs') and not contains('␣gO'))
    ctx.diff = true
    assert(not contains('␣gs') and not contains('␣gO') and contains('␣dc'), 'Native diff does not imply a Git repository')
    ctx.mode = 'V'
    assert(#m.items(ctx) == 0, 'Diff-only filtering still respects modes, including empty states')
    ctx.diff = false
    assert(contains('␣ff') and not contains('␣lgd'))
    ctx.mode, ctx.terminal = 'T', true
    assert(contains('Alt-h') and not contains('␣ff'))
    ctx.mode = 'C'
    assert(contains('Tab'), 'Command-line completion applies inside terminal buffers too')
    return true
  ]]))
  print('PASS: mode, Git, LSP, hunk, diff, terminal and three-state selection contracts (attachment fixtures).')
  assert(lua([[
    for _, mode in ipairs({ 'n', 'x' }) do
      assert(vim.fn.maparg(' ?', mode) ~= '', 'Quick toggle is registered')
      for _, mapping in ipairs(vim.api.nvim_get_keymap(mode)) do
        local lhs = vim.api.nvim_replace_termcodes(mapping.lhs, true, false, true)
        assert(not (lhs:sub(1, 2) == ' ?' and #lhs > 2), 'Toggle must not have longer continuations')
      end
    end
    assert(vim.fn.maparg('<C-r>', 'c') == '', 'Keep native command-line register insertion')
    return true
  ]]))

  local list = snapshot().floats['keymap-trainer']
  assert(list.config.width == 73, 'Panel is 40% wider than the previous 52-column width, rounded')
  local all = table.concat(list.lines, '\n')
  assert(all:find('\nПоиск\n', 1, true) and all:find('\nGit\n', 1, true)
    and all:find('\nПравки\n', 1, true), 'All matching sections appear together')
  assert(all:find('Удалить обрамление', 1, true) < all:find('ys + движение', 1, true),
    'Motion commands follow simple actions within their section')
  assert(list.config.height == 44, 'Long list uses available screen height rather than the old 12-row cap')
  assert(list.config.row + list.config.height + 1 <= 48, 'Bottom border leaves status/command area and inset')
  local before = list.view.topline
  mouse('wheel', 'down', list.position[1] + 2, list.position[2] + 4)
  wait(function(s) return s.floats['keymap-trainer'].view.topline > before end, 'Wheel scrolls list')
  assert(snapshot().current == source, 'Wheel must not enter list')
  assert(snapshot().floats['keymap-trainer-controls'].view.topline == 1, 'Progress switch stays fixed while list scrolls')
  assert(lua('return vim.api.nvim_win_get_cursor(vim.g.source_win)[1]') == 1, 'Wheel must not move editor cursor')
  lua('require("config.keymap-trainer").refresh()')
  assert(snapshot().floats['keymap-trainer'].view.topline > before, 'No-op refresh must preserve scrolling')
  mouse('left', 'press', list.position[1] + 2, list.position[2] + 4)
  mouse('left', 'release', list.position[1] + 2, list.position[2] + 4)
  wait(function(s) return s.current == source end, 'Click release must not leave focus in readonly help')
  lua('vim.keymap.set("n", "<F9>", function() vim.g.command_buf = vim.api.nvim_get_current_buf() end)')
  input('<F9>')
  wait(function() return lua('return vim.g.command_buf == vim.g.source_buf') end, 'Next editor command runs in the source buffer')
  input('<C-w>w')
  wait(function(s) return s.current == source end, 'Window traversal skips help controls too')
  click('[Учить ⇄]')
  wait(function(s) return table.concat(s.floats['keymap-trainer'].lines, '\n'):find('yss + обрамление', 1, true) end,
    'Known filter is mouse-selectable')
  click('[Помню ⇄]')
  wait(function(s) return not table.concat(s.floats['keymap-trainer'].lines, '\n'):find('yss + обрамление', 1, true) end,
    'Learning filter restored')
  print('PASS: grouped single column, adaptive height, fixed progress switch, native scrolling and focus safety.')

  local first_tab = snapshot().tab
  local function current_panel(s)
    return s.floats['keymap-trainer'] and s.floats['keymap-trainer-controls'] and s.total == 2
  end
  lua('vim.cmd.tabnew(); vim.bo.filetype = "lua"')
  wait(current_panel, 'Enabled panel follows into the new tab, leaving no old-tab floats')
  local second_tab = snapshot().tab
  local second_source = snapshot().current
  lua('vim.api.nvim_set_current_tabpage(...)', first_tab)
  wait(function(s) return current_panel(s) and s.current == source end, 'Returning restores panel without stealing focus')
  lua('vim.api.nvim_set_current_tabpage(...)', second_tab)
  wait(function(s) return current_panel(s) and s.current == second_source end, 'Reentering restores both components')
  lua('vim.cmd.tabclose()')
  wait(function(s) return s.tab == first_tab and current_panel(s) end, 'Closing the panel-owning tab does not disable it')
  lua([[
    local first = ...
    vim.cmd.tabnew()
    vim.bo.filetype = 'lua'
    local second = vim.api.nvim_get_current_tabpage()
    require('config.keymap-trainer').refresh()
    vim.api.nvim_set_current_tabpage(first)
    vim.api.nvim_set_current_tabpage(second)
    vim.api.nvim_set_current_tabpage(first)
    vim.cmd('tabclose ' .. vim.api.nvim_tabpage_get_number(second))
  ]], first_tab)
  wait(function(s) return s.tab == first_tab and current_panel(s) end, 'Rapid switches and closing an inactive tab leave one panel')
  print('PASS: current-tab window ownership, tab closing and rapid switching without focus stealing.')

  input('<Space>?')
  wait(function(s) return not s.floats['keymap-trainer'] end, 'Toggle hides')
  lua('require("config.keymap-trainer").refresh()')
  assert(not snapshot().floats['keymap-trainer'], 'Same context must stay hidden')
  lua('vim.cmd.tabnew(); vim.bo.filetype = "lua"; require("config.keymap-trainer").reload(); vim.api.nvim_exec_autocmds("VimResized", {})')
  lua('require("config.keymap-trainer").refresh()')
  assert(snapshot().total == 0, 'New tab, reload and resize do not override explicit hiding')
  lua('vim.cmd.tabclose(); require("config.keymap-trainer").refresh()')
  assert(snapshot().total == 0, 'Closing a tab does not override explicit hiding')
  input('<Space>?')
  wait(function(s) return s.floats['keymap-trainer'] end, 'Toggle shows')
  click('[×]')
  wait(function(s) return not s.floats['keymap-trainer'] end, 'Close control hides')
  lua('vim.cmd.enew(); vim.bo.filetype = "lua"')
  lua('require("config.keymap-trainer").refresh()')
  assert(vim.tbl_isempty(snapshot().floats), 'New buffers do not override explicit hiding')
  input('<Space>?')
  wait(function(s) return s.floats['keymap-trainer'] end, 'Explicit toggle shows in the new buffer')
  input('i')
  wait(function(s) return s.mode == 'i' and s.floats['keymap-trainer'] end, 'Insert context appears without stealing focus')
  assert(snapshot().current == source)
  click('[Учить ⇄]')
  wait(function(s) return s.mode == 'i' and s.current == source end, 'Insert control click returns without leaving Insert')
  click('[Помню ⇄]')
  wait(function(s) return s.mode == 'i' and #s.floats['keymap-trainer'].lines > 60 end, 'Restore long Insert list')
  list = snapshot().floats['keymap-trainer']
  before = list.view.topline
  mouse('wheel', 'down', list.position[1] + 2, list.position[2] + 4)
  wait(function(s) return s.floats['keymap-trainer'].view.topline > before end, 'Wheel works during Insert')
  assert(snapshot().current == source and snapshot().mode == 'i', 'Wheel must preserve Insert mode and focus')
  input('<Esc>:')
  wait(function(s) return s.mode == 'c' and s.floats['keymap-trainer'] end, 'Command-line context')
  assert(table.concat(snapshot().floats['keymap-trainer'].lines, '\n'):find('Дополнение команд', 1, true))
  input('<Esc>')
  wait(function(s) return s.mode == 'n' end, 'Return to Normal')
  lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "selected text", "another line" })')
  input('vll')
  wait(function(s) return s.mode == 'v' end, 'Visual context')
  local selection = lua('return { vim.fn.getpos("v"), vim.api.nvim_win_get_cursor(0) }')
  click('[Учить ⇄]')
  wait(function(s) return s.mode == 'v' and s.current == source end, 'Mouse controls preserve Visual mode')
  assert(vim.deep_equal(lua('return { vim.fn.getpos("v"), vim.api.nvim_win_get_cursor(0) }'), selection),
    'Mouse controls must preserve the selected source range')
  click('[Помню ⇄]')
  wait(function(s) return s.mode == 'v' and s.current == source end, 'Restore learning without changing selection')
  input('<Esc>')
  wait(function(s) return s.mode == 'n' end, 'Exit Visual')
  lua('vim.bo.buftype = "nofile"')
  lua('require("config.keymap-trainer").refresh()')
  assert(not snapshot().floats['keymap-trainer'], 'Plugin buffers must not be covered')
  lua('vim.bo.buftype = ""; require("config.keymap-trainer").refresh()')
  wait(function(s) return s.floats['keymap-trainer'] end, 'Ordinary buffer restores panel')
  lua('vim.wo.diff = true; require("config.keymap-trainer").refresh()')
  local function diff_section(s)
    local list = s.floats['keymap-trainer']
    return list and list.lines[1] == 'Diff'
  end
  wait(diff_section, 'Writable diff renders only the Diff section')
  assert(#snapshot().floats['keymap-trainer'].lines == 6, 'Writable diff shows only unlearned diff actions and heading')
  assert(snapshot().floats['keymap-trainer'].config.height == 6, 'Short lists shrink to their wrapped content')
  lua('vim.o.columns, vim.o.lines = 48, 44; vim.api.nvim_exec_autocmds("VimResized", {})')
  wait(function(s) return s.floats['keymap-trainer'].config.width == 42
    and s.floats['keymap-trainer'].config.height > #s.floats['keymap-trainer'].lines end,
    'Width is clamped to the screen while wrapped descriptions still grow the panel height')
  lua('vim.o.columns = 80; vim.api.nvim_exec_autocmds("VimResized", {})')
  wait(function(s) return s.floats['keymap-trainer'].config.width == 45 end,
    'Adaptive width also increases by 40% on smaller screens')
  lua('vim.o.columns, vim.o.lines = 160, 50; vim.api.nvim_exec_autocmds("VimResized", {})')
  wait(function(s) return s.floats['keymap-trainer'].config.height == 6 end, 'Wider panel shrinks after reflow')
  click('[Учить ⇄]')
  wait(function(s) return diff_section(s) and #s.floats['keymap-trainer'].lines == 2
    and s.floats['keymap-trainer'].lines[2]:find('␣dp', 1, true) end, 'Known diff keeps only the Diff section')
  click('[Помню ⇄]')
  wait(function(s) return diff_section(s) and #s.floats['keymap-trainer'].lines == 6 end, 'Diff learning view restored')
  lua('vim.bo.buftype = "nowrite"; vim.bo.modifiable = false; vim.wo.diff = true; vim.wo.scrollbind = true; vim.wo.cursorbind = true; require("config.keymap-trainer").refresh()')
  wait(diff_section, 'Readonly virtual diff renders only the Diff section')
  click('[Учить ⇄]')
  wait(function(s) return diff_section(s) and #s.floats['keymap-trainer'].lines == 2
    and s.floats['keymap-trainer'].lines[2]:find('␣dp', 1, true) end, 'Readonly diff supports the known filter too')
  click('[Помню ⇄]')
  wait(function(s) return diff_section(s) and #s.floats['keymap-trainer'].lines == 6 end, 'Readonly diff learning view restored')
  input('v')
  wait(function(s) return s.mode == 'v' and s.floats['keymap-trainer']
    and s.floats['keymap-trainer'].lines[1] == 'Нет команд для этого режима и фильтра.' end,
    'No unrelated Visual sections when diff entries do not match the mode')
  input('<Esc>')
  wait(diff_section, 'Normal mode restores the Diff section')
  -- Recreate windows while in diff, exercising native option inheritance (not just reconfiguration).
  lua('require("config.keymap-trainer").hide(); require("config.keymap-trainer").show()')
  assert(lua([[
    assert(vim.wo.diff and vim.wo.scrollbind and vim.wo.cursorbind, 'Panel must preserve source diff bindings')
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].filetype:match('^keymap%-trainer') then
        assert(not vim.wo[win].diff and not vim.wo[win].scrollbind and not vim.wo[win].cursorbind,
          'Help floats must not inherit diff, scrollbind or cursorbind')
      end
    end
    return true
  ]]))
  lua('vim.wo.diff = false; vim.wo.scrollbind = false; vim.wo.cursorbind = false; vim.bo.buftype = ""; vim.bo.modifiable = true; require("config.keymap-trainer").refresh()')
  wait(function(s) return s.floats['keymap-trainer']
    and table.concat(s.floats['keymap-trainer'].lines, '\n'):find('\nПравки\n', 1, true) end,
    'Leaving diff restores ordinary contextual sections')
  print('PASS: diff-only sections, writable/readonly progress filters, empty modes and catalogue isolation.')
  local closed = snapshot().floats['keymap-trainer'].win
  lua('vim.api.nvim_win_close(..., true)', closed)
  wait(function(s) return vim.tbl_isempty(s.floats) end, 'External close leaves no orphan controls')
  input('<Space>?')
  wait(function(s) return s.floats['keymap-trainer'] and s.floats['keymap-trainer-controls'] end, 'Quick toggle restores the entire panel')
  lua('vim.api.nvim_win_close(..., true)', snapshot().floats['keymap-trainer-controls'].win)
  wait(function(s) return s.total == 0 end, 'External controls close also hides the whole panel')
  lua('vim.cmd.tabnew(); require("config.keymap-trainer").refresh()')
  assert(snapshot().total == 0, 'External component close remains a user hide across tabs')
  lua('vim.cmd.tabclose(); require("config.keymap-trainer").refresh()')
  assert(snapshot().total == 0, 'Returning does not undo the external user close')
  input('<Space>?')
  wait(current_panel, 'Explicit toggle restores panel after external controls close')

  lua([[
    local m = require('config.keymap-trainer')
    local path = ...
    local count = #m.items(m.context())
    vim.fn.writefile({ '{ broken' }, path)
    assert(not m.reload())
    assert(#m.items(m.context()) == count, 'Invalid reload retains previous good catalogue')
  ]], path)
  vim.fn.writefile({ vim.json.encode(data) }, path)
  lua('assert(require("config.keymap-trainer").reload())')
  lua('vim.o.columns, vim.o.lines = 40, 12; vim.api.nvim_exec_autocmds("VimResized", {})')
  wait(function(s) return not s.floats['keymap-trainer'] end, 'Small screens hide cleanly')
  lua('vim.o.columns, vim.o.lines = 160, 50; vim.api.nvim_exec_autocmds("VimResized", {})')
  wait(function(s) return s.floats['keymap-trainer'] end, 'Resize restores panel')
  assert(lua('return vim.api.nvim_buf_get_lines(vim.g.source_buf, 0, -1, false)')[1] == 'one', 'Source text remains unchanged')
  assert(lua('return vim.v.errmsg') == '', 'No unhandled scheduled or mouse errors')
  assert(#lua('return vim.g.notices') == 1, 'Only the intentional invalid-JSON warning is expected')
  print('PASS: toggle/hide/reappear, Insert/cmdline, plugin exclusion, atomic reload and resize lifecycle.')
end, debug.traceback)
vim.fn.jobstop(child)
vim.fn.delete(path)
vim.fn.delete(task, 'd')
if not ok then error(err) end
