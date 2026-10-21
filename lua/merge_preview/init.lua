-- Experimental, opt-in view. It does not replace Diffview's buffers or APIs.
local M = {}
local api = vim.api
local model_api = require("merge_preview.model")
local memory = require("merge_preview.memory")
local visual = require("merge_preview.visual")
local painter = require("merge_preview.diff")
local scroll = require("merge_preview.scroll")
local views, serial = {}, 0
local redraw, sync, finish

local function warn(text) vim.notify("Merge preview: " .. text, vim.log.levels.WARN) end
local function lines(buf) return api.nvim_buf_get_lines(buf, 0, -1, false) end
local function joined(value) return table.concat(value, "\n") .. "\n" end
local function slice(value, first, last)
  local result = {}
  for i = first + 1, last do result[#result + 1] = value[i] end
  return result
end
local function hunk_range(start, count) return count == 0 and start or start - 1 end

-- Commit a fully prepared text in ONE buffer operation. A failure must not
-- leave half a set of merge decisions in the working buffer.
local function replace_text(buf, before, after)
  local first, old_last, new_last = 0, #before, #after
  while first < math.min(old_last, new_last) and before[first + 1] == after[first + 1] do first = first + 1 end
  while old_last > first and new_last > first and before[old_last] == after[new_last] do
    old_last, new_last = old_last - 1, new_last - 1
  end
  if old_last ~= first or new_last ~= first then
    api.nvim_buf_set_lines(buf, first, old_last, false, slice(after, first, new_last))
  end
end

local function work_unchanged(s)
  if not api.nvim_buf_is_loaded(s.work) then return false end
  local tick = api.nvim_buf_get_changedtick(s.work)
  if tick ~= s.work_tick then
    if not vim.deep_equal(lines(s.work), s.work_lines) then return false end
    s.work_tick = tick -- Saving can change the tick without changing text.
  end
  return true
end

local function panels_intact(s)
  if not api.nvim_tabpage_is_valid(s.tab) then return false end
  for _, kind in ipairs({ "ours", "result", "theirs" }) do
    local win, buf = s.windows[kind], s.buffers[kind]
    if not win or not buf or not api.nvim_win_is_valid(win) or not api.nvim_buf_is_loaded(buf)
        or api.nvim_win_get_buf(win) ~= buf then
      return false
    end
  end
  return true
end

-- Map projected conflict text back to the actual index snapshot. Accept only
-- unchanged spans; an ambiguous/unmatched range remains selectable in RESULT.
local function source_ranges(projected, source, ranges)
  local changes = vim.diff(joined(projected), joined(source), { result_type = "indices", algorithm = "patience" })
  local spans, a, b = {}, 0, 0
  for _, h in ipairs(changes) do
    local x, y = hunk_range(h[1], h[2]), hunk_range(h[3], h[4])
    spans[#spans + 1] = { a, x, b }
    a, b = x + h[2], y + h[4]
  end
  spans[#spans + 1] = { a, #projected, b }
  local mapped = {}
  for id, r in ipairs(ranges) do
    for _, span in ipairs(spans) do
      if r.first >= span[1] and r.last <= span[2] then
        mapped[id] = { first = span[3] + r.first - span[1], last = span[3] + r.last - span[1] }
        break
      end
    end
  end
  return mapped
end

local function result_ranges(s)
  if s.anchor_error then error(s.anchor_error) end
  return s.ranges.result
end

local function panel_ranges(s, buf)
  return buf == s.result and result_ranges(s)
      or (buf == s.buffers.ours and s.ranges.ours or s.ranges.theirs)
end

local function anchor_ranges(s, ranges)
  s.ranges.result, s.anchor_error = vim.deepcopy(ranges), nil
end

local function sequence(s)
  return api.nvim_buf_call(s.result, function() return vim.fn.undotree().seq_cur end)
end

function M.statuscolumn()
  local win = tonumber(vim.g.statusline_winid) or api.nvim_get_current_win()
  local s = views[api.nvim_win_get_tabpage(win)]
  if not s then return "%C%s%=%l " end
  local buf = api.nvim_win_get_buf(win)
  local rows = s.rows[buf] or {}
  local marker = rows[vim.v.lnum]
  if vim.v.virtnum < 0 then
    local before = rows[vim.v.lnum - 1]
    marker = before and marker and before.id == marker.id and { id = marker.id, edge = "│" } or nil
  elseif vim.v.virtnum > 0 then
    marker = marker and { id = marker.id, edge = "│" } or nil
  end
  local id = marker and marker.id
  local deleted = not marker and vim.v.virtnum == 0 and s.deleted and s.deleted[buf] and s.deleted[buf][vim.v.lnum]
  local text = marker and marker.first and tostring(s.model.blocks[id].number) or ""
  local hl = id and s.resolved[id] and "DiagnosticOk" or "DiagnosticWarn"
  if deleted then hl = "DiagnosticError" end
  if id and id == s.active then
    hl = s.resolved[id] and "MergePreviewResolvedFocus" or "MergePreviewPendingFocus"
  end
  return "%C%#" .. hl .. "#" .. string.rep(" ", math.max(0, s.width - #text)) .. text
      .. (marker and marker.edge or (deleted and "−" or " ")) .. "%* %=%l "
end

local function focus(s)
  local buf = api.nvim_get_current_buf()
  local marker = s.rows[buf] and s.rows[buf][api.nvim_win_get_cursor(0)[1]]
  local id = marker and marker.id
  if s.active ~= id then
    s.active = id; vim.cmd("redraw!")
  end
end

local function panel_title(s, kind, pending, changes_pending)
  local text = kind:upper() .. " · " .. s.name
  if kind == "result" then
    local total, changes = s.model.conflict_count, s.model.change_count
    text = text .. (" · C %d/%d · Δ %d/%d"):format(
      total - (pending or total), total, changes - (changes_pending or changes), changes)
    if (pending or total) > 0 then
      text = text .. " !"
    elseif changes_pending == 0 then
      text = text .. " ✓"
    end
    if vim.bo[s.work].modified then text = text .. " [+]" end
    if s.detached then text = text .. " [detached]" end
  end
  return text
end

function M.modified()
  local win = api.nvim_get_current_win()
  local s = views[api.nvim_win_get_tabpage(win)]
  return s and win == s.windows.result and vim.bo[s.work].modified or false
end

function M.label()
  local win = api.nvim_get_current_win()
  local s = views[api.nvim_win_get_tabpage(win)]
  if not s then return nil end
  for kind, id in pairs(s.windows) do
    if win == id then
      return panel_title(s, kind, s.remaining, s.changes_remaining):gsub("%%", "%%%%")
    end
  end
end

redraw = function(s)
  if not views[s.tab] or not panels_intact(s) then return end
  s.rows = {}
  s.display_ranges = {}
  local ranges = result_ranges(s)
  local pending, changes = 0, 0
  for _, b in ipairs(s.model.blocks) do
    if not s.resolved[b.id] then
      if b.kind == "change" then changes = changes + 1 else pending = pending + 1 end
    end
  end
  s.remaining, s.changes_remaining = pending, changes
  for kind, buf in pairs(s.buffers) do
    local selected = kind == "result" and ranges or s.ranges[kind]
    local conflicts = {}
    for id, range in pairs(selected) do
      if s.model.blocks[id].kind ~= "change" then conflicts[id] = range end
    end
    s.display_ranges[kind] = conflicts
    s.rows[buf] = visual.rows(conflicts, api.nvim_buf_line_count(buf))
    local win = s.windows[kind]
    if api.nvim_win_is_valid(win) then
      local label = panel_title(s, kind, pending, changes)
      vim.wo[win].winbar = " " .. label:gsub("%%", "%%%%")
    end
  end
  painter.update(s)
  painter.proposals(s, ranges)
  if api.nvim_get_current_tabpage() == s.tab then focus(s) end
  vim.cmd.redrawstatus()
end

local function sync_impl(s, explicit)
  if not work_unchanged(s) then
    s.detached = true
    warn("Рабочий буфер изменён снаружи. Закрой preview и открой заново; правки не перезаписаны.")
    return false
  end
  local seq = sequence(s)
  local current = lines(s.result)
  local signature = vim.fn.sha256(joined(current))
  -- A sequence number alone is insufficient while an undo block is changing.
  -- Restore coordinates/decisions only for the exact text saved with them.
  local restored = not explicit and seq ~= s.last_seq and s.text_history[seq] == signature
  if restored and s.anchor_history[seq] then
    anchor_ranges(s, s.anchor_history[seq])
  end
  local ranges = result_ranges(s)
  if explicit then
    s.history[seq] = vim.deepcopy(s.resolved)
  elseif restored and s.history[seq] then
    s.resolved = vim.deepcopy(s.history[seq])
  else
    for _, b in ipairs(s.model.blocks) do
      local r = ranges[b.id]
      if not vim.deep_equal(slice(current, r.first, r.last), b.seed) then s.resolved[b.id] = true end
    end
    s.history[seq] = vim.deepcopy(s.resolved)
  end
  s.anchor_history[seq], s.last_seq = vim.deepcopy(ranges), seq
  s.text_history[seq] = signature
  local work_ranges = {}
  local ok, output = pcall(model_api.serialize, s.model, current, ranges, s.resolved, work_ranges)
  if not ok then
    s.detached = true; warn(output); return false
  end
  local previous = lines(s.work)
  if not vim.deep_equal(previous, output) then
    local success, err = pcall(replace_text, s.work, previous, output)
    if not success then
      s.detached = true; warn(tostring(err)); return false
    end
    s.work_tick = api.nvim_buf_get_changedtick(s.work)
  end
  s.work_lines, s.synced_draft = output, current
  -- A failed metadata update must not invalidate a successful text commit.
  local remembered, err = pcall(memory.record, s.work, s.path, s.stage_key, s.model, work_ranges, s.resolved, output)
  if not remembered then
    memory.clear(s.work); warn("Память конфликтов: " .. tostring(err))
  end
  -- RESULT is a projection, not a second unsaved file. Once synchronized it
  -- may be closed normally; modified/saved status belongs to the work buffer.
  vim.bo[s.result].modified = false
  if not s.disposing then
    local painted, err = pcall(redraw, s)
    if not painted then warn("Отрисовка: " .. tostring(err)) end
  end
  return true
end

sync = function(s, explicit)
  if s.busy or s.closing or s.detached or not views[s.tab] then return false end
  s.busy = true
  local ok, result = pcall(sync_impl, s, explicit)
  s.busy = false
  if not ok then
    s.detached = true; warn(tostring(result)); return false
  end
  return result
end

local function current_block(s)
  local buf, row = api.nvim_get_current_buf(), api.nvim_win_get_cursor(0)[1] - 1
  local ranges = panel_ranges(s, buf)
  local count = api.nvim_buf_line_count(buf)
  local change
  for _, b in ipairs(s.model.blocks) do
    local r = ranges[b.id]
    if r then
      local first, last = visual.visible_range(r, count)
      if row >= first and row < last then
        if b.kind ~= "change" then return b end
        change = b
      end
    end
  end
  return change
end

local function commit_preview(s, before, output, ranges, resolved)
  local viewport = scroll.capture(s)
  -- busy prevents reentrant sync; editing_result skips manual anchor tracking.
  -- The explicit replacement already computed every anchor from one snapshot.
  s.busy, s.editing_result = true, true
  local success, err = pcall(api.nvim_buf_call, s.result, function()
    -- Commands from a side pane otherwise keep RESULT's previous undo block
    -- open, merging separate choices and overwriting their history snapshots.
    vim.bo[s.result].undolevels = vim.bo[s.result].undolevels
    if vim.deep_equal(before, output) then
      -- Accepting BASE can resolve markers without changing visible text.
      -- Record that explicit decision as an undoable buffer operation too.
      api.nvim_buf_set_lines(s.result, 0, 1, false, { before[1] })
    else
      replace_text(s.result, before, output)
    end
    anchor_ranges(s, ranges)
  end)
  s.busy, s.editing_result = false, false
  if not success then
    s.detached = true; warn(tostring(err)); return false
  end
  s.resolved = resolved
  if not sync(s, true) then return false end
  scroll.restore(s, viewport)
  return true
end

local function replace_preview(s, replacements, reset)
  local before = lines(s.result)
  local ok, output, ranges = pcall(model_api.replace, s.model, before, result_ranges(s), replacements)
  if not ok then
    warn(tostring(output)); return false
  end
  local resolved = vim.deepcopy(s.resolved)
  for id in pairs(replacements) do
    if reset then resolved[id] = s.initial_resolved[id] else resolved[id] = true end
  end
  return commit_preview(s, before, output, ranges, resolved)
end

local function choose(s, side)
  if not sync(s) then return end
  local b = current_block(s)
  if not b then
    warn("Курсор вне блока. Используй ]x или перейди в RESULT."); return
  end
  if b.kind == "change" and side ~= "base" then
    warn("Неконфликтующее изменение: <leader>cN — применить все, <leader>c0 — оставить BASE здесь.")
    return
  end
  local replacement
  if side == "both" then
    replacement = vim.list_extend(vim.deepcopy(b.ours), b.theirs)
  else
    replacement = b[side]
  end
  if side == "base" and not b.has_base then
    warn("В этих маркерах нет BASE; используй diff3/zdiff3."); return
  end
  if not replace_preview(s, { [b.id] = replacement }) then return end
end

local function choose_all(s, side)
  if not sync(s) then return end
  local replacements = {}
  for _, b in ipairs(s.model.blocks) do
    if b.kind ~= "change" and not s.resolved[b.id] then
      replacements[b.id] = b[side]
    end
  end
  if not next(replacements) then return end
  if not replace_preview(s, replacements) then return end
end

local function reset(s, all)
  if not sync(s) then return end
  if all then
    local before = lines(s.result)
    if vim.deep_equal(before, s.initial_preview) and vim.deep_equal(s.resolved, s.initial_resolved)
        and vim.deep_equal(result_ranges(s), s.initial_ranges) then return end
    if not commit_preview(s, before, s.initial_preview, s.initial_ranges, vim.deepcopy(s.initial_resolved)) then return end
  else
    local b = current_block(s)
    if not b then
      warn("Курсор вне блока. Перейди к конфликту или неконфликтующему изменению в RESULT."); return
    end
    local r = result_ranges(s)[b.id]
    if vim.deep_equal(slice(lines(s.result), r.first, r.last), b.seed)
        and s.resolved[b.id] == s.initial_resolved[b.id] then return end
    if not replace_preview(s, { [b.id] = b.seed }, true) then return end
  end
end

local function replay(s, key)
  local viewport = scroll.capture(s)
  api.nvim_buf_call(s.result, function() vim.cmd("normal! " .. key) end)
  if sync(s) then scroll.restore(s, viewport) end
end

local function navigate(s, direction)
  if not sync(s) then return end
  local buf, row = api.nvim_get_current_buf(), api.nvim_win_get_cursor(0)[1] - 1
  local ranges = panel_ranges(s, buf)
  local candidates, count = {}, api.nvim_buf_line_count(buf)
  for id, r in pairs(ranges) do
    if s.model.blocks[id].kind ~= "change" and not s.resolved[id] then
      local first = visual.visible_range(r, count)
      candidates[#candidates + 1] = first
    end
  end
  table.sort(candidates)
  if #candidates == 0 then
    warn("Нет неразрешённых блоков в этой панели; проверь RESULT."); return
  end
  local target = direction > 0 and candidates[1] or candidates[#candidates]
  if direction > 0 then
    for _, first in ipairs(candidates) do
      if first > row then
        target = first; break
      end
    end
  else
    for i = #candidates, 1, -1 do
      if candidates[i] < row then
        target = candidates[i]; break
      end
    end
  end
  api.nvim_win_set_cursor(0, { target + 1, 0 })
  vim.cmd("normal! zz")
  scroll.align(s, api.nvim_get_current_win())
end

local function apply_nonconflicting(s)
  if not sync(s) then return false end
  local replacements = {}
  for _, b in ipairs(s.model.blocks) do
    if b.kind == "change" and not s.resolved[b.id] then
      replacements[b.id] = b.raw
    end
  end
  if not next(replacements) then return true end
  return replace_preview(s, replacements)
end

local function close(s)
  finish(s)
end

local function help(s)
  if s.help and api.nvim_win_is_valid(s.help) then
    api.nvim_set_current_win(s.help); return
  end
  local leader = (vim.g.mapleader or "\\"):gsub(" ", "<Space>"):gsub("\t", "<Tab>")
  local text = {
    "Merge editor", "",
    leader .. "co    OURS для текущего конфликта",
    leader .. "ct    THEIRS для текущего конфликта",
    leader .. "cO    OURS для всех нерешённых конфликтов",
    leader .. "cT    THEIRS для всех нерешённых конфликтов",
    leader .. "cb    OURS + THEIRS",
    leader .. "c0    Явно оставить BASE в текущем участке",
    leader .. "cr    Сбросить текущий конфликт / неконфликтующее изменение",
    leader .. "cR    Сбросить весь RESULT, включая ручные правки",
    leader .. "cN    Применить все ожидающие неконфликтующие изменения",
    "", "[x / ]x    Предыдущий / следующий нерешённый конфликт",
    "u / <C-r>  Undo / redo RESULT из любой панели",
    ":w         Сохранить рабочий файл (из RESULT), без staging",
    "q          Закрыть merge-вкладку, сохранив решения в рабочем буфере",
    "g?         Эта справка", "",
    "C — решённые конфликты; Δ — принятые неконфликтующие предложения.",
    "! — есть нерешённые конфликты; [+] — рабочий файл не сохранён.",
    "cr / cR возвращают состояние открытия preview; сброс отменяется через u.",
    "При открытии cN можно повторить; ручные решения сохраняются.",
    "Зелёный конфликт можно переиграть: co / ct / cb / c0 в его диапазоне.",
    "cO / cT сохраняют решения и ручные правки; неконфликтующие — через cN.",
    "", "Esc / q — закрыть справку",
  }
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, text)
  vim.bo[buf].bufhidden, vim.bo[buf].modifiable = "wipe", false
  local width, height = math.min(84, vim.o.columns - 4), math.min(#text, vim.o.lines - 4)
  s.help = api.nvim_open_win(buf, true, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " Merge · g? ",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.floor((vim.o.columns - width) / 2),
  })
  local function dismiss()
    if s.help and api.nvim_win_is_valid(s.help) then api.nvim_win_close(s.help, true) end
  end
  for _, key in ipairs({ "q", "<Esc>", "g?" }) do
    vim.keymap.set("n", key, dismiss, { buffer = buf, silent = true })
  end
end

local function save(s, force, target, cmdarg)
  -- BufWriteCmd also handles :w other-name and :saveas. Never silently
  -- redirect those requests into the real working file.
  local name = s.result_name
  if api.nvim_buf_get_name(s.result) ~= name
      or (target and target ~= "" and vim.fn.fnamemodify(target, ":p") ~= vim.fn.fnamemodify(name, ":p")) then
    error("Merge preview: запись под другим именем из RESULT не поддерживается; используй рабочий буфер", 0)
  end
  if cmdarg and cmdarg ~= "" then
    error("Merge preview: параметры ++ записи из RESULT не поддерживаются; используй рабочий буфер", 0)
  end
  if api.nvim_buf_get_name(s.work) ~= s.path then
    error("Merge preview: рабочий файл переименован; открой preview заново", 0)
  end
  if not sync(s) then error("Merge preview: RESULT не синхронизирован; запись отменена", 0) end
  local expected = lines(s.work)
  local readonly = vim.bo[s.work].readonly
  -- The explicit save targets only the real, writable working file. Some
  -- source views leave its buffer readonly; lift that local flag just for the
  -- delegated write, never force filesystem permissions or overwrite checks.
  local lift = readonly and api.nvim_buf_get_name(s.work) == s.path and vim.fn.filewritable(s.path) == 1
  if lift then vim.bo[s.work].readonly = false end
  local success, err = pcall(api.nvim_buf_call, s.work, function()
    vim.cmd.write({ bang = force })
  end)
  if lift and api.nvim_buf_is_valid(s.work) then vim.bo[s.work].readonly = readonly end
  if not success then error("Merge preview: " .. tostring(err), 0) end
  s.work_tick = api.nvim_buf_get_changedtick(s.work)
  if not vim.deep_equal(expected, lines(s.work)) then
    s.detached = true
    warn("Текст изменился при сохранении. Рабочий файл сохранён; открой preview заново.")
  end
  vim.bo[s.result].modified = false
  redraw(s)
end

-- Keep the last RESULT text in Lua independently of buffer lifetime. :q! can
-- unload a buffer even with bufhidden=hide; on_lines captures text before that.
local function capture_draft(s)
  if api.nvim_buf_is_loaded(s.result) then s.draft = lines(s.result) end
end

local function recover_draft(s)
  local buf = api.nvim_create_buf(true, true)
  api.nvim_buf_set_name(buf, "merge-draft://" .. s.serial .. "/" .. s.name)
  api.nvim_buf_set_lines(buf, 0, -1, false, s.draft)
  vim.bo[buf].bufhidden, vim.bo[buf].filetype = "hide", s.filetype
  vim.bo[buf].readonly = false
  warn("Несинхронизированный RESULT скопирован в буфер " .. buf .. "; открыть: :buffer " .. buf)
  return buf
end

finish = function(s)
  if s.finished then return end
  s.disposing = true
  capture_draft(s)
  local transferred
  if api.nvim_buf_is_loaded(s.result) then
    transferred = sync(s)
  else
    transferred = not s.detached and work_unchanged(s) and vim.deep_equal(s.draft, s.synced_draft)
  end
  -- Make the recovery copy BEFORE deleting buffers or closing remaining panes.
  if not transferred then recover_draft(s) end
  s.finished, s.closing = true, true
  views[s.tab] = nil
  if s.group then api.nvim_del_augroup_by_id(s.group) end
  if s.help and api.nvim_win_is_valid(s.help) then api.nvim_win_close(s.help, true) end
  for kind, win in pairs(s.windows) do
    if api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == s.buffers[kind] then
      local ok = pcall(api.nvim_win_close, win, true)
      -- The merge tab may have become the last tab. Keep one ordinary window
      -- rather than leaving a half-alive merge view or closing unrelated files.
      if not ok and api.nvim_win_is_valid(win) then
        local buf = api.nvim_buf_is_valid(s.work) and s.work or api.nvim_create_buf(true, false)
        api.nvim_win_set_buf(win, buf)
      end
    end
  end
  for _, buf in pairs(s.buffers) do
    if api.nvim_buf_is_valid(buf) then api.nvim_buf_delete(buf, { force = true }) end
  end
end

local function queue_finish(s)
  if s.finished or s.finish_pending then return end
  s.finish_pending = true
  vim.schedule(function()
    s.finish_pending = false
    if not s.finished and not panels_intact(s) then finish(s) end
  end)
end

local function create_panels(s, preview, sources)
  vim.cmd.tabnew()
  s.tab = api.nvim_get_current_tabpage()
  local placeholder = api.nvim_get_current_buf()
  views[s.tab] = s
  local filetype = vim.bo[s.work].filetype
  visual.setup()
  for i, kind in ipairs({ "ours", "result", "theirs" }) do
    if i > 1 then vim.cmd("rightbelow vsplit") end
    local buf = api.nvim_create_buf(false, true)
    s.buffers[kind], s.windows[kind] = buf, api.nvim_get_current_win()
    api.nvim_buf_set_name(buf, "merge-preview://" .. serial .. "/" .. kind .. "/" .. s.name)
    local undo = vim.bo[buf].undolevels
    vim.bo[buf].undolevels = -1
    api.nvim_buf_set_lines(buf, 0, -1, false, kind == "result" and preview or sources[kind])
    vim.bo[buf].undolevels = undo
    vim.bo[buf].buftype = kind == "result" and "acwrite" or "nofile"
    -- Normal closes hide RESULT until cleanup; forced unloads are also covered
    -- by the independent on_lines snapshot used for draft recovery.
    vim.bo[buf].bufhidden = kind == "result" and "hide" or "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = filetype
    vim.bo[buf].modified = false
    vim.bo[buf].readonly = false
    if kind ~= "result" then vim.bo[buf].modifiable = false end
    vim.diagnostic.enable(false, { bufnr = buf })
    api.nvim_win_set_buf(0, buf)
    vim.wo.diff = false
    vim.wo.scrollbind = false
    vim.wo.cursorbind = false
    vim.wo.wrap = false
    vim.wo.foldenable = false
    vim.wo.scrolloff = 0
    vim.wo.statuscolumn = "%!v:lua.require'merge_preview'.statuscolumn()"
    local function map(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = buf, silent = true }) end
    map("<leader>co", function() choose(s, "ours") end)
    map("<leader>ct", function() choose(s, "theirs") end)
    map("<leader>cO", function() choose_all(s, "ours") end)
    map("<leader>cT", function() choose_all(s, "theirs") end)
    map("<leader>cb", function() choose(s, "both") end)
    map("<leader>c0", function() choose(s, "base") end)
    map("<leader>cr", function() reset(s, false) end)
    map("<leader>cR", function() reset(s, true) end)
    map("<leader>cN", function() apply_nonconflicting(s) end)
    map("]x", function() navigate(s, 1) end)
    map("[x", function() navigate(s, -1) end)
    map("u", function() replay(s, "u") end)
    map("<C-r>", function() replay(s, "\18") end)
    map("q", function() close(s) end)
    map("g?", function() help(s) end)
  end
  if api.nvim_buf_is_valid(placeholder) then api.nvim_buf_delete(placeholder, {}) end
  s.result = s.buffers.result
  s.result_name = api.nvim_buf_get_name(s.result)
end

local function attach_events(s)
  local group = api.nvim_create_augroup("MergePreview" .. serial, { clear = true })
  s.group = group
  scroll.attach(s, group)
  api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "WinEnter" }, {
    group = group,
    callback = function()
      if views[s.tab] and api.nvim_get_current_tabpage() == s.tab then focus(s) end
    end,
  })
  api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave", "BufLeave" }, {
    group = group, buffer = s.result, callback = function() sync(s) end,
  })
  local function result_changed(edit)
    if not views[s.tab] then return true end
    local before = s.observed_result
    capture_draft(s)
    s.observed_result = s.draft
    if not s.editing_result and not s.closing and not s.anchor_error then
      local tracked, ranges = pcall(model_api.edit_ranges, before, s.draft, s.ranges.result, edit)
      if tracked then s.ranges.result = ranges else s.anchor_error = tostring(ranges) end
    end
    if s.editing_result or s.closing or s.sync_pending then return end
    -- on_lines runs under textlock: commit at the next safe opportunity.
    -- BufLeave/BufWriteCmd and final cleanup also flush synchronously.
    s.sync_pending = true
    vim.schedule(function()
      s.sync_pending = false
      if views[s.tab] then
        if panels_intact(s) then sync(s) else queue_finish(s) end
      end
    end)
  end
  api.nvim_buf_attach(s.result, false, {
    on_lines = function(_, _, _, first, old_last, new_last)
      return result_changed({ first = first, old_last = old_last, new_last = new_last })
    end,
    on_reload = function() return result_changed() end,
    on_detach = function() queue_finish(s) end,
  })
  api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    buffer = s.result,
    nested = true,
    callback = function(event) save(s, vim.v.cmdbang == 1, event.match, vim.v.cmdarg) end,
  })
  api.nvim_create_autocmd({ "FileWriteCmd", "FileAppendCmd" }, {
    group = group,
    buffer = s.result,
    callback = function()
      error("Merge preview: запись диапазона и добавление в файл из RESULT не поддерживаются; используй рабочий буфер", 0)
    end,
  })
  api.nvim_create_autocmd({ "BufWinLeave", "BufUnload", "BufWipeout" }, {
    group = group,
    callback = function(event)
      if s.finished then return end
      for _, buf in pairs(s.buffers) do
        if event.buf == buf then
          capture_draft(s); queue_finish(s); return
        end
      end
    end,
  })
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(event)
      for _, win in pairs(s.windows) do
        if tonumber(event.match) == win then
          queue_finish(s); return
        end
      end
    end,
  })
  api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = function()
      if not api.nvim_tabpage_is_valid(s.tab) then queue_finish(s) end
    end,
  })
