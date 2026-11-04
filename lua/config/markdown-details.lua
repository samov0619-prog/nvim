local M = {}
local cache = {}
local query

local function child(node, kind)
  for item in node:iter_children() do
    if item:type() == kind then return item end
  end
end

local function tag_name(node, buf)
  local name = node and child(node, 'tag_name')
  return name and vim.treesitter.get_node_text(name, buf):lower()
end

local function text(node, buf)
  local kind = node:type()
  if kind == 'start_tag' or kind == 'end_tag' or kind == 'comment' then return '' end
  if node:named_child_count() == 0 then return vim.treesitter.get_node_text(node, buf) end
  local parts = {}
  local row, col = node:start()
  for item in node:iter_children() do
    local next_row, next_col = item:start()
    -- HTML text nodes omit surrounding whitespace; keep the source gaps.
    parts[#parts + 1] = table.concat(vim.api.nvim_buf_get_text(buf, row, col, next_row, next_col, {}), '\n')
    parts[#parts + 1] = text(item, buf)
    row, col = item:end_()
  end
  local end_row, end_col = node:end_()
  parts[#parts + 1] = table.concat(vim.api.nvim_buf_get_text(buf, row, col, end_row, end_col, {}), '\n')
  return table.concat(parts)
end

function M.get(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  if cache[buf] and cache[buf].tick == tick then return cache[buf].items end
  local ok, parser = pcall(vim.treesitter.get_parser, buf, 'markdown')
  if not ok then return {} end
  -- Parse injections too: UFO's first request may precede HTML highlighting.
  local trees = parser:parse(true)
  local root = trees[1]:root()
  local items = {}
  parser:for_each_tree(function(tree, language)
    if language:lang() ~= 'html' then return end
    query = query or vim.treesitter.query.parse('html', '(element) @element')
    for _, node in query:iter_captures(tree:root(), buf) do
      local start_tag, end_tag = child(node, 'start_tag'), child(node, 'end_tag')
      if tag_name(start_tag, buf) == 'details' and tag_name(end_tag, buf) == 'details' then
        local row, col, end_row, end_col = node:range()
        local source = root:named_descendant_for_range(row, col, row, col)
        local in_code = false
        while source do
          if source:type() == 'fenced_code_block' or source:type() == 'indented_code_block' then
            in_code = true
            break
          end
          source = source:parent()
        end
        if not in_code then
          local open, summary = false, 'Details'
          for item in start_tag:iter_children() do
            local name = item:type() == 'attribute' and child(item, 'attribute_name')
            if name and vim.treesitter.get_node_text(name, buf):lower() == 'open' then open = true end
          end
          for item in node:iter_children() do
            if item:type() == 'element' and tag_name(child(item, 'start_tag'), buf) == 'summary' then
              local value = vim.trim(text(item, buf):gsub('%s+', ' '))
              if value ~= '' then summary = value end
              break
            end
          end
          items[row] = { last = end_col == 0 and end_row - 1 or end_row, summary = summary, open = open }
        end
      end
    end
  end)
  cache[buf] = { tick = tick, items = items }
  return items
end

function M.folds(buf)
  local items = M.get(buf)
  local ranges = require('ufo').getFolds(buf, 'treesitter')
  if not ranges then return ranges end
  local result, seen = {}, {}
  for _, range in ipairs(ranges) do
    local key = range.startLine .. ':' .. range.endLine
    if not seen[key] then
      local item = items[range.startLine]
      if item and item.last == range.endLine then
        range = vim.tbl_extend('force', {}, range, { kind = item.open and 'details_open' or 'details' })
      end
      result[#result + 1], seen[key] = range, true
    end
  end
  return result
end

function M.fold_text(virt_text, first, last, width, truncate, ctx, fallback)
  if vim.bo[ctx.bufnr].filetype == 'markdown' then
    local item = M.get(ctx.bufnr)[first - 1]
    if item and item.last == last - 1 then
      virt_text = { { '▸ ' .. item.summary, 'RenderMarkdownInfo' } }
    end
  end
  return fallback(virt_text, first, last, width, truncate)
end

function M.setup()
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = vim.api.nvim_create_augroup('MarkdownDetails', { clear = true }),
    callback = function(ev) cache[ev.buf] = nil end,
  })
end

return M
