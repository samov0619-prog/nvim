local M = {}
local api = vim.api
local namespace = api.nvim_create_namespace('completion_available')
local marked_buffer

local function clear()
  if marked_buffer and api.nvim_buf_is_valid(marked_buffer) then
    api.nvim_buf_clear_namespace(marked_buffer, namespace, 0, -1)
  end
  marked_buffer = nil
end

-- Async results must still describe the text and cursor we are looking at.
local function current_context(cmp)
  local context = cmp.get_context()
  if not context or context.mode ~= 'default' or api.nvim_get_mode().mode:sub(1, 1) ~= 'i' then return end
  if context.bufnr ~= api.nvim_get_current_buf() or context.line ~= api.nvim_get_current_line() then return end
  local cursor = api.nvim_win_get_cursor(0)
  if cursor[1] ~= context.cursor[1] or cursor[2] ~= context.cursor[2] then return end
  return context
end

function M.tab(cmp, direction)
  if not cmp.is_menu_visible() then
    -- No candidates (and no marker): Tab keeps its ordinary indentation behavior.
    if direction == 1 and current_context(cmp) and #cmp.get_items() > 0 then
      return cmp.show_and_insert()
    end
    return
  end

  local count, index = #cmp.get_items(), cmp.get_selected_item_idx()
  if count == 0 or (count == 1 and index == 1) then return true end
  -- Skip Blink's extra "no selection/original text" stop when wrapping.
  if direction == 1 then
    if index == count then return cmp.select_prev({ count = count - 1 }) end
    return cmp.select_next()
  end
  if index == 1 then return cmp.select_next({ count = count - 1 }) end
  return cmp.select_prev()
end

function M.setup()
  clear()
  local group = api.nvim_create_augroup('CompletionAvailable', { clear = true })
  local function highlight()
    api.nvim_set_hl(0, 'CompletionAvailable', {
      underline = true,
      sp = vim.o.background == 'light' and '#008b8b' or '#56d4dd',
    })
  end
  highlight()
  api.nvim_create_autocmd('ColorScheme', { group = group, callback = highlight })

  local function update()
    clear()
    local cmp = require('blink.cmp')
    if cmp.is_menu_visible() or #cmp.get_items() == 0 then return end
    local context = current_context(cmp)
    if not context then return end
    local column = context.cursor[2]
    local prefix = context.line:sub(context.bounds.start_col, column)
    local width = 2
    -- A trigger such as '.' may have candidates but no keyword yet.
    if prefix == '' then
      prefix, width = context.line:sub(1, column), 1
    end
    -- Count characters, not bytes, and keep combining accents with their letter.
    local tail = vim.fn.strcharpart(prefix, math.max(0, vim.fn.strchars(prefix, 1) - width), width, 1)
    if tail == '' then return end
    marked_buffer = context.bufnr
    api.nvim_buf_set_extmark(marked_buffer, namespace, context.cursor[1] - 1, column - #tail, {
      end_col = column,
      hl_group = 'CompletionAvailable',
      -- Diagnostics must take precedence over the availability hint.
      priority = 90,
    })
  end

  -- Blink's public events keep the marker in sync without polling or patching it.
  api.nvim_create_autocmd('User', {
    group = group,
    pattern = { 'BlinkCmpShow', 'BlinkCmpListSelect' },
    callback = update,
  })
  api.nvim_create_autocmd('User', {
    group = group,
    pattern = { 'BlinkCmpHide', 'BlinkCmpMenuOpen' },
    callback = clear,
  })
  api.nvim_create_autocmd({ 'CursorMovedI', 'TextChangedI' }, { group = group, callback = update })
  api.nvim_create_autocmd({ 'InsertLeave', 'BufLeave' }, { group = group, callback = clear })
end

return M
