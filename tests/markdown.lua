-- Run: nvim -n --headless -u NONE -i NONE -l tests/markdown.lua
local source = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local root = vim.fn.fnamemodify(source, ':h:h')
local case = vim.env.MARKDOWN_TEST_CASE
local fixture = {
  '# Markdown fixture', '',
  '| Name | Description |',
  '| ---- | ----------- |',
  '| First | plain |',
  '| Second | **bold** and a sufficiently long description to wrap inside a narrow table window |',
  '| Third | plain again |', '', 'After the table.',
}
if not case then
  local directory = '/tmp/opencode/markdown-' .. vim.fn.getpid()
  for _, name in ipairs({ 'contract', 'fallback', 'edit', 'minifiles', 'diffview' }) do
    local project = directory .. '/' .. name
    vim.fn.mkdir(project, 'p')
    vim.fn.writefile(fixture, project .. '/README.md')
    local result = vim.system({ vim.v.progpath, '-n', '--headless', '-u', 'NONE', '-i', 'NONE', '-l', source }, {
      text = true, env = { MARKDOWN_TEST_CASE = name, MARKDOWN_TEST_PROJECT = project },
    }):wait(20000)
    assert(result.code == 0, name .. ': ' .. (result.stdout or '') .. (result.stderr or ''))
    print('PASS: ' .. name)
  end
  vim.fn.delete(directory, 'rf')
  print('All Markdown cold-load and table-stripe regression checks passed')
  vim.cmd('qa!')
  return
end

