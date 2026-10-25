local M = {}
local api = vim.api
local operation = require("config.code-operation")

local function output_lines(output, eol)
  local lines = vim.split(output:gsub("\r\n", "\n"), "\n", { plain = true })
  if eol and lines[#lines] == "" then table.remove(lines) end
  return #lines > 0 and lines or { "" }
end

-- Conform selects and builds formatter commands; this executor owns their
-- lifetime. Its async APIs have neither a deadline nor a cancellation handle.
function M.run(snapshot, opts, callback)
  local conform = require("conform")
  local runner = require("conform.runner")
  local op = operation(snapshot, "Formatting", function(lines, err) callback(err, lines) end)
  op.deadline(opts.timeout_ms or 10000)

  local function apply(lines)
    if not opts.apply then return end
    local bufnr = snapshot.bufnr
    if not api.nvim_buf_is_valid(bufnr) or not api.nvim_buf_is_loaded(bufnr)
        or api.nvim_buf_get_name(bufnr) ~= snapshot.filename
        or api.nvim_buf_get_changedtick(bufnr) ~= snapshot.tick
        or require("config.code-tools").in_review(bufnr) then
      error("Formatting cancelled; buffer changed or entered a review view")
    end
    runner.apply_format(bufnr, snapshot.lines, lines, nil, false, false, false)
    snapshot.lines = lines
    snapshot.tick = api.nvim_buf_get_changedtick(bufnr)
  end
  local function finish(lines)
    apply(lines)
    op.finish(lines)
  end
  local function start()
    local formatters, lsp = conform.list_formatters_to_run(snapshot.bufnr)
    if #formatters == 0 then
      if not lsp then op.fail("No formatters available for buffer"); return end
      local clients = require("conform.lsp_format").get_format_clients({ bufnr = snapshot.bufnr })
      local function next_client(index, lines)
        if op.stopped then return end
        local client = clients[index]
        if not client then finish(lines); return end
        local params = api.nvim_buf_call(snapshot.bufnr, function()
          return vim.lsp.util.make_formatting_params()
        end)
        op.request(client, "textDocument/formatting", params, function(edits)
          -- Apply to a scratch buffer first: checks never edit the live buffer,
          -- and a late reply cannot apply anything after cancellation/timeout.
          local scratch = api.nvim_create_buf(false, true)
          local function cleanup()
            if api.nvim_buf_is_valid(scratch) then api.nvim_buf_delete(scratch, { force = true }) end
          end
          op.cleanup[#op.cleanup + 1] = cleanup
          api.nvim_buf_set_lines(scratch, 0, -1, false, lines)
          vim.lsp.util.apply_text_edits(edits or {}, scratch, client.offset_encoding)
          local formatted = api.nvim_buf_get_lines(scratch, 0, -1, false)
          cleanup()
          if not opts.apply and not vim.deep_equal(formatted, lines) then op.finish(formatted); return end
          apply(formatted)
          next_client(index + 1, formatted)
        end)
      end
      next_client(1, snapshot.lines)
      return
    end

    local function next_formatter(index, lines)
      if op.stopped then return end
      local formatter = formatters[index]
      if not formatter then finish(lines); return end
      local config = assert(conform.get_formatter_config(formatter.name, snapshot.bufnr))
      local ctx = runner.build_context(snapshot.bufnr, config)
      if config.format then
        local completed = false
        config.format(config, ctx, vim.deepcopy(lines), function(err, formatted)
          if completed or op.stopped then return end
          completed = true
          local ok, failure = pcall(function()
            if err then op.fail(err) else next_formatter(index + 1, formatted) end
          end)
          if not ok then op.fail(failure) end
        end)
        return
      end
      local command = runner.build_cmd(formatter.name, ctx, config)
      local cwd = config.cwd and config.cwd(config, ctx)
      local env = type(config.env) == "function" and config.env(config, ctx) or config.env
      local source = table.concat(lines, "\n") .. (snapshot.eol and "\n" or "")
      local temporary = not config.stdin and ctx.filename or nil
      local function cleanup() if temporary then vim.fn.delete(temporary) end end
      if temporary then
        op.cleanup[#op.cleanup + 1] = cleanup
        -- Keep the temp file beside the original, preserving tool path/config
        -- semantics; never pass the original to a file-writing formatter.
        vim.fn.writefile(lines, temporary, snapshot.eol and "" or "b")
      end
      op.system(command, { cwd = cwd, env = env, stdin = config.stdin and source or nil }, function(result)
        if not vim.tbl_contains(config.exit_codes or { 0 }, result.code) then
          op.fail(formatter.name .. " failed: " .. vim.trim((result.stderr or "") .. "\n" .. (result.stdout or "")))
          return
        end
        local output = result.stdout or ""
        if temporary then output = table.concat(vim.fn.readfile(temporary, "b"), "\n") end
        next_formatter(index + 1, output_lines(output, snapshot.eol))
      end, cleanup)
    end
    next_formatter(1, snapshot.lines)
  end
  local ok, err = pcall(start)
  if not ok then op.fail(err) end
  return op.stop
end

function M.format_buffer(bufnr, callback)
  return M.run({ bufnr = bufnr, filename = api.nvim_buf_get_name(bufnr),
    tick = api.nvim_buf_get_changedtick(bufnr), lines = api.nvim_buf_get_lines(bufnr, 0, -1, false),
    eol = vim.bo[bufnr].endofline, current = function() return true end,
  }, { apply = true, timeout_ms = 4000 }, callback)
end

return M
