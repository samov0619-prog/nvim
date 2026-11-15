-- npm owns dependency resolution/install; this module only bootstraps the locked runtime.
local M = {}
local uv = vim.uv
local manifests = { 'package.json', 'package-lock.json' }

local function signature(root)
  local parts = {}
  for _, name in ipairs(manifests) do
    parts[#parts + 1] = table.concat(vim.fn.readfile(root .. '/' .. name, 'b'), '\n')
  end
  return vim.fn.sha256(table.concat(parts, '\n'))
end

function M.ready(root, data)
  local runtime = data .. '/runtime'
  local marker = runtime .. '/.ready'
  if vim.fn.filereadable(marker) ~= 1 or vim.fn.readfile(marker)[1] ~= signature(root) then return false end
  for _, package in ipairs({ 'puppeteer', 'mermaid', '@mermaid-js/mermaid-cli' }) do
    if vim.fn.filereadable(runtime .. '/node_modules/' .. package .. '/package.json') ~= 1 then return false end
  end
  return true
end

function M.ensure(root, data, progress, complete)
  if M.ready(root, data) then complete(); return end
  if vim.fn.executable('node') ~= 1 or vim.fn.executable('npm') ~= 1 then
    complete('Mermaid setup requires Node.js and npm on PATH. Install them, then reopen the preview.')
    return
  end
  local runtime, lock = data .. '/runtime', data .. '/runtime-install.lock'
  local expected = signature(root)
  local owner = lock .. '/pid'
  local acquired = false
  local function release()
    if acquired then
      vim.fn.delete(owner)
      uv.fs_rmdir(lock)
      acquired = false
    end
  end
  local ok, err = pcall(function()
    vim.fn.mkdir(data, 'p', 448)
    local made, reason = uv.fs_mkdir(lock, 448)
    if not made then
      error('Cannot acquire Mermaid installation lock: ' .. tostring(reason)
        .. '\nAnother Neovim may still be installing. Retry after it finishes.\nLock: ' .. lock, 0)
    end
    acquired = true
    vim.fn.writefile({ tostring(vim.fn.getpid()) }, owner)
    vim.fn.mkdir(runtime, 'p', 448)
    -- Invalidate success before npm ci, which may remove an incomplete node_modules.
    vim.fn.delete(runtime .. '/.ready')
    for _, name in ipairs(manifests) do
      vim.fn.writefile(vim.fn.readfile(root .. '/' .. name, 'b'), runtime .. '/' .. name, 'b')
    end
  end)
  if not ok then release(); complete('Mermaid setup: ' .. tostring(err)); return end
  local cancelled, finished, job, exit_autocmd = false, false, nil, nil
  local output = ''
  local function append(_, chunk)
    if not chunk then return end
    output = (output .. chunk):sub(-6000)
    vim.schedule(function()
      if finished or cancelled then return end
      progress('Installing locked Mermaid dependencies (npm ci)…\nBrowser download and install scripts are disabled.\nq / Esc: cancel\n\n' .. output)
    end)
  end
  progress('Installing locked Mermaid dependencies (npm ci)…\nBrowser download and install scripts are disabled.\nFirst installation needs network access. q / Esc: cancel')
  ok, job = pcall(vim.system, {
    'npm', 'ci', '--prefix', runtime, '--ignore-scripts', '--no-audit', '--no-fund', '--loglevel=info',
  }, {
    cwd = runtime, text = true, timeout = 300000,
    env = { PUPPETEER_SKIP_DOWNLOAD = 'true' }, stdout = append, stderr = append,
  }, function(result)
    vim.schedule(function()
      finished = true
      local failure
      if not cancelled then
        local signal = result.signal or 0
        if result.code ~= 0 or signal ~= 0 then
          failure = 'Mermaid dependency installation failed (exit ' .. tostring(result.code)
            .. ', signal ' .. tostring(signal) .. ').\nReopen the preview to retry.\n\n' .. output
        else
          local saved, save_error = pcall(vim.fn.writefile, { expected }, runtime .. '/.ready')
          if not saved or save_error ~= 0 then failure = 'Cannot record Mermaid installation: ' .. tostring(save_error) end
          if not failure and not M.ready(root, data) then
            vim.fn.delete(runtime .. '/.ready')
            failure = 'npm finished but Mermaid dependencies are incomplete. Reopen the preview to retry.'
          end
        end
      end
      if exit_autocmd then vim.api.nvim_del_autocmd(exit_autocmd); exit_autocmd = nil end
      release()
      if not cancelled then complete(failure) end
    end)
  end)
  if not ok then release(); complete('Cannot start npm: ' .. tostring(job)); return end
  exit_autocmd = vim.api.nvim_create_autocmd('VimLeavePre', { once = true, callback = function()
    exit_autocmd = nil
    cancelled = true
    job:kill(15)
    -- Unlike closing a float, editor exit cannot rely on a scheduled exit callback.
    job:wait(1000)
    release()
  end })
  return { cancel = function()
    if finished or cancelled then return end
    cancelled = true
    job:kill(15)
    -- Keep the lock until npm has actually exited, so a quick reopen cannot race ci.
  end }
end

return M
