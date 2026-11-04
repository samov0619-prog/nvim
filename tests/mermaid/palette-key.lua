local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')
vim.opt.rtp:prepend(root)
local viewer = require('config.mermaid-preview')
local palette = vim.json.decode(vim.env.MERMAID_TEST_PALETTE)
io.write(vim.json.encode({ pipeline = viewer.pipeline_key(), palette = viewer.palette_key(palette),
  lookup = viewer.lookup_key(vim.env.MERMAID_TEST_SOURCE, palette) }))
vim.cmd('qa!')
