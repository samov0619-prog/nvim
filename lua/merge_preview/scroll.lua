-- Synchronize one visible anchor instead of padding every hunk to equal height.
local M = {}
local api = vim.api
local diff = require("merge_preview.diff")

local function view(win) return api.nvim_win_call(win, vim.fn.winsaveview) end
local function height(win)
  return math.max(1, api.nvim_win_get_height(win) - (vim.wo[win].winbar ~= "" and 1 or 0))
end

-- Cursor/extmarks inside one broad replacement cannot identify unchanged
-- context. Pin it to a model block boundary before changing any buffer text.
local function pin(s, row)
  local previous
  for _, b in ipairs(s.model.blocks) do
    local r = s.ranges.result[b.id]
    if row < r.first then return { id = b.id, edge = "first", offset = row - r.first } end
    if row < r.last or (row == r.first and r.first == r.last) then
      return { id = b.id, offset = row - r.first }
    end
    previous = b.id
  end
  return previous and { id = previous, edge = "last", offset = row - s.ranges.result[previous].last }
      or { offset = row }
end

local function unpin(s, saved)
  local r = saved.id and s.ranges.result[saved.id]
  if not r then return saved.offset end
  if saved.edge then return r[saved.edge] + saved.offset end
  return r.first + math.min(saved.offset, math.max(0, r.last - r.first - 1))
end

function M.capture(s)
  if not s.windows or s.aligning or s.closing or s.disposing or s.anchor_error then return end
  local driver = api.nvim_get_current_win()
  if driver ~= s.windows.result then return end
  local saved = { driver = driver }
  local current = view(driver)
  local cursor, top = current.lnum - 1, current.topline - 1
  local anchor, distance = cursor, math.huge
  for _, b in ipairs(s.model.blocks) do
    if b.kind == "conflict" then
      local r = s.ranges.result[b.id]
      if cursor >= r.first and cursor < math.max(r.first + 1, r.last) then
        anchor = cursor; break
      end
      if r.first >= top and r.first < top + height(driver) and math.abs(r.first - cursor) < distance then
        anchor, distance = r.first, math.abs(r.first - cursor)
      end
    end
  end
  saved.view, saved.cursor, saved.anchor, saved.screen = current, pin(s, cursor), pin(s, anchor), anchor - top
  return saved
end

function M.restore(s, saved)
  if not saved or s.aligning or s.closing or s.disposing or not api.nvim_win_is_valid(saved.driver) then return end
  if saved.view then
    local count = api.nvim_buf_line_count(s.result)
    saved.view.lnum = math.max(1, math.min(count, unpin(s, saved.cursor) + 1))
    saved.view.topline = math.max(1, math.min(count, unpin(s, saved.anchor) + 1 - saved.screen))
    s.aligning = true
    local ok, err = pcall(api.nvim_win_call, saved.driver, function() vim.fn.winrestview(saved.view) end)
    s.aligning = false
    if not ok then vim.notify("Merge preview scroll: " .. tostring(err), vim.log.levels.WARN) end
  end
  M.align(s, saved.driver)
end

function M.align(s, driver)
  if s.aligning or s.laying_out or s.disposing or s.finish_pending or not s.display_ranges
      or not api.nvim_tabpage_is_valid(s.tab) or driver ~= s.windows.result then return end
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
    callback = function()
      if s.aligning or s.laying_out or s.busy or s.closing or api.nvim_get_current_tabpage() ~= s.tab then return end
      local driver = s.windows.result
      if api.nvim_win_is_valid(driver) then
        local top = view(driver).topline
        if top ~= s.scroll_tops[driver] then M.align(s, driver) end
      end
    end,
  })
end

return M
