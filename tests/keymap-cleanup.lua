-- Run: nvim -n --headless -u NONE -i NONE -l tests/keymap-cleanup.lua
-- Exercise configuration registration without booting Lazy, LSP, or external tools.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp:prepend(root)
vim.g.mapleader = ' '

local function plugin(name) return dofile(root .. '/lua/plugins/' .. name .. '.lua')[1] end
local function absent(mode, keys)
  for _, key in ipairs(keys) do
    assert(vim.fn.maparg(key, mode) == '', mode .. ': removed mapping remains: ' .. key)
  end
end
local function present(mode, keys)
  for _, key in ipairs(keys) do
    assert(next(vim.fn.maparg(key, mode, false, true)), mode .. ': retained mapping is missing: ' .. key)
  end
end

dofile(root .. '/lua/config/mapping.lua')
absent('n', {
  ' tn', ' tt', ' th', ' tv', ' tx', ' MY', ' my', ' ul', ' uc', ' dl',
})
absent('t', { '<C-[>', '<C-r>' })
absent('c', { '<C-r>' }) -- Native register insertion must stay unmodified.
present('n', {
  ' tc', ' scr', ' gy', ' do', ' dc', ' dg', ' dp', ' dd', ' rd',
  ' y', ' p', ' cf', ' cx', ' j', ' k', '<C-Space>', '<C-Backspace>', ' fp',
})
present('x', { ' gy', ' y', ' p', ' j', ' k' })
local window_keys = vim.uv.os_uname().sysname == 'Darwin'
    and { '˙', '∆', '˚', '¬' } or { '<A-h>', '<A-j>', '<A-k>', '<A-l>' }
for _, mode in ipairs({ 'n', 'i', 't' }) do present(mode, window_keys) end

