local M = {}
local api = vim.api

-- Tree-sitter owns fence recognition, including nested quotes/lists and examples
-- containing literal fences. Remove only grammar-owned continuation prefixes.
function M.source(buf, row)
  local name = api.nvim_buf_get_name(buf):lower()
  if name:match('%.mmd$') or name:match('%.mermaid$') or vim.bo[buf].filetype == 'mermaid' then
    return table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), '\n') .. '\n'
  end
  local ok, parser = pcall(vim.treesitter.get_parser, buf, 'markdown')
  if not ok then return nil, 'Нужен Tree-sitter parser markdown' end
  local trees = parser:parse()
  local query = vim.treesitter.query.parse('markdown', '(fenced_code_block) @block')
  for _, block in query:iter_captures(trees[1]:root(), buf) do
    local first, _, last, last_col = block:range()
    if row >= first and (row < last or (row == last and last_col > 0)) then
      local language, content
      for child in block:iter_children() do
        if child:type() == 'info_string' then
          language = vim.treesitter.get_node_text(child, buf):match('^([%w_-]+)')
        elseif child:type() == 'code_fence_content' then
          content = child
        end
      end
      if not language or language:lower() ~= 'mermaid' then break end
      if not content then return nil, 'Пустой блок Mermaid' end
      local start_row, start_col, end_row, end_col = content:range()
      local prefixes = { [start_row] = start_col }
      for child in content:iter_children() do
        if child:type() == 'block_continuation' then
          local r, _, _, col = child:range()
          prefixes[r] = col
        end
      end
      local lines = api.nvim_buf_get_lines(buf, start_row, end_row + 1, false)
      for i, line in ipairs(lines) do
        local r = start_row + i - 1
        lines[i] = line:sub((prefixes[r] or 0) + 1, r == end_row and end_col or #line)
      end
      while lines[#lines] == '' do table.remove(lines) end
      return table.concat(lines, '\n') .. '\n'
    end
  end
  return nil, 'Курсор должен быть в блоке mermaid или файле .mmd/.mermaid'
end

return M
