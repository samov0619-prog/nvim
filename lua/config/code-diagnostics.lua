local M = {}
local api = vim.api
local tools = require("config.code-tools")
local checks = require("config.code-checks")
local states = {}
local biome_configs = {}
local max_size = 1024 * 1024

local function cancel(state)
  state.serial = state.serial + 1
  if state.timer and not state.timer:is_closing() then state.timer:stop(); state.timer:close() end
  state.timer = nil
  for _, stop in pairs(state.jobs) do pcall(stop) end
  if next(state.jobs) then state.checked = nil end
  state.jobs = {}
end

local function valid(bufnr)
  return api.nvim_buf_is_valid(bufnr) and api.nvim_buf_is_loaded(bufnr)
      and vim.bo[bufnr].buftype == "" and api.nvim_buf_get_name(bufnr) ~= ""
      and not api.nvim_buf_get_name(bufnr):match("^diffview://")
end

local function stamp(path)
  local stat = path and vim.uv.fs_stat(path)
  return stat and { path = path, size = stat.size, mtime = stat.mtime } or false
end

local function context_key(ctx, bufnr)
  local configs = {}
  for _, tool in ipairs(ctx.linters) do configs[#configs + 1] = stamp(tool.config) end
  if ctx.formatter then configs[#configs + 1] = stamp(ctx.formatter.config) end
  for _, path in ipairs(ctx.config_files or {}) do configs[#configs + 1] = stamp(path) end
  for _, dir in ipairs(ctx.dirs) do configs[#configs + 1] = stamp(vim.fs.joinpath(dir, ".editorconfig")) end
  local clients = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    clients[#clients + 1] = { client.id, client.initialized, client.config.root_dir }
  end
  return { filename = ctx.filename, ft = ctx.ft, linters = ctx.linters, formatter = ctx.formatter,
    configs = configs, disk = stamp(ctx.filename), clients = clients,
    indent = { vim.bo[bufnr].expandtab, vim.bo[bufnr].shiftwidth, vim.bo[bufnr].tabstop },
    eol = vim.bo[bufnr].endofline, server_revision = states[bufnr] and states[bufnr].server_revision }
end

local function busy(bufnr)
  local code = package.loaded["config.code"]
  return code and code.is_running(bufnr)
end

local function run(bufnr, state)
  if not valid(bufnr) or tools.in_review(bufnr) or busy(bufnr) or vim.fn.mode():match("^[iR]") then return end
  local lint = require("lint")
  local ctx = tools.resolve(bufnr)
  local tick = api.nvim_buf_get_changedtick(bufnr)
  local key = context_key(ctx, bufnr)
  if not state.force and state.checked and state.checked.tick == tick and vim.deep_equal(state.checked.key, key) then
    return
  end
  state.force = false

  local selected, biome = {}, nil
  for _, tool in ipairs(ctx.linters) do
    if tool.id == "biomejs" then biome = tool end
    selected[tool.id] = true
  end
  if not biome then selected[ctx.formatter and ctx.formatter.id or "format"] = true end
  for id in pairs(state.sources) do
    if not selected[id] then vim.diagnostic.reset(lint.get_namespace(id), bufnr) end
  end
  state.sources = selected
  if api.nvim_buf_get_offset(bufnr, api.nvim_buf_line_count(bufnr)) > max_size then
    for id in pairs(selected) do vim.diagnostic.reset(lint.get_namespace(id), bufnr) end
    return
  end

  local snapshot = { bufnr = bufnr, filename = ctx.filename, tick = tick,
    lines = api.nvim_buf_get_lines(bufnr, 0, -1, false), eol = vim.bo[bufnr].endofline, offsets = { 0 } }
  snapshot.source = table.concat(snapshot.lines, "\n") .. (snapshot.eol and "\n" or "")
  for i = 2, #snapshot.lines do snapshot.offsets[i] = snapshot.offsets[i - 1] + #snapshot.lines[i - 1] + 1 end
  local serial = state.serial
  snapshot.current = function()
    return states[bufnr] == state and state.serial == serial and valid(bufnr) and not tools.in_review(bufnr)
        and api.nvim_buf_get_changedtick(bufnr) == tick
        and vim.deep_equal(context_key(tools.resolve(bufnr), bufnr), key)
  end

  local jobs = {}
  local function add(id, start) jobs[#jobs + 1] = { id = id, start = start } end
  for _, tool in ipairs(ctx.linters) do
    if tool.id == "biomejs" then
      local client
      for _, candidate in ipairs(vim.lsp.get_clients({ bufnr = bufnr, name = "biome" })) do
        if candidate.initialized and tools.biome_client_matches(candidate, ctx.lsp.biome) then
          client = candidate
          break
        end
      end
      if client then
        local config = { stamp(tool.config), stamp(vim.fs.joinpath(tool.cwd, ".editorconfig")) }
        if not vim.deep_equal(biome_configs[client.id], config) then
          biome_configs[client.id] = config
          client:notify("workspace/didChangeWatchedFiles", {
            changes = { { uri = vim.uri_from_fname(tool.config), type = 2 } },
          })
        end
        add(tool.id, function(done) return checks.biome(ctx, snapshot, client, done) end)
      elseif tool.cmd and not vim.bo[bufnr].modified and vim.fn.filereadable(ctx.filename) == 1 then
        -- Initial diagnostics remain available while the LSP is starting.
        add(tool.id, function(done)
          return checks.linter(tool, lint.linters[tool.id](), snapshot, done)
        end)
      else
        add(tool.id, function(done) return checks.format(ctx, snapshot, done) end)
      end
    elseif tool.cmd then
      add(tool.id, function(done)
        if tool.id == "phpstan" then return checks.phpstan(tool, snapshot, done) end
        return checks.linter(tool, lint.linters[tool.id](), snapshot, done)
      end)
    else
      vim.diagnostic.reset(lint.get_namespace(tool.id), bufnr)
    end
  end
  if not biome then
    add(ctx.formatter and ctx.formatter.id or "format", function(done) return checks.format(ctx, snapshot, done) end)
  end

  local remaining = #jobs
  api.nvim_buf_call(bufnr, function()
    for _, job in ipairs(jobs) do
      local completed = false
      local function done(diagnostics)
        if completed or not snapshot.current() then return end
        completed = true
        state.jobs[job.id] = nil
        vim.diagnostic.set(lint.get_namespace(job.id), bufnr, diagnostics)
        remaining = remaining - 1
        if remaining == 0 then state.checked = { tick = tick, key = key } end
      end
      local ok, stop = pcall(job.start, done)
      if not ok then done({ { lnum = 0, col = 0, source = job.id,
        severity = vim.diagnostic.severity.ERROR, message = tostring(stop) } })
      elseif not completed then state.jobs[job.id] = stop end
    end
  end)
end

function M.biome_changed(params, context)
  local bufnr = vim.fn.bufnr(vim.uri_to_fname(params.uri))
  if not valid(bufnr) or not vim.lsp.buf_is_attached(bufnr, context.client_id) then return end
  local version = vim.lsp.util.buf_versions[bufnr]
  if type(params.version) == "number" and version and params.version < version then return end
  if not states[bufnr] then M.refresh(bufnr, false, 0) end
  local state = states[bufnr]
  -- Native notifications signal completed settings reloads as well as edits.
  -- Re-query the full API (with enforced assists), rather than publishing the
  -- native subset or leaving cached results from before a config reload.
  state.server_revision = (state.server_revision or 0) + 1
  M.refresh(bufnr, true, 150)
end

function M.refresh(bufnr, force, delay)
  if not valid(bufnr) then return end
  local state = states[bufnr]
  if not state then state = { serial = 0, jobs = {}, sources = {} }; states[bufnr] = state end
  cancel(state)
  state.force = state.force or force
  if tools.in_review(bufnr) or busy(bufnr) or vim.fn.mode():match("^[iR]") then return end
  state.timer = vim.defer_fn(function()
    state.timer = nil
    run(bufnr, state)
  end, delay or 0)
end

function M.setup()
  require("config.code-review").setup()
  for _, state in pairs(states) do cancel(state) end
  states = {}
  biome_configs = {}
  local group = api.nvim_create_augroup("CodeDiagnostics", { clear = true })
  -- In Insert mode keep the last displayed diagnostics, but invalidate work
  -- immediately. InsertLeave checks the final buffer, including unsaved edits.
  api.nvim_create_autocmd({ "InsertEnter", "TextChangedI", "TextChangedP" }, {
    group = group, callback = function(args) if states[args.buf] then cancel(states[args.buf]) end end,
  })
  api.nvim_create_autocmd("TextChanged", {
    group = group, callback = function(args) M.refresh(args.buf, false, 150) end,
  })
  api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufEnter", "FileType", "InsertLeave", "BufFilePost",
    "BufWritePost", "FocusGained", "LspAttach", "LspDetach" }, {
    group = group, callback = function(args)
      M.refresh(args.buf, args.event == "BufWritePost" or args.event == "LspAttach", 0)
    end,
  })
  api.nvim_create_autocmd("User", {
    group = group, pattern = { "CodeToolsBusy", "CodeToolsIdle", "CodeFixPost" }, callback = function(args)
      M.refresh(args.data.bufnr, args.match ~= "CodeToolsBusy", 0)
    end,
  })
  api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
    group = group, callback = function(args)
      if states[args.buf] then cancel(states[args.buf]); states[args.buf] = nil end
    end,
  })
  for _, bufnr in ipairs(api.nvim_list_bufs()) do M.refresh(bufnr, false, 0) end
end

return M
