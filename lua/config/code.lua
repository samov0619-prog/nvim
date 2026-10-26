local M = {}
local tools = require("config.code-tools")
local running = {}

-- readfile()/writefile() use Vim's line representation, where NUL becomes LF.
-- Fixer stdin, its disk guard and the final write must use the original bytes.
local function read_file(filename)
  local file = assert(io.open(filename, "rb"))
  local source, err = file:read("*a")
  local closed, close_err = file:close()
  assert(source, err)
  assert(closed, close_err)
  return source
end

local function write_file(filename, source)
  local file = assert(io.open(filename, "wb"))
  local written, err = file:write(source)
  local closed, close_err = file:close()
  assert(written, err)
  assert(closed, close_err)
end

local function set_running(bufnr, value)
  running[bufnr] = value
  vim.api.nvim_exec_autocmds("User", {
    pattern = value and "CodeToolsBusy" or "CodeToolsIdle", data = { bufnr = bufnr },
  })
end

function M.is_running(bufnr) return running[bufnr] == true end

local function format_buffer(bufnr, callback)
  local ok = pcall(require, "conform")
  if not ok then
    vim.notify("conform.nvim not available", vim.log.levels.WARN)
    if callback then callback() end
    return
  end
  local completed = false
  local function complete(err)
    if completed then return end
    completed = true
    if err then vim.notify(tostring(err), vim.log.levels.WARN) end
    if callback then callback() end
  end
  local started, err = pcall(function() require("config.code-format").format_buffer(bufnr, complete) end)
  if not started then
    vim.notify("Cannot start formatter: " .. tostring(err), vim.log.levels.ERROR)
    complete(err)
  end
end

function M.format_file()
  local bufnr = vim.api.nvim_get_current_buf()
  if not tools.is_file_buffer(bufnr) or tools.in_review(bufnr) then return end
  if running[bufnr] then
    vim.notify("A code action is already running for this file", vim.log.levels.INFO)
    return
  end
  set_running(bufnr, true)
  format_buffer(bufnr, function() set_running(bufnr, nil) end)
end

