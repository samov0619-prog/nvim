-- Run: nvim -n --headless -u NONE -i NONE -l tests/command-palette-ui.lua
-- Real picker, terminal fzf filtering, preview, and command-line prefill.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local child = vim.fn.jobstart({ vim.v.progpath, '--embed', '--headless', '-n', '-u', 'NONE', '-i', 'NONE' }, { rpc = true })
local function lua(code, ...)
  return vim.rpcrequest(child, 'nvim_exec_lua', code, { ... })
end
local function state()
  return lua([[
    local text = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then
        vim.list_extend(text, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      end
    end
    return {
      mode = vim.api.nvim_get_mode().mode,
      cmdline = vim.fn.getcmdline(),
      executed = vim.g.palette_executed,
      text = table.concat(text, '\n'),
    }
  ]])
end
local function wait(predicate, label)
  assert(vim.wait(5000, function() return predicate(state()) end, 20), label .. '\n' .. vim.inspect(state()))
end
local function input(keys) vim.rpcrequest(child, 'nvim_input', keys) end

local ok, err = xpcall(function()
  lua([[
    local root = ...
    vim.opt.rtp:prepend(root)
    for _, plugin in ipairs({ 'fzf-lua', 'mini.files', 'mini.icons', 'nvim-web-devicons' }) do
      vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/' .. plugin)
    end
    vim.o.lines, vim.o.columns = 40, 160
    require('config.float-style').setup()
    dofile(root .. '/lua/plugins/fzf-lua.lua')[1].config()
    vim.g.palette_executed = false
    vim.api.nvim_create_user_command('PaletteUnmapped', function() vim.g.palette_executed = true end, {
      desc = 'Calibrate spectroscope without a key mapping',
    })
    vim.api.nvim_create_user_command('PaletteDefinition', 'echo "DefinitionOnlyNeedle"', {})
    require('config.command-palette').open()
  ]], root)
  wait(function(s) return s.mode == 't' end, 'Real fzf picker opens')
  local function check_borders(minimum)
    return lua([[
    local minimum = ...
    local expected, count = require('config.float-style').border, 0
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local config = vim.api.nvim_win_get_config(win)
      if config.relative ~= '' and config.border then
        assert(vim.deep_equal(config.border, expected), 'Real picker and preview use thin-block borders')
        assert(vim.wo[win].winhighlight:find('FloatBorder:UserFzfBorder', 1, true),
          'Real picker and preview use the Fzf-specific contrast group')
        count = count + 1
      end
    end
    return count >= minimum
    ]], minimum)
  end

  input('remove good or bad word')
  wait(function(s) return s.text:find('spellundo%s+remove good or bad word') end,
    'Terminal picker finds the builtin command by its preview description')

  input('<C-u>DefinitionOnlyNeedle')
  wait(function(s)
    -- fzf may horizontally scroll the row to keep the matching definition visible.
    return s.text:find('name = "PaletteDefinition"', 1, true) and s.text:find('DefinitionOnlyNeedle', 1, true)
  end,
    'Terminal picker searches command definitions too')

  input('<C-u>spectroscope')
  wait(function(s)
    return s.text:find('PaletteUnmapped', 1, true) and s.text:find('Calibrate spectroscope', 1, true)
  end,
    'Terminal picker finds an unmapped command by description')
  wait(function(s)
    return s.text:find('name = "PaletteUnmapped"', 1, true)
      and s.text:find('Calibrate spectroscope without a key mapping', 1, true)
      and s.text:find('callback = <function', 1, true)
      and s.text:find('nargs = "0"', 1, true)
  end,
    'Real preview shows the full command registration, including its searchable definition')
  assert(check_borders(1), 'Command picker uses thin-block borders (its preview runs inside fzf)')
  assert(state().text:find('🭽', 1, true), 'Native terminal-rendered fzf preview also uses thin-block corners')
  input('<CR>')
  wait(function(s) return s.mode == 'c' and s.cmdline == 'PaletteUnmapped ' end,
    'Enter prefills only the command name in the real command line')
  assert(not state().executed, 'Picker selection must not execute the command')
  print('PASS: real picker searches descriptions/definitions, previews complete registration tables, and safely prefills commands')
  input('<Esc>')
  wait(function(s) return s.mode == 'n' end, 'Leave prefilled command without executing')
  lua([[
    require('fzf-lua').fzf_exec({ ... }, { previewer = 'builtin' })
  ]], root .. '/doc/keymap-trainer.md')
  wait(function() return check_borders(2) end, 'Real picker and separate builtin preview use thin-block borders')
  print('PASS: configured FzfLua picker and builtin preview use the shared Unicode frame.')
end, debug.traceback)
vim.fn.jobstop(child)
if not ok then error(err) end
