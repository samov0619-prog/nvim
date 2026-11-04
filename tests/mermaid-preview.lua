-- Run: nvim -n --headless -u NONE -i NONE -l tests/mermaid-preview.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp:prepend(root)
vim.o.lines, vim.o.columns = 40, 120
vim.o.swapfile = false
local api = vim.api
local source = require('config.mermaid-preview.source').source
local source_buf = api.nvim_get_current_buf()
local function fixture(lines, row, name)
  api.nvim_set_current_buf(source_buf)
  api.nvim_buf_set_name(source_buf, name or '/virtual/diagram.md')
  api.nvim_buf_set_lines(source_buf, 0, -1, false, lines)
  api.nvim_win_set_cursor(0, { row or 2, 0 })
end
fixture({ '```mermaid', 'flowchart LR', 'A --> B', '```' })
assert(source(source_buf, 2) == 'flowchart LR\nA --> B\n')
assert(source(source_buf, 3) == 'flowchart LR\nA --> B\n', 'Closing fence belongs to block')
fixture({ '````markdown', '```mermaid', 'flowchart LR', 'A --> B', '```', '````' })
assert(source(source_buf, 3) == nil, 'Do not render fences inside an example')
fixture({ '> ```mermaid', '> flowchart LR', '>   A --> B', '> ```' })
assert(source(source_buf, 2) == 'flowchart LR\n  A --> B\n', 'Remove quote prefixes only')
fixture({ '- item', '', '  ```mermaid', '  flowchart LR', '    A --> B', '  ```' }, 4)
assert(source(source_buf, 4) == 'flowchart LR\n  A --> B\n', 'Remove list continuation prefixes')
fixture({ '    ```mermaid', '    flowchart LR', '    A --> B', '    ```' })
assert(source(source_buf, 2) == nil, 'Indented code is not a fence')
fixture({ '~~~mermaid', 'flowchart LR', '  A --> B', '~~~', '', 'After' })
assert(source(source_buf, 1) == 'flowchart LR\n  A --> B\n')
assert(source(source_buf, 5) == nil, 'Do not include following paragraph')
fixture({ '```mermaid', 'flowchart LR', 'A --> B' })
assert(source(source_buf, 2) == 'flowchart LR\nA --> B\n', 'Unclosed fence')
fixture({ '```mermaid', '```' }, 1)
assert(source(source_buf, 0) == nil, 'Empty fence')
fixture({ 'sequenceDiagram', 'Alice->>Bob: Привет' }, 2, '/virtual/diagram.mmd')
assert(source(source_buf, 1) == 'sequenceDiagram\nAlice->>Bob: Привет\n')
-- Avoid populating Neovim's message grid before the headless redraw tests.
io.stdout:write('PASS: Markdown/standalone extraction\n')
dofile(root .. '/tests/mermaid/viewer.lua')
