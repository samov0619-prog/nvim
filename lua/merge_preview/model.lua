-- Pure model: preserve every unresolved region byte-for-byte (as buffer lines).
local M = {}
local function append(dst, src)
  for _, line in ipairs(src) do dst[#dst + 1] = line end
end

function M.parse(lines)
  local model = { parts = {}, blocks = {} }
  local plain, block, section, width = {}, nil, nil, nil
  for _, line in ipairs(lines) do
    local marker = line:match("^(<<<<<<<[<]*)")
    if marker then
      assert(not block, "Nested conflict markers are not supported")
      model.parts[#model.parts + 1] = { lines = plain }
      plain = {}
      block = { id = #model.blocks + 1, kind = "conflict", raw = {}, ours = {}, base = {}, theirs = {} }
      model.blocks[#model.blocks + 1] = block
      model.parts[#model.parts + 1] = { block = block }
      section, width = "ours", #marker
      block.raw[#block.raw + 1] = line
    elseif block then
      block.raw[#block.raw + 1] = line
      if line:sub(1, width) == string.rep("|", width) then
        assert(section == "ours", "Invalid BASE marker")
        block.has_base, section = true, "base"
      elseif line == string.rep("=", width) then
        assert(section ~= "theirs", "Duplicate separator")
        section = "theirs"
      elseif line:sub(1, width) == string.rep(">", width) then
        assert(section == "theirs", "Missing conflict separator")
        block, section = nil, nil
      else
        block[section][#block[section] + 1] = line
      end
    else
      plain[#plain + 1] = line
    end
  end
  assert(not block, "Unclosed conflict marker")
  model.parts[#model.parts + 1] = { lines = plain }
  return model
end

function M.project(model, side)
  local lines, ranges = {}, {}
  for _, part in ipairs(model.parts) do
    if part.block then
      local b = part.block
      local content = side == "result" and (b.initial_result or (b.has_base and b.base or b.ours)) or b[side]
      if b.kind == "change" and (side == "ours" or side == "theirs") then content = b.raw end
      ranges[b.id] = { first = #lines, last = #lines + #content }
      append(lines, content)
    else
      append(lines, part.lines)
    end
  end
  return lines, ranges
end

function M.serialize(model, preview, ranges, resolved, work_ranges)
  local output, cursor = {}, 0
  for _, b in ipairs(model.blocks) do
    local r = assert(ranges[b.id], "Lost conflict anchor")
    assert(r.first >= cursor and r.last >= r.first and r.last <= #preview, "Overlapping conflict anchors")
    for i = cursor + 1, r.first do output[#output + 1] = preview[i] end
    local first = #output
    if resolved[b.id] then
      for i = r.first + 1, r.last do output[#output + 1] = preview[i] end
    else
      append(output, b.raw)
    end
    if work_ranges then work_ranges[b.id] = { first = first, last = #output } end
    cursor = r.last
  end
  for i = cursor + 1, #preview do output[#output + 1] = preview[i] end
  return output
end

-- Plan explicit replacements from one immutable set of anchors. In particular,
-- inserting at an empty range must not expand its neighbouring block.
function M.replace(model, preview, ranges, replacements)
  local output, updated, cursor = {}, {}, 0
  for _, b in ipairs(model.blocks) do
    local r = assert(ranges[b.id], "Lost block anchor")
    assert(r.first >= cursor and r.last >= r.first and r.last <= #preview, "Overlapping block anchors")
    for i = cursor + 1, r.first do output[#output + 1] = preview[i] end
    local first = #output
    if replacements[b.id] then
      append(output, replacements[b.id])
    else
      for i = r.first + 1, r.last do output[#output + 1] = preview[i] end
    end
    updated[b.id] = { first = first, last = #output }
    cursor = r.last
  end
  for i = cursor + 1, #preview do output[#output + 1] = preview[i] end
  return output, updated
end

local function move_ranges(ranges, count, first, old_last, new_last)
  local delta, updated = new_last - old_last, {}
  for id, r in pairs(ranges) do
    assert(r.first >= 0 and r.last >= r.first and r.last <= count, "Invalid edit anchor")
    local a, b = r.first, r.last
    if old_last == first and new_last == first then
      -- An undoable no-op must not move an empty anchor at EOF.
    elseif a == b and first == old_last and first == a then
      b = b + delta -- Typing into an empty block is a manual resolution.
    elseif old_last <= a then
      a, b = a + delta, b + delta
    elseif first >= b then
      -- Edits on the following context line do not belong to this block.
    elseif first >= a and old_last <= b then
      b = b + delta
    else
      error("Правка пересекла границу конфликтного блока; автоматический перенос остановлен")
    end
    updated[id] = { first = a, last = b }
  end
  return updated
end

-- Use the actual on_lines span: equal neighboring lines do not identify where
-- an insertion/deletion happened. Broad notifications may include unchanged
-- context, but trimming it must not guess across a conflict boundary.
function M.edit_ranges(before, after, ranges, edit)
  local first, old_last, new_last = 0, #before, #after
  if edit then first, old_last, new_last = edit.first, edit.old_last, edit.new_last end
  assert(first >= 0 and old_last >= first and old_last <= #before
    and new_last >= first and new_last <= #after
    and #before - old_last == #after - new_last, "Invalid edit span")
  for i = 1, first do assert(before[i] == after[i], "Edit snapshot changed outside reported span") end
  for i = 1, #before - old_last do
    assert(before[old_last + i] == after[new_last + i], "Edit snapshot changed outside reported span")
  end
  local function trim(prefix_first)
    local a, b, c = first, old_last, new_last
    local function prefix()
      while a < math.min(b, c) and before[a + 1] == after[a + 1] do a = a + 1 end
    end
    local function suffix()
      while b > a and c > a and before[b] == after[c] do b, c = b - 1, c - 1 end
    end
    if prefix_first then
      prefix(); suffix()
    else
      suffix(); prefix()
    end
    return move_ranges(ranges, #before, a, b, c)
  end
  -- Repeated text can be trimmed from either end. Both extreme alignments
  -- must agree on every anchor; otherwise preserve work and recover the draft.
  local left, right = trim(false), trim(true)
  for id, r in pairs(left) do
    assert(r.first == right[id].first and r.last == right[id].last,
      "Неоднозначная привязка правки к конфликтному блоку; автоматический перенос остановлен")
  end
  return left
end

local function slice(lines, first, last)
  local result = {}
  for i = first + 1, last do result[#result + 1] = lines[i] end
  return result
end

local function equal(a, b)
  if #a ~= #b then return false end
  for i, value in ipairs(a) do if value ~= b[i] then return false end end
  return true
end

-- Reintroduce known conflict definitions without putting markers back into the
-- working text. The scaffold projects BASE for alignment; from_base then seeds
-- resolved blocks with their current text and keeps all three original choices.
function M.restore(working, entries)
  local model, cursor, unresolved = { parts = {}, blocks = {} }, 0, 0
  for _, entry in ipairs(entries) do
    assert(entry.first >= cursor and entry.last >= entry.first and entry.last <= #working,
      "Overlapping remembered conflicts")
    local content = slice(working, entry.first, entry.last)
    assert(equal(content, entry.raw), "Remembered conflict text changed outside preview")
    model.parts[#model.parts + 1] = { lines = slice(working, cursor, entry.first) }
    local b = {
      id = #model.blocks + 1,
      kind = "conflict",
      raw = content,
      base = entry.base,
      ours = entry.ours,
      theirs = entry.theirs,
      has_base = true,
      restore = entry.resolved and content or nil,
      initial_resolved = entry.resolved
    }
    if not entry.resolved then unresolved = unresolved + 1 end
    model.blocks[#model.blocks + 1] = b
    model.parts[#model.parts + 1] = { block = b }
    cursor = entry.last
  end
  model.parts[#model.parts + 1] = { lines = slice(working, cursor, #working) }
  assert(#M.parse(working).blocks == unresolved, "Conflict markers changed outside preview")
  return model
end

local function overlaps(a, b)
  if a.an == 0 then return a.a >= b.a and a.a <= b.a + b.an end
  if b.an == 0 then return b.a >= a.a and b.a <= a.a + a.an end
  return a.a < b.a + b.an and b.a < a.a + a.an
end

-- Only an exact, unopposed stage edit can be an ordinary Git proposal.
-- Everything else is existing working text, including manual resolutions.
-- Ambiguous diff alignment must preserve text, never replace it with BASE.
local function ordinary_change(h, clean, sides)
  if not sides then return true end
  local content, matched = slice(clean, h.b, h.b + h.bn), nil
  for index, side in ipairs(sides) do
    for _, change in ipairs(side.changes) do
      if overlaps(h, change) then
        if change.a ~= h.a or change.an ~= h.an
            or not equal(content, slice(side.lines, change.b, change.b + change.bn)) then
          return false
        end
        matched = matched or index
      end
    end
  end
  if not matched then return false end
  -- Git may put edits to ADJACENT lines into one conflict. A chosen side in
  -- that region must not become an ordinary proposal on the next opening.
  for index, side in ipairs(sides) do
    if index ~= matched then
      for _, change in ipairs(side.changes) do
        if h.a <= change.a + change.an and change.a <= h.a + h.an then
          if change.a ~= h.a or change.an ~= h.an
              or not equal(content, slice(side.lines, change.b, change.b + change.bn)) then
            return false
          end
        end
      end
    end
  end
  return true
end

-- Add pending non-conflicting changes. Their raw text is the ORIGINAL working
-- content, so an untouched BASE preview serializes back to the Git result,
-- not to BASE. Never approximate ambiguous boundaries here.
function M.from_base(original, base, changes, sides)
  local clean, old_ranges = M.project(original, "result")
  local raw = M.serialize(original, clean, old_ranges, {})
  local owners = {}
  for hi, h in ipairs(changes) do
    for _, b in ipairs(original.blocks) do
      local r = old_ranges[b.id]
      local overlap = h.bn > 0 and ((h.b < r.last and h.b + h.bn > r.first)
        or (r.first == r.last and h.b < r.first and h.b + h.bn > r.first))
      local deletion = h.bn == 0 and not b.has_base and h.b >= r.first and h.b <= r.last
      if overlap or deletion then
        assert(not b.has_base and h.b >= r.first and h.b + h.bn <= r.last and not owners[hi],
          "Неоднозначные границы BASE: нужен исходный RESULT в стиле zdiff3")
        owners[hi] = b.id
      end
    end
  end
  local function boundary(row, ending, id)
    local offset = 0
    for hi, h in ipairs(changes) do
      if row < h.b then return row + offset end
      if row == h.b and h.bn == 0 then
        if ending then return owners[hi] == id and h.a + h.an or h.a end
        return owners[hi] == id and h.a or h.a + h.an
      end
      if row == h.b then return h.a end
      assert(row >= h.b + h.bn, "BASE boundary falls inside a replacement")
      offset = h.a + h.an - h.b - h.bn
    end
    return row + offset
  end
  local events = {}
  for _, b in ipairs(original.blocks) do
    local r = old_ranges[b.id]
    local first, last = boundary(r.first, false, b.id), boundary(r.last, true, b.id)
    local content = slice(base, first, last)
    assert(last >= first and (not b.has_base or equal(content, b.base)), "Conflict BASE does not match index BASE")
    events[#events + 1] = {
      first = first,
      last = last,
      at = r.first,
      block = {
        kind = "conflict",
        raw = b.raw,
        ours = b.ours,
        theirs = b.theirs,
        base = content,
        has_base = true,
        initial_result = b.restore,
        initial_resolved = b.initial_resolved
      }
    }
  end
  for hi, h in ipairs(changes) do
    if not owners[hi] then
      local content = slice(clean, h.b, h.b + h.bn)
      local event = { first = h.a, last = h.a + h.an, at = h.b }
      if ordinary_change(h, clean, sides) then
        event.block = { kind = "change", raw = content, base = slice(base, h.a, h.a + h.an), has_base = true }
      else
        event.lines = content
      end
      events[#events + 1] = event
    end
  end
  table.sort(events, function(a, b)
    if a.first ~= b.first then return a.first < b.first end
    if a.at ~= b.at then return a.at < b.at end
    return a.last < b.last
  end)
  local model, cursor, number = { parts = {}, blocks = {} }, 0, 0
  for _, event in ipairs(events) do
    assert(event.first >= cursor, "Overlapping BASE regions")
    model.parts[#model.parts + 1] = { lines = slice(base, cursor, event.first) }
    local b = event.block
    if b then
      b.id = #model.blocks + 1
      if b.kind == "conflict" then
        number = number + 1; b.number = number
      end
      model.blocks[#model.blocks + 1] = b
      model.parts[#model.parts + 1] = { block = b }
    else
      model.parts[#model.parts + 1] = { lines = event.lines }
    end
    cursor = event.last
  end
  model.parts[#model.parts + 1] = { lines = slice(base, cursor, #base) }
  model.conflict_count, model.change_count = number, #model.blocks - number
  local preview, ranges = M.project(model, "result")
  if not sides then assert(equal(preview, base), "Preview must start with exact BASE") end
  assert(equal(M.serialize(model, preview, ranges, {}), raw), "Opening would change the Git result")
  return model
end

return M
