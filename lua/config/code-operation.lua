-- A snapshot owns its jobs, requests and cleanup, including after cancellation.
return function(snapshot, source, callback)
  local op = { stopped = false, cancel = {}, cleanup = {} }
  function op.stop()
    if op.stopped then return end
    op.stopped = true
    for cancel in pairs(op.cancel) do pcall(cancel) end
    for _, cleanup in ipairs(op.cleanup) do pcall(cleanup) end
  end
  function op.finish(result, err)
    if op.stopped then return end
    op.stop()
    if snapshot.current() then callback(result, err) end
  end
  function op.fail(message) op.finish(nil, tostring(message)) end
  function op.deadline(ms)
    local timer = vim.defer_fn(function() op.fail(source .. " timed out") end, ms)
    op.cleanup[#op.cleanup + 1] = function()
      if timer and not timer:is_closing() then timer:stop(); timer:close() end
    end
  end
  function op.system(command, opts, next_step, cleanup)
    local process, timer, timed_out
    local function close_timer()
      if timer and not timer:is_closing() then timer:stop(); timer:close() end
    end
    op.cleanup[#op.cleanup + 1] = close_timer
    local cancel = function() if process then process:kill(9) end end
    op.cancel[cancel] = true
    opts = vim.tbl_extend("keep", opts or {}, { text = true, timeout = 10000 })
    local ok, result = pcall(vim.system, command, opts, function(result)
      vim.schedule(function()
        close_timer()
        op.cancel[cancel] = nil
        if not op.stopped then
          if snapshot.current() then
            if timed_out then result.code = 124 end
            local ok, err = pcall(function()
              -- libuv can report code=0 for a process killed by a signal. Its
              -- stdout may be incomplete, regardless of allowed exit codes.
              if (result.signal or 0) ~= 0 then
                local reason = result.code == 124 and " exited with code 124 (timeout), signal "
                  or " terminated by signal "
                op.finish(result, source .. reason .. result.signal)
              else next_step(result) end
            end)
            if not ok then op.fail(source .. " failed: " .. tostring(err)) end
          else op.stop() end
        end
        -- Read successful output first. On cancellation, clean up again after
        -- exit: the process might have held/recreated its temp file when killed.
        if cleanup then pcall(cleanup) end
      end)
    end)
    if ok then
      process = result
      -- vim.system's async timeout sends only SIGTERM, which a tool can
      -- ignore. Wait for its actual exit before reloading any files it wrote.
      timer = vim.defer_fn(function()
        timed_out = true
        pcall(cancel)
      end, opts.timeout)
    else op.cancel[cancel] = nil; op.fail(result) end
  end
  function op.request(client, method, params, next_step)
    local done, id, timer = false, nil, nil
    local cancel = function()
      done = true
      if timer and not timer:is_closing() then timer:stop(); timer:close() end
      if id then client:cancel_request(id) end
    end
    op.cancel[cancel] = true
    local function complete(err, result)
      if done then return end
      done = true
      if timer and not timer:is_closing() then timer:stop(); timer:close() end
      op.cancel[cancel] = nil
      if op.stopped then return end
      if not snapshot.current() then op.stop(); return end
      if err then op.fail(source .. " failed: " .. tostring(err.message or err))
      else
        local ok, err = pcall(next_step, result)
        if not ok then op.fail(source .. " failed: " .. tostring(err)) end
      end
    end
    local ok, sent, request_id = pcall(client.request, client, method, params, complete, snapshot.bufnr)
    id = request_id
    if not ok or not sent then complete({ message = ok and ("Cannot request " .. method) or tostring(sent) })
    elseif not done then
      timer = vim.defer_fn(function()
        complete({ message = method .. " timed out" })
        if id then client:cancel_request(id) end
      end, 4000)
    end
  end
  return op
end
