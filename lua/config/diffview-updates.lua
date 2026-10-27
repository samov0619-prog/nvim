local M = {}
local installed = false

function M.setup()
  if installed then return end
  installed = true
  local DiffView = require("diffview.scene.views.diff.diff_view").DiffView
  local update = DiffView.update_files
  local queue, pending = {}, {}
  local running, scheduled = false, false
  local drain
  local function schedule()
    if scheduled then return end
    scheduled = true
    vim.schedule(function()
      scheduled = false
      drain()
    end)
  end
  local function finish(request, err)
    running = false
    for _, callback in ipairs(request.callbacks) do
      vim.schedule(function() callback(err) end)
    end
    schedule()
  end
  drain = function()
    if running or #queue == 0 then return end
    local request = table.remove(queue, 1)
    local view = request.view
    pending[view] = nil
    if view.closing:check() or not vim.api.nvim_tabpage_is_valid(view.tabpage) then
      finish(request, { "The update was cancelled: view closed." })
      return
    end
    running = true
    update(view, function(err) finish(request, err) end)
  end

  -- Upstream's 100ms debounce does not serialize async refreshes. In addition,
  -- synchronous Git jobs can pump the event loop while the edit script is
  -- mutating self.files. A nested refresh then invalidates the outer script.
  -- Keep the lock until the completion callback, not merely until Git returns.
  -- The upstream debouncer is shared by all views, so serialize across views
  -- too: otherwise it can replace one view's request/callback with another's.
  DiffView.update_files = function(view, callback)
    local request = pending[view]
    if not request then
      request = { view = view, callbacks = {} }
      pending[view] = request
      queue[#queue + 1] = request
    end
    if callback then request.callbacks[#request.callbacks + 1] = callback end
    if not running then schedule() end
  end
end

return M
