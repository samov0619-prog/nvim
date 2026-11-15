-- Run: nvim -n --headless -u NONE -i NONE -l tests/mermaid/runtime.lua
-- Actual bootstrap/filesystem/UI with simulated npm and renderer; no downloads.
local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')
vim.opt.rtp:prepend(repo)
local directory = '/tmp/opencode/mermaid-runtime-' .. vim.fn.getpid()
assert(vim.fn.isdirectory(directory) == 0)
vim.fn.mkdir(directory .. '/source', 'p', 448)
local source, data = directory .. '/source', directory .. '/data'
for _, name in ipairs({ 'package.json', 'package-lock.json' }) do
  vim.fn.writefile(vim.fn.readfile(repo .. '/scripts/mermaid-preview/' .. name, 'b'), source .. '/' .. name, 'b')
end
local runtime = require('config.mermaid-preview.runtime')
local system, executable = vim.system, vim.fn.executable
local jobs, logs = {}, {}
local viewer
local api = vim.api
local function packages(target)
  for _, name in ipairs({ 'puppeteer', 'mermaid', '@mermaid-js/mermaid-cli' }) do
    local file = target .. '/runtime/node_modules/' .. name .. '/package.json'
    vim.fn.mkdir(vim.fs.dirname(file), 'p', 448)
    vim.fn.writefile({ '{}' }, file)
  end
end
local function finish(job, code, signal)
  job.callback({ code = code, signal = signal or 0, stdout = '', stderr = '' })
  assert(vim.wait(1000, function() return vim.fn.isdirectory(job.target .. '/runtime-install.lock') == 0 end, 10))