end

function M.open()
  local work = api.nvim_get_current_buf()
  local path = api.nvim_buf_get_name(work)
  if vim.bo[work].buftype ~= "" or path == "" or path:find("://", 1, true) then
    warn("Открой режим из рабочего файла / центрального окна Diffview."); return
  end
  for _, s in pairs(views) do
    if s.work == work then
      if panels_intact(s) then
        api.nvim_set_current_tabpage(s.tab); return
      end
      finish(s)
    end
  end
  local working = lines(work)
  local ok, model = pcall(model_api.parse, working)
  if not ok then
    warn(model); return
  end
  local root = vim.fs.root(path, ".git")
  if not root then
    warn("Git-репозиторий не найден."); return
  end
  local relative = path:sub(#root + 2)
  local sources, hashes = {}, {}
  for side, stage in pairs({ base = 1, ours = 2, theirs = 3 }) do
    local result = vim.system({ "git", "-C", root, "show", ":" .. stage .. ":" .. relative }, { text = true }):wait(3000)
    if result.code ~= 0 then
      memory.clear(work); warn("Нет конфликтной стадии " .. stage .. ": " .. relative); return
    end
    hashes[stage] = vim.fn.sha256(result.stdout)
    sources[side] = vim.split(result.stdout, "\n", { plain = true })
    if sources[side][#sources[side]] == "" then table.remove(sources[side]) end
  end
  local stage_key = table.concat(hashes, ":")
  model = memory.restore(work, path, stage_key, working) or model
  local clean = model_api.project(model, "result")
  local sides = {}
  for _, kind in ipairs({ "ours", "theirs" }) do
    sides[#sides + 1] = { lines = sources[kind], changes = painter.changes(sources.base, sources[kind]) }
  end
  local expanded, expanded_model = pcall(model_api.from_base, model, sources.base, painter.changes(sources.base, clean),
    sides)
  if not expanded then
    warn(tostring(expanded_model)); return
  end
  model = expanded_model
  local preview, initial = model_api.project(model, "result")
  if #preview == 0 then
    warn("Полностью пустой RESULT пока не поддерживается этим прототипом."); return
  end
  if not vim.deep_equal(working, lines(work)) then
    warn("Рабочий файл изменился во время открытия; попробуй снова."); return
  end
  local s = {
    work = work,
    path = path,
    stage_key = stage_key,
    work_tick = api.nvim_buf_get_changedtick(work),
    model = model,
    base = sources.base,
    -- Work detects outside edits; the independent draft survives RESULT unload.
    work_lines = working,
    draft = preview,
    observed_result = preview,
    synced_draft = preview,
    initial_preview = vim.deepcopy(preview),
    initial_ranges = vim.deepcopy(initial),
    buffers = {},
    windows = {},
    ranges = {},
    rows = {},
    resolved = {},
    -- Decisions and anchors share undo sequence keys, verified by text hash.
    history = {},
    anchor_history = {},
    text_history = {},
    name = vim.fn.fnamemodify(path, ":t"),
    width = math.max(2, #tostring(model.conflict_count)),
  }
  for _, side in ipairs({ "ours", "theirs" }) do
    local projected, ranges = model_api.project(model, side)
    s.ranges[side] = source_ranges(projected, sources[side], ranges)
  end
  serial = serial + 1
  s.serial, s.filetype = serial, vim.bo[work].filetype
  s.paint = api.nvim_create_namespace("MergePreviewPaint" .. serial)
  s.proposals = api.nvim_create_namespace("MergePreviewProposals" .. serial)
  create_panels(s, preview, sources)
  anchor_ranges(s, initial)
  for _, b in ipairs(model.blocks) do
    local r = initial[b.id]
    if b.initial_resolved then s.resolved[b.id] = true end
    b.seed = slice(preview, r.first, r.last)
  end
  s.initial_resolved = vim.deepcopy(s.resolved)
  s.history[sequence(s)] = vim.deepcopy(s.resolved)
  s.last_seq = sequence(s)
  s.anchor_history[s.last_seq] = vim.deepcopy(initial)
  s.text_history[s.last_seq] = vim.fn.sha256(joined(preview))
  attach_events(s)
  vim.cmd("wincmd =")
  api.nvim_set_current_win(s.windows.result)
  sync(s) -- Also remember the original definitions before any conflict is edited.
end

return M
