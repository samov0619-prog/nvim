-- Run: nvim -n --headless -u NONE -i NONE -l tests/completion.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local child = vim.fn.jobstart({ vim.v.progpath, '--embed', '--headless', '-n', '-u', 'NONE', '-i', 'NONE' }, { rpc = true })
local function lua(code, ...)
  return vim.rpcrequest(child, 'nvim_exec_lua', code, { ... })
end
local function state()
  return lua([[
    local cmp = require('blink.cmp')
    return {
      mode = vim.api.nvim_get_mode().mode,
      lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
      cursor = vim.api.nvim_win_get_cursor(0),
      menu = cmp.is_menu_visible(),
      ghost = cmp.is_ghost_text_visible(),
      count = #cmp.get_items(),
      selected = cmp.get_selected_item_idx(),
      marks = vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace('completion_available'), 0, -1, { details = true }),
    }
  ]])
end
local function wait(predicate, label)
  assert(vim.wait(3000, function() return predicate(state()) end, 10), label .. '\n' .. vim.inspect(state()))
end
local function input(keys)
  vim.rpcrequest(child, 'nvim_input', keys)
  -- Let input, redraw/autocmds and Blink's deferred cursor bookkeeping settle.
  vim.wait(25, function() return false end)
end
local function reset(text)
  -- Bypass the contextual Esc mapping when preparing a new case.
  lua([=[vim.api.nvim_feedkeys(vim.keycode([[<C-\><C-n>]]), 'n', false)]=])
  wait(function(s) return s.mode == 'n' end, 'Reset to Normal')
  lua([[
    require('luasnip').unlink_current()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { ... })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
  ]], text or '')
  input('A')
  wait(function(s) return s.mode == 'i' end, 'Enter Insert')
end