local calls = {}
local function action(name)
  return function(...) calls[#calls + 1] = { name, ... } end
end
local gitsigns = {}
for _, name in ipairs({
  'nav_hunk', 'blame_line', 'stage_hunk', 'reset_hunk', 'stage_buffer',
  'preview_hunk_inline', 'diffthis',
}) do gitsigns[name] = action(name) end
gitsigns.setup = function(opts) opts.on_attach(vim.api.nvim_get_current_buf()) end
package.loaded.gitsigns = gitsigns
plugin('gitsigns-nvim').config()
absent('n', { ' hR', ' hi', ' hq', ' hQ', ' tb', ' tw', ' hb', ' bl' })
absent('x', { 'ih' })
absent('o', { 'ih' })
present('n', { '[c', ']c', ' gb', ' hs', ' hr', ' hS', ' hp', ' hd', ' hD' })
present('x', { ' hs', ' hr' })
vim.fn.maparg(' hp', 'n', false, true).callback()
assert(calls[#calls][1] == 'preview_hunk_inline', 'Keep the inline hunk preview')
vim.fn.maparg(' gb', 'n', false, true).callback()
assert(vim.deep_equal(calls[#calls], { 'blame_line', { full = true } }), 'Lowercase gb shows line blame')
package.loaded.blame = { setup = function() end }
plugin('blame-nvim').config()
assert(vim.fn.maparg(' gB', 'n') == '<Cmd>BlameToggle virtual<CR>', 'Uppercase gB keeps whole-file blame')
absent('x', { ' gb', ' gB', ' hi', ' hp' })

local fzf_config
package.loaded['fzf-lua'] = {
  setup = function(opts) fzf_config = opts end,
  register_ui_select = function() end,
  git_status = action('git_status'),
  live_grep = action('live_grep'),
}
package.loaded['fzf-lua.utils'] = { get_visual_selection = function() return 'selected search text' end }
package.loaded['fzf-lua.path'] = {}
package.loaded['mini.files'] = {}
plugin('fzf-lua').config()
absent('n', { ' zxa', ' zxo', ' fg', ' fq', ' fQ', ' fl', ' fL', ' fm', ' fgs', 'z', 'Z' })
absent('x', { ' fg' })
absent('s', { ' fg' })
present('n', { ' z', ' Z', ' fG', ' gs', ' fc', ' fk', ' fd', ' fD' })
present('x', { ' z', ' fG' })
present('s', { ' z', ' fG' })
vim.fn.maparg(' z', 'n', false, true).callback()
assert(vim.deep_equal(calls[#calls], { 'live_grep' }), 'Lowercase z keeps the existing live grep action')
vim.fn.maparg(' z', 'x', false, true).callback()
assert(vim.deep_equal(calls[#calls], { 'live_grep', { search = 'selected search text' } }),
  'Visual z keeps the selected text as the initial search')
assert(vim.fn.maparg(' Z', 'n') == ':FzfLua zoxide<CR>', 'Uppercase Z opens the existing Zoxide picker')
vim.fn.maparg(' gs', 'n', false, true).callback()
assert(calls[#calls][1] == 'git_status', 'gs opens the existing Git status picker')
assert(fzf_config.zoxide.actions.default, 'Keep Zoxide selection actions')
assert(#vim.api.nvim_get_autocmds({ event = 'DirChanged', group = 'ZoxideIntegration' }) == 1,
  'Keep automatic Zoxide directory tracking')

local graph = plugin('gitgraph-nvim')
assert(#graph.keys == 1 and graph.keys[1][1] == '<leader>gp', 'gp is the only dual graph shortcut')
package.loaded.gitgraph = {
  draw_dual = function(...)
    action('draw_dual')(...)
    vim.cmd('tabnew')
    vim.cmd('leftabove vsplit')
  end,
}
graph.keys[1][2]()
assert(vim.deep_equal(calls[#calls], {
  'draw_dual', { commit_info_as_branch_color = true }, { all = true, max_count = 1000 },
}), 'Keep the existing dual graph options')
local graph_width = vim.api.nvim_win_get_width(0)
local text_width = vim.api.nvim_win_get_width(vim.fn.win_getid(vim.fn.winnr('l')))
assert(graph_width == math.floor((vim.o.columns - 1) / 3), 'Give the graph one third of the available width')
assert(text_width == vim.o.columns - 1 - graph_width, 'Give commit details the remaining two thirds')
vim.cmd('tabclose')
-- Register the declared Lazy key for the prefix checks below.
vim.keymap.set('n', graph.keys[1][1], graph.keys[1][2])
local indent
package.loaded['mini.indentscope'] = {
  setup = function(opts) indent = opts end,
  gen_animation = { none = function() return function() end end },
}
plugin('mini-indentscope').config()
for _, name in ipairs({ 'object_scope', 'object_scope_with_border', 'goto_top', 'goto_bottom' }) do
  assert(indent.mappings[name] == '', 'Disable only the indent mapping: ' .. name)
end
assert(indent.symbol == '│', 'Keep the indent visualization')

local parsers
package.loaded['nvim-treesitter.config'] = { get_installed = function() return {} end }
package.loaded['nvim-treesitter'] = { install = function(names) parsers = names end }
local original_start = vim.treesitter.start
vim.treesitter.start = function() end
local treesitter = plugin('nvim-treesitter')
assert(not treesitter.dependencies, 'Remove the textobjects-only dependency and native-map suppression')
treesitter.config()
vim.treesitter.start = original_start
assert(vim.tbl_contains(parsers, 'rust') and vim.tbl_contains(parsers, 'markdown'), 'Keep parser installation configuration')
assert(vim.wo.foldexpr == 'v:lua.vim.treesitter.foldexpr()', 'Keep native Treesitter folding')
assert(vim.bo.indentexpr == "v:lua.require'nvim-treesitter'.indentexpr()", 'Keep Treesitter indentation')
absent('n', { ' a', ' A', ']m', '[m', ']]', '[[', ']i', '[i', 'f', 'F', 't', 'T', ';', ',' })
absent('x', { 'af', 'if', 'ac', 'ic', 'aa', 'ia', 'ai', 'ii', 'ae', 'aO', 'iO' })
absent('o', { 'af', 'if', 'r=', 'l=' })
assert(vim.g.no_plugin_maps == nil, 'Do not suppress native ftplugin mappings anymore')

local fold_config
package.loaded['config.markdown-details'] = { setup = function() end, folds = function() end }
package.loaded.ufo = { setup = function(opts) fold_config = opts end }
plugin('nvim-ufo').config()
absent('n', { 'zR', 'zM', 'K' })
assert(fold_config.close_fold_current_line_for_ft.markdown, 'Keep Markdown folding behavior')

local diff_config
package.loaded['config.diffview-presentation'] = { setup = function() end }
package.loaded['config.code-review'] = { setup = function() end }
package.loaded['config.diffview-updates'] = { setup = function() end }
package.loaded.diffview = { setup = function(opts) diff_config = opts end }
package.loaded.merge_preview = { open = action('merge_open') }
plugin('diffview-nvim').config()
absent('n', { ' gdh', ' gdH', ' gdc', ' gdo', ' gdm', ' gdO', ' gdu' })
present('n', { ' gm', ' gg', ' gO', ' gu' })
assert(vim.fn.maparg(' gg', 'n') == '<Cmd>DiffviewOpen<CR>', 'gg opens Diffview, not the graph')
assert(vim.fn.maparg(' gO', 'n') == '<Cmd>DiffviewOpen origin<CR>', 'gO keeps the origin comparison')
assert(vim.fn.maparg(' gu', 'n') == '<Cmd>DiffviewOpen @{u}<CR>', 'gu keeps the upstream comparison')
vim.fn.maparg(' gm', 'n', false, true).callback()
assert(calls[#calls][1] == 'merge_open', 'gm opens the existing merge resolver')
for _, lhs in ipairs({ '<leader>cf', '<leader>cx' }) do
  local blocked = false
  for _, map in ipairs(diff_config.keymaps.view) do
    if map[2] == lhs and map[3] == '<Nop>' then blocked = true end
  end
  assert(blocked, 'Diff panels must still block ' .. lhs)
end

local blink = plugin('blink')
for _, key in ipairs({ '<C-j>', '<C-k>', '<C-p>', '<C-n>', '<C-y>', '<C-b>', '<C-f>' }) do
  assert(blink.opts.keymap[key] == false, 'Explicitly disable Insert preset key: ' .. key)
end
for _, key in ipairs({ '<C-space>', '<C-n>', '<C-p>', '<Left>', '<C-y>', '<C-e>', '<End>' }) do
  assert(blink.opts.cmdline.keymap[key] == false, 'Explicitly disable cmdline preset key: ' .. key)
end
assert(blink.opts.cmdline.keymap['<C-r>'] == nil, 'Do not intercept native cmdline Ctrl-R')
assert(vim.deep_equal(blink.opts.cmdline.keymap['<Right>'], { 'accept', 'fallback' }), 'Right accepts instead of selecting another candidate')
assert(vim.deep_equal(blink.opts.cmdline.completion.trigger.show_on_x_blocked_trigger_characters, { '/' }), 'Do not reopen completion after accepting a directory')
assert(vim.fn.filereadable(root .. '/lua/plugins/neotab-nvim.lua') == 0, 'Remove Neotab spec')
assert(vim.fn.filereadable(root .. '/lua/plugins/marks-nvim.lua') == 0, 'Remove marks.nvim spec')
assert(vim.fn.filereadable(root .. '/lua/plugins/multicursor-nvim.lua') == 0, 'Remove multicursor spec')
assert(vim.fn.filereadable(root .. '/lua/plugins/zk-nvim.lua') == 0, 'Remove Zk integration without touching notes')

-- A complete shortcut must not be a prefix of another map, globally or locally.
for mode, targets in pairs({
  n = { ' gs', ' hp', ' gm', ' gp', ' gg', ' gO', ' gu', ' z', ' Z' },
  x = { ' z' }, s = { ' z' },
}) do
  for _, keys in ipairs(targets) do
    for _, maps in ipairs({ vim.api.nvim_get_keymap(mode), vim.api.nvim_buf_get_keymap(0, mode) }) do
      for _, map in ipairs(maps) do
        local lhs = vim.keycode(map.lhs)
        assert(#lhs <= #keys or lhs:sub(1, #keys) ~= keys,
          'Complete shortcut would wait for a longer mapping: ' .. keys .. ' -> ' .. map.lhs)
      end
    end
  end
end
print('PASS: removed mappings, retained bindings, native cmdline Ctrl-R, inline preview, and plugin options')
print('PASS: Git and search shortcuts have no longer mapping continuations in their mapped modes')
