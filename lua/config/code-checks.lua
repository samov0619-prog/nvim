local M = {}
local severity = vim.diagnostic.severity
local phpstan_editor = {}
local create_operation = require("config.code-operation")

local function failure(source, message)
  return { { source = source, lnum = 0, col = 0, severity = severity.ERROR, message = tostring(message) } }
end

local function operation(snapshot, source, callback)
  return create_operation(snapshot, source, function(diagnostics, err)
    callback(err and failure(source, err) or diagnostics)
  end)
end

local function position(snapshot, offset)
  offset = math.max(0, math.min(offset or 0, #snapshot.source))
  local low, high = 1, #snapshot.offsets
  while low < high do
    local middle = math.floor((low + high + 1) / 2)
    if snapshot.offsets[middle] <= offset then low = middle else high = middle - 1 end
  end
  return low - 1, math.min(offset - snapshot.offsets[low], #snapshot.lines[low])
end

local function format_diagnostics(snapshot, output, source)
  local diagnostics = {}
  -- Compare logical lines, like Conform: line-ending/EOF metadata is not an
  -- editable buffer line and must not leave warnings that cf cannot clear.
  local lines = vim.split(output:gsub("\r\n", "\n"), "\n", { plain = true })
  if lines[#lines] == "" then table.remove(lines) end
  local original = table.concat(snapshot.lines, "\n") .. "\n"
  local formatted = table.concat(lines, "\n") .. "\n"
  for _, hunk in ipairs(vim.diff(original, formatted, { result_type = "indices" })) do
    local line = math.max(0, math.min(hunk[1] - 1, #snapshot.lines - 1))
    diagnostics[#diagnostics + 1] = {
      source = source, code = "format", severity = severity.WARN,
      lnum = line, col = 0, end_lnum = math.min(line + math.max(hunk[2], 1) - 1, #snapshot.lines - 1),
      message = "Formatting differs from project settings; use <leader>cf",
    }
  end
  return diagnostics
end

function M.format(ctx, snapshot, callback)
  local tool = ctx.formatter
  local source = tool and tool.id or "format"
  local op = operation(snapshot, source, callback)
  if tool and tool.cmd then
    op.system(vim.list_extend({ tool.cmd }, tool.args), { cwd = tool.cwd, stdin = snapshot.source }, function(result)
      if result.code == 0 then op.finish(format_diagnostics(snapshot, result.stdout, source))
      elseif source == "biome" and (result.stderr or ""):find("The file was ignored", 1, true) then op.finish({})
      else op.fail((tool.name or source) .. " check failed: " .. vim.trim(result.stderr .. "\n" .. result.stdout)) end
    end)
  else
    local ok = pcall(require, "conform")
    if not ok then op.finish({}); return op.stop end
    local cancel = require("config.code-format").run(snapshot, {}, function(err, lines)
      if err == "No formatters available for buffer" then op.finish({})
      elseif err then op.fail(err)
      else op.finish(format_diagnostics(snapshot, table.concat(lines, "\n") .. (snapshot.eol and "\n" or ""), source)) end
    end)
    if not op.stopped then op.cancel[cancel] = true end
  end
  return op.stop
end

function M.biome(ctx, snapshot, client, callback)
  local op = operation(snapshot, "biomejs", callback)
  -- The LSP workspace may be narrowed to a package's binary installation.
  -- Open the actual config root so ancestor config reloads update this project.
  op.request(client, "biome/open_project", {
    path = vim.fs.dirname(ctx.lsp.biome.config), openUninitialized = false,
  }, function(project)
    local params = { projectKey = project.projectKey, path = ctx.filename, features = {} }
    op.request(client, "biome/file_features", params, function(result)
      local features = result.featuresSupported
      local categories = { "syntax" }
      if features.lint == "supported" and ctx.linter.id ~= "stylelint" then categories[#categories + 1] = "lint" end
      if features.assist == "supported" then categories[#categories + 1] = "action" end
      if #categories == 1 and features.format ~= "supported" then op.finish({}); return end
      op.request(client, "biome/process_file", {
        projectKey = project.projectKey, path = ctx.filename,
        content = { type = "fromClient", content = snapshot.source, version = snapshot.tick },
        categories = categories, format = false, write = false, includeCodeFix = false,
        diagnosticLevel = "hint", enforceAssist = true, skipParseErrors = false,
      }, function(result)
        local diagnostics = {}
        for _, item in ipairs(result.diagnostics) do
          local span = item.location and item.location.span
          local lnum, col = position(snapshot, type(span) == "table" and span[1] or 0)
          local end_lnum, end_col = position(snapshot, type(span) == "table" and span[2] or 0)
          diagnostics[#diagnostics + 1] = {
            source = "biomejs", code = type(item.category) == "string" and item.category or nil,
            message = item.description,
            severity = ({ fatal = severity.ERROR, error = severity.ERROR, warning = severity.WARN,
              info = severity.INFO, hint = severity.HINT })[item.severity] or severity.WARN,
            lnum = lnum, col = col, end_lnum = end_lnum, end_col = end_col,
          }
        end
        if features.format ~= "supported" or result.parseErrors > 0 then op.finish(diagnostics); return end
        local cancel = M.format(ctx, snapshot, function(formatting)
          for _, diagnostic in ipairs(formatting) do diagnostic.source = "biomejs" end
          op.finish(vim.list_extend(diagnostics, formatting))
        end)
        if not op.stopped then op.cancel[cancel] = true end
      end)
    end)
  end)
  return op.stop
end

function M.linter(tool, definition, snapshot, callback)
  local op = operation(snapshot, tool.id, callback)
  local args = vim.deepcopy(definition.args)
  if not definition.stdin and definition.append_fname ~= false then args[#args + 1] = snapshot.filename end
  op.system(vim.list_extend({ tool.cmd }, args), {
    cwd = tool.cwd, env = tool.env, stdin = definition.stdin and snapshot.source or nil,
  }, function(result)
    local output = definition.stream == "stderr" and result.stderr or result.stdout
    if definition.stream == "both" then output = result.stdout .. result.stderr end
    local ok, diagnostics = pcall(definition.parser, output, snapshot.bufnr, tool.cwd)
    if ok and result.code > 1 and #diagnostics == 0 then
      op.fail(tool.name .. " check failed: " .. vim.trim(result.stderr .. "\n" .. result.stdout))
    elseif ok then op.finish(diagnostics)
    else op.fail(tool.name .. " check failed: " .. tostring(diagnostics)) end
  end)
  return op.stop
end

function M.phpstan(tool, snapshot, callback)
  local op = operation(snapshot, tool.id, callback)
  local function analyse(editor)
    local args, temporary = vim.deepcopy(tool.args), nil
    if editor then
      temporary = vim.fn.tempname() .. ".php"
      op.cleanup[#op.cleanup + 1] = function() vim.fn.delete(temporary) end
      local ok, err = pcall(vim.fn.writefile, snapshot.lines, temporary, snapshot.eol and "" or "b")
      if not ok then op.fail(err); return end
      vim.list_extend(args, { "--tmp-file", temporary, "--instead-of", snapshot.filename })
    end
    args[#args + 1] = snapshot.filename
    op.system(vim.list_extend({ tool.cmd }, args), { cwd = tool.cwd, timeout = 60000 }, function(result)
      local ok, decoded = pcall(vim.json.decode, result.stdout)
      if not ok or type(decoded) ~= "table" or type(decoded.files) ~= "table" then
        op.fail("PHPStan check failed: " .. vim.trim(result.stderr .. result.stdout)); return
      end
      local diagnostics = {}
      for _, message in ipairs(decoded.errors or {}) do
        vim.list_extend(diagnostics, failure(tool.id, message))
      end
      local file = decoded.files[snapshot.filename] or (temporary and decoded.files[temporary]) or {}
      for _, message in ipairs(file.messages or {}) do
        diagnostics[#diagnostics + 1] = { source = tool.id,
          code = type(message.identifier) == "string" and message.identifier or nil,
          lnum = type(message.line) == "number" and math.max(message.line - 1, 0) or 0,
          col = 0, severity = severity.ERROR, message = message.message }
      end
      op.finish(diagnostics)
    end)
  end
  if not vim.bo[snapshot.bufnr].modified and vim.fn.filereadable(snapshot.filename) == 1 then analyse(false)
  elseif phpstan_editor[tool.cmd] ~= nil then
    if phpstan_editor[tool.cmd] then analyse(true) else op.finish({}) end
  else
    op.system({ tool.cmd, "analyse", "--help" }, { cwd = tool.cwd }, function(result)
      local help = result.stdout .. result.stderr
      local supported = result.code == 0 and help:find("--tmp-file", 1, true) and help:find("--instead-of", 1, true)
      phpstan_editor[tool.cmd] = not not supported
      -- TODO: PHPStan older than 2.1.17/1.12.27 has no editor mode. Keep its
      -- saved-file checks; avoid analysing a changed buffer as an unrelated file.
      if supported then analyse(true) else op.finish({}) end
    end)
  end
  return op.stop
end

return M