local ok, err = xpcall(function()
  lua([[
    local root = ...
    vim.opt.rtp:prepend(root)
    for _, plugin in ipairs({ 'blink.cmp', 'LuaSnip', 'neotab.nvim', 'nvim-autopairs' }) do
      vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/' .. plugin)
    end
    vim.o.lines, vim.o.columns = 40, 120
    vim.o.swapfile, vim.o.backup, vim.o.writebackup = false, false, false
    vim.o.expandtab, vim.o.shiftwidth, vim.o.tabstop = true, 2, 2
    package.preload.completion_fixture = function()
      return { new = function()
        return { get_completions = function(_, _, callback)
          callback({
            is_incomplete_forward = false, is_incomplete_backward = false,
            items = {
              { label = 'alphabet', sortText = '1' },
              { label = 'alpine', sortText = '2' },
              { label = 'invoke', insertText = 'call(${1:first}, ${2:second})$0', insertTextFormat = 2 },
              { label = 'абвгд' },
              { label = 'éclair' },
            },
          })
        end }
      end }
    end
    require('luasnip').setup({})
    require('nvim-autopairs').setup({})
    local neotab = dofile(root .. '/lua/plugins/neotab-nvim.lua')[1]
    require('neotab').setup(neotab.opts)
    local blink = dofile(root .. '/lua/plugins/blink.lua')[1]
    blink.opts.sources.default = { 'fixture' }
    blink.opts.sources.providers.fixture = { name = 'Fixture', module = 'completion_fixture', min_keyword_length = 1 }
    blink.opts.fuzzy.sorts = { 'sort_text' }
    blink.opts.cmdline.enabled = false
    blink.config(nil, blink.opts)
  ]], root)

  reset()
  input('al')
  wait(function(s) return s.count == 2 and #s.marks == 1 end, 'Available candidates get a marker')
  local s = state()
  assert(not s.menu and not s.ghost and s.lines[1] == 'al', 'No automatic UI or text insertion')
  local mark = s.marks[1]
  assert(mark[3] == 0 and mark[4].end_col == 2, 'Underline covers the last two letters')
  assert(mark[4].hl_group == 'CompletionAvailable' and not mark[4].virt_text, 'No extra characters or text displacement')
  assert(mark[4].priority < vim.hl.priorities.diagnostics, 'Diagnostics have higher priority')
  local highlight = lua([[return vim.api.nvim_get_hl(0, { name = 'CompletionAvailable', link = false })]])
  assert(highlight.underline and highlight.sp and not highlight.fg and not highlight.bg, 'Only the underline is colored')
  lua([[vim.api.nvim_exec_autocmds('ColorScheme', {})]])
  assert(lua([[return vim.api.nvim_get_hl(0, { name = 'CompletionAvailable', link = false }).underline]]), 'Underline survives theme changes')
  input('<Tab>')
  wait(function(s) return s.menu and s.lines[1] == 'alphabet' end, 'First Tab opens and previews first item')
  assert(#state().marks == 0, 'Marker is hidden while the menu is open')
  input('<Tab>')
  wait(function(s) return s.lines[1] == 'alpine' end, 'Tab previews next item')
  input('<S-Tab>')
  wait(function(s) return s.lines[1] == 'alphabet' end, 'Shift-Tab previews previous item')
  input('<S-Tab>')
  wait(function(s) return s.lines[1] == 'alpine' and s.selected == 2 end, 'Shift-Tab wraps without an unselected stop')
  input('<Tab>')
  wait(function(s) return s.lines[1] == 'alphabet' and s.selected == 1 end, 'Tab wraps without an unselected stop')
  input('<Esc>')
  wait(function(s) return not s.menu and s.lines[1] == 'al' end, 'Esc restores original text')
  assert(state().mode == 'i', 'Esc cancelling completion stays in Insert')
  input('<Esc>')
  wait(function(s) return s.mode == 'n' end, 'Second Esc exits Insert')
  assert(#state().marks == 0)

  reset()
  input('al')
  wait(function(s) return #s.marks == 1 end, 'Marker before accepting')
  input('<Tab>')
  wait(function(s) return s.menu and s.lines[1] == 'alphabet' end, 'Preview before accepting')
  input('<CR>')
  wait(function(s) return not s.menu end, 'Enter closes the menu')
  assert(state().mode == 'i' and #state().lines == 1 and state().lines[1] == 'alphabet', 'Enter accepts without newline')
  input('<CR>')
  wait(function(s) return #s.lines == 2 end, 'Enter without menu inserts newline')

  reset()
  input('al')
  wait(function(s) return #s.marks == 1 end, 'Hidden candidates before newline')
  input('<CR>')
  wait(function(s) return #s.lines == 2 end, 'Hidden candidates do not intercept Enter')
  assert(state().lines[1] == 'al')

  reset('λ ')
  input('al')
  wait(function(s) return #s.marks == 1 end, 'Marker also works after multibyte text')
  mark = state().marks[1]
  assert(mark[3] == #'λ ' and mark[4].end_col == #'λ al', 'Underline uses byte columns after multibyte text')
  input('zz')
  wait(function(s) return s.count == 0 and #s.marks == 0 end, 'Marker disappears when matches disappear')

  reset()
  input('a')
  wait(function(s) return #s.marks == 1 end, 'One-letter keyword gets an underline')
  mark = state().marks[1]
  assert(mark[3] == 0 and mark[4].end_col == 1, 'Short keywords do not underline preceding text')

  reset()
  input('абв')
  wait(function(s) return #s.marks == 1 end, 'Multibyte keyword gets an underline')
  mark = state().marks[1]
  assert(mark[3] == #'а' and mark[4].end_col == #'абв', 'Underline covers two characters, not two bytes')

  reset()
  input('éc')
  wait(function(s) return #s.marks == 1 end, 'Combining accents get an underline')
  mark = state().marks[1]
  assert(mark[3] == 0 and mark[4].end_col == #'éc', 'Combining accents stay with their letter')

  reset()
  input('zzzz')
  wait(function(s) return s.lines[1] == 'zzzz' and s.count == 0 end, 'No matching candidates')
  assert(#state().marks == 0 and not state().menu)
  input('<Tab>')
  wait(function(s) return s.lines[1] == 'zzzz  ' end, 'Tab without candidates inserts indentation')
  input('<Esc>')
  wait(function(s) return s.mode == 'n' end, 'Esc without menu exits directly')

  reset('()')
  input('<Left>')
  wait(function(s) return s.cursor[2] == 1 and s.count == 0 end, 'No candidates inside empty parentheses')
  input('<Tab>')
  wait(function(s) return s.lines[1] == '( )' end, 'Tab inside parentheses does not tabout')
  reset('()')
  input('<Left>')
  wait(function(s) return s.cursor[2] == 1 end, 'Cursor before closing parenthesis')
  input('<C-l>')
  wait(function(s) return s.cursor[2] == 2 end, 'Ctrl-L exits parentheses')
  assert(state().lines[1] == '()' and state().mode == 'i')
  input('<C-l>')
  lua('return true')
  assert(state().lines[1] == '()', 'Unavailable tabout must not insert indentation')

  reset()
  input('invoke')
  wait(function(s) return s.count == 1 and #s.marks == 1 end, 'Single candidate gets a marker')
  input('<Tab>')
  wait(function(s) return s.menu end, 'Single candidate still opens menu rather than accepting')
  input('<Tab><S-Tab>')
  assert(state().menu and state().selected == 1, 'Single candidate stays selected when cycling')
  input('<CR>')
  wait(function(s) return s.lines[1] == 'call(first, second)' and not s.menu end, 'Enter expands snippet')
  input('<C-j>')
  wait(function(s) return s.cursor[2] >= 12 end, 'Separate forward snippet navigation')
  input('<C-k>')
  wait(function(s) return s.cursor[2] < 12 end, 'Separate backward snippet navigation')

  print('PASS: completion marker, Tab previews, Enter accept/newline, Esc cancel, indentation, tabout, and snippets')
end, debug.traceback)
vim.fn.jobstop(child)
if not ok then error(err) end
vim.cmd('qa!')
