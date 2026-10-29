local M = {}
local highlight = 'RenderMarkdownTableStripe'

local function set_highlight()
  local normal = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
  local dark = vim.o.background == 'dark'
  local bg = normal.bg or (dark and 0x202020 or 0xffffff)
  local target = dark and 255 or 0
  local function channel(shift)
    local value = math.floor(bg / 2 ^ shift) % 256
    return math.floor(value + (target - value) * 0.045 + 0.5)
  end
  vim.api.nvim_set_hl(0, highlight, {
    bg = channel(16) * 65536 + channel(8) * 256 + channel(0),
  })
end

-- Keep syntax foregrounds and styles; override only the background.
local function shade(line)
  for _, chunk in ipairs(line) do
    local groups = type(chunk[2]) == 'table' and vim.list_extend({}, chunk[2])
        or (chunk[2] and { chunk[2] } or {})
    groups[#groups + 1] = highlight
    chunk[2] = groups
  end
end

local table_query
local function striped_rows(ctx)
  table_query = table_query or vim.treesitter.query.parse('markdown', '(pipe_table) @table')
  local rows = {}
  for _, node in table_query:iter_captures(ctx.root, ctx.buf) do
    local delimiter
    for child in node:iter_children() do
      if child:type() == 'pipe_table_delimiter_row' then
        delimiter = child:start()
      elseif child:type() == 'pipe_table_row' and delimiter then
        local row, col, end_row, end_col = child:range()
        -- Anchor parity to the delimiter, not the visible part of the table.
        if (row - delimiter) % 2 == 0 then
          rows[row] = { col = col, end_row = end_row, end_col = end_col }
        end
      end
    end
  end
  return rows
end

-- Transform the documented custom-handler Mark format, not private renderer
-- methods. Work on copies so an optional decoration failure leaves the native
-- marks intact. Layout, wrapping and anti-conceal remain owned by the plugin.
local function decorate(ctx, marks)
  local rows, result, rendered = striped_rows(ctx), {}, {}
  for _, mark in ipairs(marks) do
    local row = rows[mark.start_row]
    -- Quote/list prefixes can share the source row without belonging to the
    -- table. In particular, they still render when pipe_table.enabled=false.
    if row and mark.start_col >= row.col and (mark.opts.virt_text or mark.replace) then
      mark = vim.deepcopy(mark)
      if mark.opts.virt_text then shade(mark.opts.virt_text) end
      for _, line in ipairs(mark.replace or {}) do shade(line) end
      rendered[mark.start_row] = true
    end
    result[#result + 1] = mark
  end
  for row in pairs(rendered) do
    local range = rows[row]
    result[#result + 1] = {
      conceal = true,
      start_row = row,
      start_col = range.col,
      opts = {
        end_row = range.end_row,
        end_col = range.end_col,
        hl_group = highlight,
        priority = 4097,
      },
    }
  end
  return result
end

local warned = false
local function warn(reason)
  if warned then return end
  warned = true
  vim.schedule(function()
    vim.notify('Markdown table stripes unavailable; using the default Markdown renderer: ' .. tostring(reason),
      vim.log.levels.WARN)
  end)
end

function M.setup()
  set_highlight()
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = vim.api.nvim_create_augroup('MarkdownTableZebra', { clear = true }),
    callback = set_highlight,
  })

  -- One guarded integration point: the builtin handler implements the same
  -- parse(ctx) -> Mark[] contract as custom handlers. If it moves or disappears,
  -- omit our override altogether instead of aborting render-markdown.setup().
  local ok, builtin = pcall(require, 'render-markdown.handler.markdown')
  if not ok or type(builtin) ~= 'table' or type(builtin.parse) ~= 'function' then
    warn(ok and 'builtin Markdown handler has no parse function' or builtin)
    return nil
  end
  local enabled = true
  return {
    extends = false, -- Delegate below; do not also run the builtin a second time.
    parse = function(ctx, ...)
      -- Do not hide failures in the native renderer behind a cosmetic fallback.
      local marks = builtin.parse(ctx, ...)
      if not enabled then return marks end
      local success, decorated = pcall(decorate, ctx, marks)
      if success then return decorated end
      enabled = false
      warn(decorated)
      return marks
    end,
  }
end

return M