end
local ok, err = xpcall(function()
  -- The locked runtime has only Puppeteer's download lifecycle hook. It is safe
  -- to disable scripts; adding a dependency with a required hook needs review.
  local lock = vim.json.decode(table.concat(vim.fn.readfile(source .. '/package-lock.json'), '\n'))
  for name, package in pairs(lock.packages) do
    assert(not package.hasInstallScript or name == 'node_modules/puppeteer', 'Review newly required lifecycle scripts: ' .. name)
  end
  vim.fn.executable = function(name)
    if name == 'node' or name == 'npm' then return 1 end
    return executable(name)
  end
  vim.system = function(cmd, opts, callback)
    local job = { cmd = cmd, opts = opts, callback = callback, killed = false }
    jobs[#jobs + 1] = job
    if cmd[1] == 'npm' then
      assert(cmd[2] == 'ci' and cmd[3] == '--prefix')
      assert(opts.cwd == cmd[4], 'Install outside the currently edited project')
      assert(vim.tbl_contains(cmd, '--ignore-scripts') and vim.tbl_contains(cmd, '--no-audit'))
      assert(opts.env.PUPPETEER_SKIP_DOWNLOAD == 'true' and opts.timeout == 300000)
      job.target = vim.fs.dirname(cmd[4])
    else
      assert(cmd[1] == 'node' and opts.timeout == 45000, 'Only npm setup and existing renderer may run')
    end
    return { kill = function() job.killed = true end }
  end
  local completion, result
  local function ensure()
    completion, result = false, nil
    return runtime.ensure(source, data, function(message) logs[#logs + 1] = message end,
      function(failure) completion, result = true, failure end)
  end
  assert(not runtime.ready(source, data))
  local handle = ensure()
  assert(handle and not completion and #jobs == 1)
  assert(vim.deep_equal(vim.fn.readfile(data .. '/runtime/package-lock.json', 'b'), vim.fn.readfile(source .. '/package-lock.json', 'b')))
  jobs[1].opts.stderr(nil, 'npm http fetch fixture\n')
  assert(vim.wait(1000, function() return (logs[#logs] or ''):find('fetch fixture', 1, true) end))
  local blocked
  runtime.ensure(source, data, function() end, function(failure) blocked = failure end)
  assert(blocked:find('installation lock', 1, true) and #jobs == 1, 'Concurrent ci must not touch the same runtime')
  packages(data)
  finish(jobs[1], 0)
  assert(completion and not result and runtime.ready(source, data))
  assert(not ensure() and completion and not result and #jobs == 1, 'Ready runtime never runs npm again')
  vim.fn.delete(data .. '/runtime/node_modules/mermaid/package.json')
  assert(not runtime.ready(source, data), 'Missing dependency invalidates success')
  handle = ensure()
  handle.cancel()
  assert(jobs[2].killed and vim.fn.isdirectory(data .. '/runtime-install.lock') == 1)
  finish(jobs[2], 143)
  assert(not completion and not runtime.ready(source, data), 'Cancelled install cannot mark success or call back')
  ensure()
  jobs[3].opts.stderr(nil, 'network unavailable')
  finish(jobs[3], 1)
  assert(completion and result:find('network unavailable', 1, true) and not runtime.ready(source, data))
  ensure()
  finish(jobs[4], 0)
  assert(result:find('incomplete', 1, true), 'Successful exit without packages is not success')
  ensure()
  packages(data)
  finish(jobs[5], 0)
  assert(not result and runtime.ready(source, data), 'Retry can complete without manual cleanup')
  vim.fn.writefile({ ' ' }, source .. '/package-lock.json', 'a')
  assert(not runtime.ready(source, data), 'A changed lockfile triggers reinstall')
  ensure()
  -- A second update during npm must not bless the earlier snapshot as current.
  vim.fn.writefile({ ' ' }, source .. '/package-lock.json', 'a')
  finish(jobs[6], 0)
  assert(result and not runtime.ready(source, data))
  -- vim.system may report code=0 with signal=9 for SIGKILL/OOM. Package
  -- manifests can already exist even though npm has not finished installing.
  ensure()
  finish(jobs[#jobs], 0, 9)
  assert(completion and result and result:find('signal 9', 1, true), 'Signaled npm termination is an installation failure')
  assert(not runtime.ready(source, data) and vim.fn.filereadable(data .. '/runtime/.ready') == 0,
    'A killed installer must not mark partial dependencies ready')
  ensure()
  finish(jobs[#jobs], 0)
  assert(completion and not result and runtime.ready(source, data), 'Installation retries after signal termination')
  vim.fn.delete(data .. '/runtime/.ready')
  local spawn = vim.system
  vim.system = function() error('fixture spawn failure') end
  ensure()
  assert(completion and result:find('spawn failure', 1, true))
  assert(vim.fn.isdirectory(data .. '/runtime-install.lock') == 0, 'Spawn failure releases ownership')
  vim.system = spawn
  vim.fn.executable = function(name) if name == 'npm' then return 0 end; return 1 end
  ensure()
  assert(completion and result:find('Node.js and npm', 1, true))
  vim.fn.executable = function() return 1 end

  -- Real float + bootstrap: progress, palette changes, automatic handoff, close.
  local ui_data = directory .. '/ui'
  vim.g.mermaid_preview_data_dir = ui_data
  vim.env.KITTY_WINDOW_ID, vim.env.TMUX = 'fixture', nil
  vim.o.columns, vim.o.lines = 120, 40
  viewer = dofile(repo .. '/lua/config/mermaid-preview.lua')
  viewer.cell_size = function() return { width = 8, height = 16 } end
  viewer.send = function() end
  viewer.browser_executable = function() return '/fixture/google-chrome-stable' end
  viewer.ensure_runtime = function(progress, complete) return runtime.ensure(source, ui_data, progress, complete) end
  vim.bo.filetype = 'mermaid'
  api.nvim_buf_set_lines(0, 0, -1, false, { 'flowchart LR', 'A --> B' })
  local before = #jobs
  viewer.toggle()
  local npm = jobs[#jobs]
  assert(#jobs == before + 1 and npm.cmd[1] == 'npm')
  npm.opts.stdout(nil, 'fixture installation progress')
  assert(vim.wait(1000, function()
    return table.concat(api.nvim_buf_get_lines(0, 0, -1, false), '\n'):find('fixture installation progress', 1, true)
  end))
  api.nvim_set_hl(0, 'NormalFloat', { bg = '#fafafa', fg = '#111111' })
  api.nvim_exec_autocmds('ColorScheme', {})
  vim.wait(150, function() return false end)
  assert(#jobs == before + 1 and not npm.killed, 'Theme changes cannot restart or cancel npm')
  packages(ui_data)
  finish(npm, 0)
  local render = jobs[#jobs]
  assert(render.cmd[1] == 'node' and render.opts.env.MERMAID_CHROMIUM == '/fixture/google-chrome-stable')
  local palette = vim.json.decode(table.concat(vim.fn.readfile(render.cmd[5]), '\n'))
  assert(palette[2] == '#fafafa', 'Render uses the latest theme after installation')
  viewer.close()
  assert(render.killed)
  render.callback({ code = 143, stderr = 'cancelled' })
  vim.wait(30, function() return false end)
  vim.fn.delete(ui_data .. '/runtime/.ready')
  viewer.toggle()
  npm = jobs[#jobs]
  assert(npm.cmd[1] == 'npm')
  viewer.close()
  assert(npm.killed)
  before = #jobs
  finish(npm, 0)
  assert(#jobs == before and not runtime.ready(source, ui_data), 'Late setup completion cannot render or mark cancellation successful')
  viewer.toggle()
  npm = jobs[#jobs]
  npm.opts.stderr(nil, 'fixture registry unavailable')
  before = #jobs
  finish(npm, 1)
  assert(#jobs == before, 'Setup failure must not launch the renderer')
  assert(table.concat(api.nvim_buf_get_lines(0, 0, -1, false), '\n'):find('fixture registry unavailable', 1, true),
    'The preview shows npm errors instead of a module-loading traceback')
  viewer.close()

  -- Exercise native vim.system streaming/exit and the editor-exit hook using a
  -- local npm executable fixture. It only writes package fixtures: no network.
  vim.system, vim.fn.executable = system, executable
  local bin, native_data = directory .. '/bin', directory .. '/native'
  vim.fn.mkdir(bin, 'p', 448)
  local npm_file = bin .. '/npm'
  vim.fn.writefile({ '#!' .. vim.fn.exepath('node'),
    'const fs = require("node:fs");',
    'const path = require("node:path");',
    'const runtime = process.argv[process.argv.indexOf("--prefix") + 1];',
    'console.log("native npm fixture progress");',
    'if (fs.existsSync(' .. vim.json.encode(directory .. '/slow') .. ')) { setInterval(() => {}, 1000); } else {',
    'for (const name of ["puppeteer", "mermaid", "@mermaid-js/mermaid-cli"]) {',
    'const location = path.join(runtime, "node_modules", name); fs.mkdirSync(location, { recursive: true });',
    'fs.writeFileSync(path.join(location, "package.json"), "{}");',
    '}}',
  }, npm_file)
  assert(vim.fn.setfperm(npm_file, 'rwx------') == 1)
  local path = vim.env.PATH
  vim.env.PATH = bin .. ':' .. path
  local native_done, native_error, native_progress = false, nil, ''
  local native_ok, native_error_trace = xpcall(function()
    runtime.ensure(source, native_data, function(message) native_progress = message end,
      function(failure) native_done, native_error = true, failure end)
    assert(vim.wait(5000, function() return native_done end, 10), 'Native bootstrap finishes')
    assert(not native_error and runtime.ready(source, native_data), tostring(native_error))
    assert(native_progress:find('native npm fixture progress', 1, true), 'Native stdout reaches progress UI')
    vim.fn.writefile({ 'slow' }, directory .. '/slow')
    native_done, native_progress = false, ''
    runtime.ensure(source, directory .. '/native-exit', function(message) native_progress = message end,
      function() native_done = true end)
    assert(vim.wait(5000, function() return native_progress:find('native npm fixture progress', 1, true) end, 10))
    api.nvim_exec_autocmds('VimLeavePre', {})
    vim.wait(30, function() return false end)
    assert(not native_done and not runtime.ready(source, directory .. '/native-exit'))
    assert(vim.fn.isdirectory(directory .. '/native-exit/runtime-install.lock') == 0,
      'Editor exit waits for npm termination and releases its lock')
  end, debug.traceback)
  vim.env.PATH = path
  assert(native_ok, native_error_trace)
end, debug.traceback)
if viewer then viewer.close() end
vim.system, vim.fn.executable = system, executable
vim.fn.delete(directory, 'rf')
if not ok then error(err) end
io.stdout:write('PASS: locked runtime bootstrap, no browser downloads/scripts, progress, retry, locking, cancellation, updates and automatic render handoff.\n')
vim.cmd('qa!')
