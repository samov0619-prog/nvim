local M = {}
local builtin_descriptions

local function one_line(text)
  return vim.trim((text or ''):gsub('%s+', ' '))
end

local function builtin_help()
  if builtin_descriptions then return builtin_descriptions end
  builtin_descriptions = {}
  local path = vim.env.VIMRUNTIME .. '/doc/index.txt'
  if vim.fn.filereadable(path) == 0 then return builtin_descriptions end

  -- Use the installed version's Ex index, including wrapped descriptions.
  local current
  for _, line in ipairs(vim.fn.readfile(path)) do
    local name, description = line:match('^|:(%S+)|%s+%S+%s+(.*%S)')
    if name then
      current = name
      builtin_descriptions[name] = one_line(description)
    elseif current and line:match('^%s+%S') then
      builtin_descriptions[current] = builtin_descriptions[current] .. ' ' .. one_line(line)
    else
      current = nil
    end
  end
  return builtin_descriptions
end

local function collect(bufnr)
  local descriptions = vim.deepcopy(builtin_help())
  local commands, kinds = vim.deepcopy(descriptions), {}
  for name in pairs(descriptions) do kinds[name] = 'cmd_ex' end
  -- Re-read registrations for each invocation: commands and buffer scope change.
  for scope, registrations in ipairs({ vim.api.nvim_get_commands({}), vim.api.nvim_buf_get_commands(bufnr or 0, {}) }) do
    for name, command in pairs(registrations) do
      descriptions[name] = one_line(command.desc or command.definition)
      commands[name] = command
      kinds[name] = scope == 1 and 'cmd_global' or 'cmd_buf'
    end
  end
  return descriptions, commands, kinds
end

function M.descriptions(bufnr)
  local descriptions = collect(bufnr)
  return descriptions
end

function M.open()
  local descriptions, commands, kinds = collect()
  local utils = require('fzf-lua.utils')
  local hls = vim.tbl_extend('force', {
    cmd_ex = 'FzfLuaCmdEx', cmd_global = 'FzfLuaCmdGlobal', cmd_buf = 'FzfLuaCmdBuf',
  }, require('fzf-lua.config').globals.hls or {})
  local function selected_name(selected)
    return selected[1] and utils.strip_ansi_coloring(selected[1]):match('^[^\t]+')
  end
  local rows = {}
  local names = vim.tbl_keys(descriptions)
  table.sort(names)
  for _, name in ipairs(names) do
    -- Use the same configurable highlight groups as FzfLua's commands picker.
    local colored = utils.ansi_from_hl(hls[kinds[name]], name)
    rows[#rows + 1] = colored .. '\t' .. descriptions[name]
  end
  -- commands() supplies a string list, which bypasses fn_transform in FzfLua.
  -- Pass complete searchable rows through the public custom-picker API instead.
  return require('fzf-lua').fzf_exec(rows, {
    prompt = 'Commands> ',
    winopts = { title = 'Commands' },
    multiprocess = false,
    fzf_opts = {
      ['--nth'] = false,
      ['--with-nth'] = false,
      ['--no-multi'] = true,
    },
    preview = function(selected)
      local name = selected_name(selected)
      -- Preserve the full registration table, as in the native commands picker.
      return name and vim.inspect(commands[name]) or ''
    end,
    actions = {
      enter = function(selected)
        local name = selected_name(selected)
        if not name then return end
        -- Prefill ':' for inspection/arguments. Never execute on picker selection.
        require('fzf-lua.actions').ex_run({ name .. ' ' })
      end,
    },
  })
end

return M