local function project_fixers(bufnr)
  local fixers = {}
  for _, selected in ipairs(tools.resolve(bufnr).linters) do
    if selected.cmd and selected.fix_args then fixers[#fixers + 1] = selected end
  end
  return fixers
end

local function same_file(bufnr, filename)
  return tools.is_file_buffer(bufnr)
      and vim.api.nvim_buf_get_name(bufnr) == filename
end

local function finish(bufnr, filename)
  set_running(bufnr, nil)
  if same_file(bufnr, filename) then
    vim.api.nvim_exec_autocmds("User", { pattern = "CodeFixPost", data = { bufnr = bufnr } })
  end
end

local function format_after_fix(bufnr, filename)
  if not same_file(bufnr, filename) or tools.in_review(bufnr) then
    set_running(bufnr, nil)
    return
  end
  format_buffer(bufnr, function() finish(bufnr, filename) end)
end

local function run_cli_fix(bufnr, filename, fixers)
  if not same_file(bufnr, filename) or tools.in_review(bufnr) then
    set_running(bufnr, nil)
    return
  end
  if vim.bo[bufnr].modified then
    vim.notify("File not saved; fix cancelled", vim.log.levels.WARN)
    set_running(bufnr, nil)
    return
  end
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local function unchanged()
    if not same_file(bufnr, filename) or tools.in_review(bufnr) then
      set_running(bufnr, nil)
      return false
    end
    if vim.bo[bufnr].modified or vim.api.nvim_buf_get_changedtick(bufnr) ~= tick then
      vim.notify("Fix finished; buffer changed meanwhile and was not reloaded", vim.log.levels.WARN)
      set_running(bufnr, nil)
      return false
    end
    return true
  end

  local function reload(formatted)
    if not unchanged() then return end
    local ok, err = pcall(vim.api.nvim_buf_call, bufnr, function()
      local view = vim.fn.winsaveview()
      vim.cmd("silent keepalt keepjumps edit")
      vim.fn.winrestview(view)
    end)
    if not ok then
      set_running(bufnr, nil)
      vim.notify("Cannot reload fixed file: " .. tostring(err), vim.log.levels.ERROR)
    elseif formatted then
      finish(bufnr, filename)
    else
      format_after_fix(bufnr, filename)
    end
  end

  local function run(index)
    if not unchanged() then return end
    local fixer = fixers[index]
    if not fixer then
      reload(fixers[#fixers].fix_formats)
      return
    end
    local command = vim.list_extend({ fixer.cmd }, fixer.fix_args)
    local input
    if fixer.fix_stdout then
      local ok, source = pcall(read_file, filename)
      if not ok then
        vim.notify("Cannot read file for " .. fixer.name .. " fixer: " .. tostring(source), vim.log.levels.ERROR)
        set_running(bufnr, nil)
        return
      end
      input = source
    end
    local job = require("config.code-operation")({ current = function() return true end }, fixer.name, function(result, err)
      if err then
        local label = result and (fixer.name .. " fixer failed: ") or ("Cannot start " .. fixer.name .. " fixer: ")
        vim.notify(label .. tostring(err), vim.log.levels.ERROR)
        if result or index > 1 then reload(false) else set_running(bufnr, nil) end
        return
      end
      if fixer.fix_stdout and result.code == 0 then
        if not unchanged() then return end
        local ok, failure = pcall(function()
          assert(read_file(filename) == input, "File changed on disk while fixing")
          assert(type(result.stdout) == "string", "Fixer returned no source text")
          -- Keep the CLI fix-on-disk contract, including exact BOM/newline
          -- bytes. Never let a daemon write the original file itself.
          if result.stdout ~= input then
            write_file(filename, result.stdout)
          end
        end)
        if not ok then
          vim.notify("Cannot apply " .. fixer.name .. " fixes: " .. tostring(failure), vim.log.levels.ERROR)
          set_running(bufnr, nil)
          return
        end
      end
      -- Nonzero exits can still apply safe fixes and leave other errors.
      if result.code ~= 0 then
        local details = {}
        for _, stream in ipairs({ "stderr", "stdout" }) do
          local output = vim.trim(result[stream] or "")
          if output ~= "" then details[#details + 1] = stream .. ":\n" .. output end
        end
        local detail = table.concat(details, "\n\n")
        vim.notify(fixer.name .. " fix exited with code " .. result.code
          .. (detail ~= "" and ("\n" .. detail) or ""), vim.log.levels.WARN)
      else
        vim.notify(fixer.name .. " fixes applied", vim.log.levels.INFO)
      end
      if result.code == 124 then reload(false) else run(index + 1) end
    end)
    job.system(command, { cwd = fixer.cwd, env = fixer.env, timeout = 10000, stdin = input,
      text = not fixer.fix_stdout },
      function(result) job.finish(result) end)
  end
  run(1)
end

local function lsp_fix(bufnr, filename)
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/codeAction" })
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local cancelled = false
  local function unchanged()
    if cancelled then return false end
    if same_file(bufnr, filename) and vim.api.nvim_buf_get_changedtick(bufnr) == tick
        and not tools.in_review(bufnr) then return true end
    cancelled = true
    set_running(bufnr, nil)
    vim.notify("Fix cancelled; buffer changed meanwhile", vim.log.levels.WARN)
    return false
  end

  -- Bound each request and ignore late replies, including after cancellation.
  local function request(client, method, params, callback, command)
    local done, request_id = false, nil
    local check
    local restore = function() end
    if command then
      -- A command may ask the client to apply edits before replying. Accept its
      -- own changes, but reject edits if the user changed this buffer meanwhile.
      local handlers = client.handlers
      -- Keep the guard on its client: it outlives a timed-out request, but must
      -- not retain a stopped client through a module-level registry.
      local state = client._code_tools_fix_guard
      if not state then
        state = { previous = handlers["workspace/applyEdit"], checks = {} }
        local handler = state.previous or vim.lsp.handlers["workspace/applyEdit"]
        state.handler = function(err, result, ctx, config)
          local edit = result and result.edit or {}
          local affected = {}
          for check in pairs(state.checks) do
            local matches = edit.changes and edit.changes[check.uri] ~= nil
            for _, change in ipairs(edit.documentChanges or {}) do
              if change.textDocument and change.textDocument.uri == check.uri then matches = true end
            end
            if matches then
              if check.expired or not check.valid() then
                return { applied = false, failureReason = "Fix cancelled or buffer changed while fixing" }
              end
              affected[#affected + 1] = check
            end
          end
          local response = handler(err, result, ctx, config)
          for _, check in ipairs(affected) do check.updated() end
          return response
        end
        handlers["workspace/applyEdit"] = state.handler
        client._code_tools_fix_guard = state
      end
      check = { uri = vim.uri_from_bufnr(bufnr), valid = unchanged, updated = function()
        if same_file(bufnr, filename) then tick = vim.api.nvim_buf_get_changedtick(bufnr) end
      end }
      state.checks[check] = true
      restore = function()
        state.checks[check] = nil
        if next(state.checks) then return end
        if handlers["workspace/applyEdit"] == state.handler then handlers["workspace/applyEdit"] = state.previous end
        client._code_tools_fix_guard = nil
      end
    end
    local function complete(err, result, timed_out)
      -- Cancellation is advisory. Keep rejecting this command's edits until
      -- the server actually replies, including while the user resumes typing.
      if timed_out and check then check.expired = true else restore() end
      if done then return end
      done = true
      if not unchanged() then return end
      if err then vim.notify(client.name .. ": " .. tostring(err.message or err), vim.log.levels.WARN) end
      callback(err, result)
    end
    -- Neovim passes a context table as the third argument, not our timeout flag.
    local ok, sent, id = pcall(client.request, client, method, params,
      function(err, result) complete(err, result) end, bufnr)
    request_id = id
    if not ok or not sent then
      complete({ message = ok and ("Cannot request " .. method) or tostring(sent) })
      return
    end
    vim.defer_fn(function()
      if done then return end
      complete({ message = method .. " timed out" }, nil, true)
      if request_id then client:cancel_request(request_id) end
    end, 4000)
  end

  local function run_client(index)
    if not unchanged() then return end
    local client = clients[index]
    if not client then
      format_after_fix(bufnr, filename)
      return
    end
    local guard = client._code_tools_fix_guard
    for check in pairs(guard and guard.checks or {}) do
      if check.expired and check.uri == vim.uri_from_bufnr(bufnr) then
        vim.notify(client.name .. ": previous fix command is still cancelling; restart the LSP to retry",
          vim.log.levels.WARN)
        run_client(index + 1)
        return
      end
    end
    local count = vim.api.nvim_buf_line_count(bufnr)
    local last = vim.api.nvim_buf_get_lines(bufnr, count - 1, count, false)[1]
    local params = {
      textDocument = vim.lsp.util.make_text_document_params(bufnr),
      range = { start = { line = 0, character = 0 },
        ["end"] = { line = count - 1, character = vim.str_utfindex(last, client.offset_encoding, #last) } },
      context = { only = { "source.fixAll" }, diagnostics = {}, triggerKind = 1 },
    }
    request(client, "textDocument/codeAction", params, function(_, result)
      local actions = {}
      for _, action in ipairs(result or {}) do
        if not action.disabled and action.kind and
            (action.kind == "source.fixAll" or vim.startswith(action.kind, "source.fixAll.")) then
          -- A server's aggregate fix-all subsumes its individual fix-all kinds.
          if action.kind == "source.fixAll" then actions = { action }; break end
          actions[#actions + 1] = action
        end
      end

      local function run_action(action_index)
        if not unchanged() then return end
        local action = actions[action_index]
        if not action then run_client(index + 1); return end
        local function next_action() run_action(action_index + 1) end
        local function apply(resolved)
          if not unchanged() then return end
          if resolved.edit then
            local ok, err = pcall(vim.lsp.util.apply_workspace_edit, resolved.edit, client.offset_encoding)
            if not ok then vim.notify(tostring(err), vim.log.levels.WARN); next_action(); return end
            tick = vim.api.nvim_buf_get_changedtick(bufnr)
          end
          if not resolved.command then next_action(); return end
          local cmd = type(resolved.command) == "table" and resolved.command or resolved
          local handler = (client.commands or {})[cmd.command] or vim.lsp.commands[cmd.command]
          if handler then
            local ok, err = pcall(handler, cmd, { bufnr = bufnr, client_id = client.id })
            if not ok then vim.notify(tostring(err), vim.log.levels.WARN) end
            tick = vim.api.nvim_buf_get_changedtick(bufnr)
            next_action()
          else
            request(client, "workspace/executeCommand", { command = cmd.command, arguments = cmd.arguments },
              next_action, true)
          end
        end
        if not (action.edit and action.command) and client:supports_method("codeAction/resolve") then
          request(client, "codeAction/resolve", action, function(err, resolved)
            if not err and resolved then apply(resolved)
            elseif action.edit or action.command then apply(action)
            else next_action() end
          end)
        else
          apply(action)
        end
      end
      run_action(1)
    end)
  end
  run_client(1)
end

function M.fix_file()
  local bufnr = vim.api.nvim_get_current_buf()
  if not tools.is_file_buffer(bufnr) or tools.in_review(bufnr) then return end
  if running[bufnr] then
    vim.notify("A code action is already running for this file", vim.log.levels.INFO)
    return
  end
  set_running(bufnr, true)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local fixers = project_fixers(bufnr)
  -- LSP edits the buffer directly, so no save or confirmation is necessary.
  if #fixers == 0 then
    lsp_fix(bufnr, filename)
    return
  end
  if not vim.bo[bufnr].modified then
    run_cli_fix(bufnr, filename, fixers)
    return
  end

  vim.ui.select({ "Save and fix", "Cancel" }, { prompt = "File not saved" }, function(choice)
    if choice ~= "Save and fix" or not same_file(bufnr, filename) or tools.in_review(bufnr) then
      set_running(bufnr, nil)
      return
    end
    local saved, err = pcall(vim.api.nvim_buf_call, bufnr, function() vim.cmd.write() end)
    if not saved or vim.bo[bufnr].modified then
      vim.notify("Failed to save file: " .. tostring(err or "buffer is still modified"), vim.log.levels.ERROR)
      set_running(bufnr, nil)
      return
    end
    run_cli_fix(bufnr, filename, fixers)
  end)
end

return M
