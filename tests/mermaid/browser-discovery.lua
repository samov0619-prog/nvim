-- Run: nvim -n --headless -u NONE -i NONE -l tests/mermaid/browser-discovery.lua
-- Real executable/PATH checks; macOS discovery uses simulated platform/paths.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')
vim.opt.rtp:prepend(root)
local directory = '/tmp/opencode/mermaid-browser-' .. vim.fn.getpid()
assert(vim.fn.isdirectory(directory) == 0, 'Use a fresh disposable directory')
vim.fn.mkdir(directory, 'p', 448)
vim.g.mermaid_preview_data_dir = directory .. '/data'
local viewer = require('config.mermaid-preview')
local path, override = vim.env.PATH, vim.env.MERMAID_CHROMIUM
local exepath, has = vim.fn.exepath, vim.fn.has
local system = vim.system
local api = vim.api
local ok, err = xpcall(function()
  vim.env.PATH, vim.env.MERMAID_CHROMIUM = directory, nil
  -- Deterministic Linux branch, including when this test runs on macOS.
  vim.fn.has = function(feature) if feature == 'macunix' then return 0 end; return has(feature) end
  vim.system = function() error('Browser discovery must never spawn or download anything') end
  local function executable(name)
    local file = directory .. '/' .. name
    vim.fn.mkdir(vim.fs.dirname(file), 'p', 448)
    vim.fn.writefile({ '#!/bin/sh', 'exit 0' }, file)
    assert(vim.fn.setfperm(file, 'rwx------') == 1)
    return file
  end
  local function selected(expected) assert(viewer.browser_executable() == expected, expected) end
  local missing, message = viewer.browser_executable()
  assert(not missing and message:find('No Chrome/Chromium', 1, true))
  for _, name in ipairs({ 'google-chrome', 'google-chrome-stable', 'chromium-browser', 'chromium' }) do
    selected(executable(name))
  end
  local explicit = executable('custom browser')
  vim.env.MERMAID_CHROMIUM = explicit
  selected(explicit)
  vim.env.MERMAID_CHROMIUM = 'google-chrome-stable'
  selected(directory .. '/google-chrome-stable')
  vim.env.MERMAID_CHROMIUM = directory .. '/missing'
  missing, message = viewer.browser_executable()
  assert(not missing and message:find('MERMAID_CHROMIUM', 1, true), 'Invalid override cannot silently select another browser')
  vim.env.MERMAID_CHROMIUM = ''
  selected(directory .. '/chromium')
  for _, name in ipairs({ 'chromium', 'chromium-browser', 'google-chrome-stable', 'google-chrome' }) do
    vim.fn.delete(directory .. '/' .. name)
  end
  -- Files with spaces exercise actual executable-path handling, not shell parsing.
  local chrome = executable('Google Chrome.app/Contents/MacOS/Google Chrome')
  local chromium = executable('Chromium.app/Contents/MacOS/Chromium')
  local available = {}
  vim.fn.has = function(feature) if feature == 'macunix' then return 1 end; return has(feature) end
  local system_chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
  local system_chromium = '/Applications/Chromium.app/Contents/MacOS/Chromium'
  local user_chrome = vim.fn.expand('~/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
  local user_chromium = vim.fn.expand('~/Applications/Chromium.app/Contents/MacOS/Chromium')
  -- Hide real macOS installations so all branches remain deterministic there.
  vim.fn.exepath = function(candidate)
    if candidate == system_chrome or candidate == system_chromium or candidate == user_chrome or candidate == user_chromium then
      return available[candidate] and exepath(available[candidate]) or ''
    end
    return exepath(candidate)
  end
  for _, entry in ipairs({ { user_chromium, chromium }, { user_chrome, chrome },
    { system_chromium, chromium }, { system_chrome, chrome } }) do
    available[entry[1]] = entry[2]
    selected(entry[2])
  end
  local on_path = executable('google-chrome-stable')
  selected(on_path)
  vim.env.MERMAID_CHROMIUM = chromium
  selected(chromium)
  vim.env.MERMAID_CHROMIUM = nil
  vim.fn.delete(on_path)
  available = {}
  local legacy = executable('data/chromium/bin/chromium')
  selected(legacy)
  vim.fn.delete(legacy)
  -- Exercise the real UI error path, with no Node spawn or temporary request files.
  vim.env.KITTY_WINDOW_ID, vim.env.TMUX = 'fixture', nil
  viewer.cell_size = function() return { width = 8, height = 16 } end
  viewer.send = function() end
  vim.o.columns, vim.o.lines = 120, 40
  vim.bo.filetype = 'mermaid'
  api.nvim_buf_set_lines(0, 0, -1, false, { 'flowchart LR', 'A --> B' })
  viewer.toggle()
  local lines = table.concat(api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  assert(lines:find('No Chrome/Chromium', 1, true), 'Missing browser is reported inside the preview')
  viewer.close()
end, debug.traceback)
viewer.close()
vim.fn.exepath, vim.fn.has, vim.system = exepath, has, system
vim.env.PATH, vim.env.MERMAID_CHROMIUM = path, override
vim.fn.delete(directory, 'rf')
if not ok then error(err) end
io.stdout:write('PASS: browser priority, overrides, Linux PATH, macOS app paths, legacy fallback and missing-browser UI.\n')
vim.cmd('qa!')