vim.opt.rtp:prepend(root)
vim.o.hidden, vim.o.swapfile = true, false
vim.o.lines, vim.o.columns = 45, 180
local api = vim.api
local project = assert(vim.env.MARKDOWN_TEST_PROJECT)
local notices = {}
vim.notify = function(message, level) notices[#notices + 1] = { message = tostring(message), level = level } end
local function wait(predicate, label)
  assert(vim.wait(7000, predicate, 10), label .. '\n' .. vim.inspect(notices))
end
local function settle() vim.wait(150, function() return false end) end
local stripe = 'RenderMarkdownTableStripe'

if case == 'contract' or case == 'fallback' then
  api.nvim_buf_set_lines(0, 0, -1, false, fixture)
  local tree = vim.treesitter.get_parser(0, 'markdown'):parse()[1]
  local ctx = { buf = api.nvim_get_current_buf(), root = tree:root(), last = true }
  local marks = {
    { conceal = true, start_row = 2, start_col = 0, opts = { virt_text = { { 'header', 'Title' } } } },
    { conceal = true, start_row = 4, start_col = 0, opts = { virt_text = { { 'plain', 'String' } } } },
    { conceal = true, start_row = 5, start_col = 0, opts = { virt_text = { { 'pad', { 'String', 'Bold' } } } } },
    { conceal = true, start_row = 5, start_col = 0, opts = {}, replace = { { { 'wrapped', 'Bold' } } } },
  }
  local original = vim.deepcopy(marks)
  local builtin = { parse = function() return marks end }
  local native_parse = builtin.parse
  package.loaded['render-markdown.handler.markdown'] = builtin
  -- The old adapter asserted here. No private row/wrapped_row API is needed.
  package.loaded['render-markdown.render.markdown.table'] = {}
  local zebra = require('config.markdown-zebra')
  if case == 'contract' then
    local handler = zebra.setup()
    local decorated = handler.parse(ctx)
    assert(vim.deep_equal(marks, original), 'Never mutate the native marks')
    assert(#decorated == #marks + 1 and decorated[#decorated].start_row == 5)
    assert(decorated[#decorated].conceal == true and decorated[#decorated].opts.hl_group == stripe)
    assert(vim.deep_equal(decorated[3].opts.virt_text[1][2], { 'String', 'Bold', stripe }))
    assert(vim.deep_equal(decorated[4].replace[1][1][2], { 'Bold', stripe }))
    assert(vim.deep_equal(decorated[1], original[1]) and vim.deep_equal(decorated[2], original[2]))
    assert(vim.deep_equal(handler.parse(ctx), decorated), 'No duplicate shading on repeated parses')
    assert(type(zebra.setup().parse) == 'function' and builtin.parse == native_parse, 'Never patch the builtin handler')
    api.nvim_set_hl(0, 'Normal', { bg = 0x202020 })
    api.nvim_exec_autocmds('ColorScheme', {})
    local dark = api.nvim_get_hl(0, { name = stripe, link = false })
    vim.o.background = 'light'
    api.nvim_set_hl(0, 'Normal', { bg = 0xffffff })
    api.nvim_exec_autocmds('ColorScheme', {})
    local light = api.nvim_get_hl(0, { name = stripe, link = false })
    assert(dark.bg ~= light.bg and not dark.fg and not light.fg, 'Only the background follows the theme')
    settle()
    assert(#notices == 0, vim.inspect(notices))
  else
    -- Missing builtin entry point: no override, native setup still runs.
    package.loaded['render-markdown.handler.markdown'] = {}
    local setups = 0
    package.loaded['render-markdown'] = { setup = function(opts)
      setups = setups + 1
      assert(opts.custom_handlers.markdown == nil)
    end }
    dofile(root .. '/lua/plugins/render-markdown-nvim.lua')[1].config()
    dofile(root .. '/lua/plugins/render-markdown-nvim.lua')[1].config()
    assert(setups == 2)
    settle()
    assert(#notices == 1 and notices[1].level == vim.log.levels.WARN)
    -- A failed optional transform returns intact builtin marks, once warned.
    local forwarded
    builtin.parse = function(...) forwarded = { ... }; return marks end
    package.loaded['render-markdown.handler.markdown'] = builtin
    local handler = zebra.setup()
    assert(handler.parse({ buf = ctx.buf, root = {} }, 'extra argument') == marks)
    assert(forwarded[2] == 'extra argument', 'Forward the full native handler contract')
    assert(handler.parse(ctx) == marks, 'Disable only stripes after a decoration failure')
    builtin.parse = function() error('native renderer failure') end
    local ok, err = pcall(handler.parse, ctx)
    assert(not ok and tostring(err):find('native renderer failure', 1, true), 'Never swallow native failures')
    settle()
    assert(#notices == 1)
  end
  vim.cmd('qa!')
  return
end

local lazy_root = vim.fn.stdpath('data') .. '/lazy/'
vim.o.loadplugins = true -- -u NONE disables it, which makes lazy.setup a no-op.
vim.opt.rtp:prepend(lazy_root .. 'lazy.nvim')
local spec = dofile(root .. '/lua/plugins/render-markdown-nvim.lua')[1]
local configure, runs, native_options = spec.config, 0, nil
spec.dir = lazy_root .. 'render-markdown.nvim'
spec.config = function(...)
  runs = runs + 1
  local md = require('render-markdown')
  local setup = md.setup
  md.setup = function(opts) native_options = opts; return setup(opts) end
  configure(...)
  md.setup = setup
end
require('lazy').setup({
  spec = {
    spec,
    { 'nvim-treesitter/nvim-treesitter', dir = lazy_root .. 'nvim-treesitter', lazy = true },
    { 'nvim-tree/nvim-web-devicons', dir = lazy_root .. 'nvim-web-devicons', lazy = true },
  },
  root = lazy_root,
  lockfile = project .. '/lazy-lock.json',
  state = project .. '/lazy-state.json',
  install = { missing = false },
  checker = { enabled = false },
  change_detection = { enabled = false },
  readme = { enabled = false },
  rocks = { enabled = false },
  pkg = { enabled = false },
  performance = { reset_packpath = false, rtp = { reset = false } },
})
vim.cmd('filetype on')
assert(runs == 0, 'Markdown must remain unloaded until the first open')
local function add_plugin(name) vim.opt.rtp:append(lazy_root .. name) end
local opener
if case == 'edit' then
  opener = function() vim.cmd.edit(vim.fn.fnameescape(project .. '/README.md')) end
elseif case == 'minifiles' then
  add_plugin('mini.files'); add_plugin('mini.icons')
  dofile(root .. '/lua/plugins/mini-files.lua')[1].config()
  opener = function()
    local mf = require('mini.files')
    mf.open(project .. '/README.md', false)
    vim.fn.maparg('l', 'n', false, true).callback()
    mf.close()
  end
else
  local function git(args)
    local command = { 'git', '-C', project, '-c', 'user.name=Markdown Test', '-c', 'user.email=markdown@example.test' }
    vim.list_extend(command, args)
    local result = vim.system(command, { text = true }):wait(5000)
    assert(result.code == 0, result.stderr)
  end
  git({ 'init', '-q' }); git({ 'add', 'README.md' }); git({ '-c', 'commit.gpgsign=false', 'commit', '-qm', 'base' })
  fixture[1] = '# Changed Markdown fixture'
  vim.fn.writefile(fixture, project .. '/README.md')
  vim.cmd.cd(vim.fn.fnameescape(project))
  add_plugin('diffview.nvim'); add_plugin('plenary.nvim')
  vim.diagnostic.set(api.nvim_create_namespace('markdown-test'), 0, {})
  dofile(root .. '/lua/plugins/diffview-nvim.lua')[1].config()
  require('diffview.config').get_config().watch_index = false
  vim.cmd('runtime plugin/diffview.lua')
  opener = function()
    vim.cmd('DiffviewOpen')
    local view = require('diffview.lib').get_current_view()
    wait(function() return view.initialized and view.cur_entry and view.cur_entry.opened end, 'Open Markdown diff')
  end
end
opener()
wait(function() return runs == 1 and require('render-markdown').initialized end, 'First Markdown configuration')
assert(require('render-markdown').get(), 'Rendering must be enabled after cold load')
local buf = api.nvim_get_current_buf()
if case ~= 'diffview' then
  assert(vim.bo[buf].filetype == 'markdown')
  local md = require('render-markdown')
  local ns = api.nvim_get_namespaces()['render-markdown.nvim']
  local function marks() return api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true }) end
  local function striped()
    for _, mark in ipairs(marks()) do if mark[4].hl_group == stripe then return true end end
    return false
  end
  md.render({ buf = buf })
  wait(striped, 'Visible table stripe')
  local wrapped = false
  for _, mark in ipairs(marks()) do
    for _, line in ipairs(mark[4].virt_lines or {}) do
      for _, chunk in ipairs(line) do
        if type(chunk[2]) == 'table' and vim.tbl_contains(chunk[2], stripe) then wrapped = true end
      end
    end
  end
  assert(wrapped, 'Wrapped virtual rows must keep the stripe too')
  -- Keep native anti-conceal and lifecycle, including virtual wrapped rows.
  settle() -- Let the plugin's native render debounce expire between actions.
  api.nvim_win_set_cursor(0, { 6, 0 })
  md.render({ buf = buf })
  wait(function() return not striped() end, 'Cursor hides the stripe')
  settle()
  api.nvim_win_set_cursor(0, { 1, 0 })
  md.render({ buf = buf })
  wait(striped, 'Stripe returns after cursor leaves')
  settle()
  md.disable()
  wait(function() return #marks() == 0 end, 'Disable clears all rendering')
  settle()
  md.enable()
  wait(striped, 'Enable restores rendering')
  -- A quoted table has native quote marks even when table rendering is off.
  -- Those prefixes must not be mistaken for rendered table cells.
  settle()
  local quoted = vim.deepcopy(fixture)
  for row = 3, 7 do quoted[row] = '> ' .. quoted[row] end
  api.nvim_buf_set_lines(buf, 0, -1, false, quoted)
  vim.bo[buf].modified = false
  md.setup(vim.tbl_deep_extend('force', {}, native_options, { pipe_table = { enabled = false } }))
  md.render({ buf = buf })
  wait(function()
    for _, mark in ipairs(marks()) do
      if mark[2] == 5 and mark[3] == 0 and mark[4].virt_text then return true end
    end
    return false
  end, 'Native quote prefix with disabled table rendering')
  assert(not striped(), 'Disabled nested tables have no stripes')
  settle()
  md.setup(native_options)
  md.render({ buf = buf })
  wait(striped, 'Enabled nested tables regain stripes')
  for _, mark in ipairs(marks()) do
    if mark[2] == 5 and mark[3] < 2 then
      for _, chunk in ipairs(mark[4].virt_text or {}) do
        assert(type(chunk[2]) ~= 'table' or not vim.tbl_contains(chunk[2], stripe), 'Do not shade quote prefixes')
      end
    end
  end
end
if case == 'diffview' then vim.cmd('DiffviewClose') else vim.cmd.enew() end
opener()
settle()
assert(runs == 1, 'Subsequent opens must not rerun configuration')
for _, notice in ipairs(notices) do
  assert(not notice.level or notice.level < vim.log.levels.WARN, vim.inspect(notices))
end
vim.cmd('qa!')
