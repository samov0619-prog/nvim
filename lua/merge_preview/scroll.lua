-- Synchronize one visible anchor instead of padding every hunk to equal height.
local M = {}
local api = vim.api
local diff = require("merge_preview.diff")

local function view(win) return api.nvim_win_call(win, vim.fn.winsaveview) end
local function height(win)
  return math.max(1, api.nvim_win_get_height(win) - (vim.wo[win].winbar ~= "" and 1 or 0))
end

function M.align(s, driver)
  if s.aligning or s.disposing or s.finish_pending or not s.display_ranges or not api.nvim_tabpage_is_valid(s.tab) then return end
  for kind, win in pairs(s.windows) do
    if not api.nvim_win_is_valid(win) or api.nvim_win_get_buf(win) ~= s.buffers[kind] then return end
  end
  local from
  for kind, win in pairs(s.windows) do if win == driver then from = kind end end
  if not from or not s.diff_data[from] then return end
  s.aligning = true
  local ok, err = pcall(function()
    local current = view(driver)
    local top, h = current.topline - 1, height(driver)
    local middle = math.min(s.diff_data[from].count - 1, top + math.floor(h / 2))
    local anchor, chosen, distance = middle, nil, math.huge
    -- Prefer an exact conflict correspondence near the middle of the viewport.
    for id, range in pairs(s.display_ranges[from]) do
      if range.first >= top and range.first < top + h and math.abs(range.first - middle) < distance then
        anchor, chosen, distance = range.first, id, math.abs(range.first - middle)
      end
    end
    local base = diff.map(s.diff_data[from].scroll, anchor, true)
    local screen_offset = anchor - top
    s.scroll_tops[driver] = current.topline
    for kind, win in pairs(s.windows) do
      if win ~= driver and api.nvim_win_is_valid(win) then
        local exact = chosen and s.display_ranges[kind][chosen]
        local target = exact and exact.first or diff.map(s.diff_data[kind].scroll, base)
        local count, size = s.diff_data[kind].count, height(win)
        target = math.max(0, math.min(count - 1, target))
        local first = math.max(0, math.min(math.max(0, count - size), target - screen_offset))
        local saved = view(win)
        if saved.topline ~= first + 1 then
          saved.topline = first + 1
          if saved.lnum < first + 1 or saved.lnum > first + size then
            saved.lnum, saved.col, saved.curswant = target + 1, 0, 0
          end
          api.nvim_win_call(win, function() vim.fn.winrestview(saved) end)
        end
        -- Remember the actual clamped viewport. Its ensuing WinScrolled event
        -- is an echo, not another user's scroll command.
        s.scroll_tops[win] = view(win).topline
      end
    end
  end)
  s.aligning = false
  if not ok then vim.notify("Merge preview scroll: " .. tostring(err), vim.log.levels.WARN) end
end

function M.attach(s, group)
  s.scroll_tops = {}
  for _, win in pairs(s.windows) do s.scroll_tops[win] = view(win).topline end
  api.nvim_create_autocmd("WinScrolled", {
    group = group,
    callback = function(event)
      if s.aligning or s.busy or s.closing or api.nvim_get_current_tabpage() ~= s.tab then return end
      local changed, first = {}, nil
      for _, win in pairs(s.windows) do
        if api.nvim_win_is_valid(win) then
          local top = view(win).topline
          if top ~= s.scroll_tops[win] then changed[win], first = true, first or win end
          s.scroll_tops[win] = top
        end
      end
      local current, reported = api.nvim_get_current_win(), tonumber(event.match)
      local driver = changed[current] and current or (changed[reported] and reported or first)
      if driver then M.align(s, driver) end
    end,
  })
  api.nvim_create_autocmd("WinResized", {
    group = group,
    callback = function()
      if not s.closing and api.nvim_get_current_tabpage() == s.tab then M.align(s, api.nvim_get_current_win()) end
    end,
  })
end

return M
