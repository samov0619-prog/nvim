-- BASE-relative painting and coordinate mapping; no filler or text changes.
local M = {}
local function text(lines) return #lines == 0 and "" or table.concat(lines, "\n") .. "\n" end
local function start(row, count) return count == 0 and row or row - 1 end
local function diff(a, b, whitespace)
  return (vim.text and vim.text.diff or vim.diff)(text(a), text(b), {
    result_type = "indices",
    algorithm = "patience",
    linematch = 120,
    ignore_whitespace = whitespace or false,
  })
end

function M.changes(base, side, whitespace)
  local result = {}
  for _, h in ipairs(diff(base, side, whitespace)) do
    result[#result + 1] = { a = start(h[1], h[2]), an = h[2], b = start(h[3], h[4]), bn = h[4] }
  end
  return result
end

-- Exact outside changed hunks; proportional within an unequal replacement.
-- Whitespace-insensitive maps are used ONLY for scrolling, never highlighting.
function M.map(changes, row, reverse)
  local offset = 0
  for _, h in ipairs(changes) do
    local a, an, b, bn = h.a, h.an, h.b, h.bn
    if reverse then a, an, b, bn = b, bn, a, an end
    if row < a then return row + offset end
    if an > 0 and row < a + an then
      return b + (bn > 0 and math.min(bn - 1, math.floor((row - a) * bn / an)) or 0)
    end
    offset = b + bn - a - an
  end
  return row + offset
end

function M.characters(before, after)
  local old, new = vim.fn.split(before, "\\zs"), vim.fn.split(after, "\\zs")
  local offsets = { [0] = 0 }
  for i, char in ipairs(new) do offsets[i] = offsets[i - 1] + #char end
  local spans = {}
  for _, h in ipairs(diff(old, new)) do
    if h[4] > 0 then
      local first = start(h[3], h[4])
      spans[#spans + 1] = { offsets[first], offsets[first + h[4]] }
    end
  end
  return spans
end

function M.update(s)
  local api = vim.api
  s.diff_data = s.diff_data or {}
  s.deleted = s.deleted or {}
  for kind, buf in pairs(s.buffers) do
    local tick = api.nvim_buf_get_changedtick(buf)
    if not s.diff_data[kind] or s.diff_data[kind].tick ~= tick then
      local current = api.nvim_buf_get_lines(buf, 0, -1, false)
      local changes = M.changes(s.base, current)
      s.diff_data[kind] = { tick = tick, count = #current, scroll = M.changes(s.base, current, true), deleted = {} }
      s.deleted[buf] = s.diff_data[kind].deleted
      api.nvim_buf_clear_namespace(buf, s.paint, 0, -1)
      for _, h in ipairs(changes) do
        if h.bn == 0 then
          s.diff_data[kind].deleted[math.max(1, math.min(#current, h.b + 1))] = true
        end
        for row = h.b, h.b + h.bn - 1 do
          api.nvim_buf_set_extmark(buf, s.paint, row, 0, {
            line_hl_group = "MergePreviewLine", priority = 90,
          })
          -- Refine paired lines; genuinely inserted/unpaired lines keep their
          -- line tint rather than receiving a misleading full-line char tint.
          if h.an == h.bn then
            local before, after = s.base[h.a + row - h.b + 1], current[row + 1]
            if #before + #after <= 4096 then
              for _, span in ipairs(M.characters(before, after)) do
                api.nvim_buf_set_extmark(buf, s.paint, row, span[1], {
                  end_col = span[2], hl_group = "MergePreviewText", priority = 200,
                })
              end
            end
          end
        end
      end
    end
  end
end

-- Pending ordinary changes are proposals against BASE, not yet applied text.
-- Render their BASE ranges in RESULT without inserting the proposed contents.
function M.proposals(s, ranges)
  local api = vim.api
  api.nvim_buf_clear_namespace(s.result, s.proposals, 0, -1)
  local current = api.nvim_buf_get_lines(s.result, 0, -1, false)
  for _, b in ipairs(s.model.blocks) do
    if b.kind == "change" and not s.resolved[b.id] then
      local r = ranges[b.id]
      if r.first == r.last then
        api.nvim_buf_set_extmark(s.result, s.proposals, math.min(r.first, #current - 1), 0, {
          virt_text = { { " + pending change", "DiagnosticInfo" } }, virt_text_pos = "eol",
        })
      end
      for row = r.first, r.last - 1 do
        api.nvim_buf_set_extmark(s.result, s.proposals, row, 0, { line_hl_group = "MergePreviewLine", priority = 90 })
        if r.last - r.first == #b.raw then
          local before, after = b.raw[row - r.first + 1], current[row + 1]
          if #before + #after <= 4096 then
            for _, span in ipairs(M.characters(before, after)) do
              api.nvim_buf_set_extmark(s.result, s.proposals, row, span[1], {
                end_col = span[2], hl_group = "MergePreviewText", priority = 200,
              })
            end
          end
        end
      end
    end
  end
end

return M
