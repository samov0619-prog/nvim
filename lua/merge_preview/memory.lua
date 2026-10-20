-- Buffer-local conflict definitions, not preview sessions or cN history.
-- Work extmarks track shifts outside conflict spans; changed/ambiguous spans
-- invalidate the memory rather than guessing which text a choice may replace.
local M = {}
local api = vim.api
local model = require("merge_preview.model")
local namespace

local function ns()
  namespace = namespace or api.nvim_create_namespace("MergePreviewConflictMemory")
  return namespace
end

function M.clear(buf)
  vim.b[buf].merge_preview_conflicts = nil
  if namespace and api.nvim_buf_is_loaded(buf) then api.nvim_buf_clear_namespace(buf, namespace, 0, -1) end
end

function M.record(buf, path, key, source, ranges, resolved, working)
  local entries = {}
  for _, b in ipairs(source.blocks) do
    if b.kind == "conflict" then
      local r, raw = assert(ranges[b.id]), {}
      for i = r.first + 1, r.last do raw[#raw + 1] = working[i] end
      entries[#entries + 1] = {
        first = r.first,
        last = r.last,
        raw = raw,
        base = b.base,
        ours = b.ours,
        theirs = b.theirs,
        resolved = resolved[b.id] == true
      }
    end
  end
  M.clear(buf)
  for _, entry in ipairs(entries) do
    entry.mark = api.nvim_buf_set_extmark(buf, ns(), entry.first, 0, {
      end_row = entry.last, right_gravity = false, end_right_gravity = true,
    })
    entry.first, entry.last = nil, nil
  end
  vim.b[buf].merge_preview_conflicts = { path = path, key = key, entries = entries }
end

function M.restore(buf, path, key, working)
  local saved = vim.b[buf].merge_preview_conflicts
  if not saved then return nil end
  if saved.path ~= path or saved.key ~= key then
    M.clear(buf); return nil
  end
  local ok, restored = pcall(function()
    for _, entry in ipairs(saved.entries) do
      local mark = api.nvim_buf_get_extmark_by_id(buf, ns(), entry.mark, { details = true })
      assert(mark[3] and mark[2] == 0 and (mark[3].end_col or 0) == 0, "Lost remembered conflict anchor")
      entry.first, entry.last = mark[1], mark[3].end_row
    end
    return model.restore(working, saved.entries)
  end)
  if ok then return restored end
  M.clear(buf)
end

return M
