local M = {}

local function colors()
  local api = vim.api
  local bg = api.nvim_get_hl(0, { name = "Normal", link = false }).bg
  local light = vim.o.background == "light"
  if bg then
    local r, g, b = math.floor(bg / 65536), math.floor(bg / 256) % 256, bg % 256
    light = (299 * r + 587 * g + 114 * b) / 1000 > 128
  end
  -- Separate line and character layers, computed against BASE for each pane.
  api.nvim_set_hl(0, "MergePreviewLine", { bg = light and "#EEF1F7" or "#303844" })
  api.nvim_set_hl(0, "MergePreviewText", { bg = light and "#B8CCE6" or "#4A617D" })
  for _, item in ipairs({ { "Pending", "DiagnosticWarn", "#C99B39" }, { "Resolved", "DiagnosticOk", "#70A85A" } }) do
    local source = api.nvim_get_hl(0, { name = item[2], link = false })
    api.nvim_set_hl(0, "MergePreview" .. item[1] .. "Focus", {
      fg = source.fg or item[3], bg = light and "#DFEAF8" or "#29394D", bold = true,
    })
  end
end

function M.setup()
  colors()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("MergePreviewColors", { clear = true }), callback = colors,
  })
end

-- Visible, zero-based half-open range; keep actual replacement anchors intact.
-- An empty EOF range belongs to the last physical line for all cursor actions.
function M.visible_range(range, count)
  local first = math.max(1, math.min(count, range.first + 1))
  local last = math.max(first, math.min(count, range.last))
  return first - 1, last
end

-- Pure, testable gutter model. Empty ranges mark an insertion point, not a
-- made-up text block. Overlapping anchors retain the first block's identity.
function M.rows(ranges, count)
  local rows = {}
  local ids = {}
  for id in pairs(ranges) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local r = ranges[id]
    local start, last = M.visible_range(r, count)
    local first = start + 1
    for row = first, last do
      local edge = r.first == r.last and "◇" or (first == last and "["
        or (row == first and "┌" or (row == last and "└" or "│")))
      rows[row] = rows[row] or { id = id, edge = edge, first = row == first }
    end
  end
  return rows
end

return M
