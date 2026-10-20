-- Presentation only: documented Diffview hooks and public Neovim window APIs.
local M = {}
local windows = {}
local inherited = {}
-- Sonokai removes CursorLine's background in diff mode; UFO can also restore
-- a stale window-local copy. Give Diffview its own live, background-only group.
local groups = { "DiffAdd", "DiffChange", "DiffText", "DiffTextAdd", "DiffDelete", "CursorLine" }
local aliases = {}
for _, name in ipairs(groups) do aliases[name] = "UserDiffview" .. name end

local function set_colors()
  local bg = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
  local light = vim.o.background == "light"
  if bg then
    local r, g, b = math.floor(bg / 65536), math.floor(bg / 256) % 256, bg % 256
    light = (r * 299 + g * 587 + b * 114) / 1000 > 128
  end
  local colors = light
      and { "#E6F2E6", "#EEF1F7", "#B8CCE6", "#B8DEB8", "#F5F5F5", "#F0F0F0" }
      or { "#2E3D32", "#303844", "#4A617D", "#3E5B43", "#292B30", "#33353F" }
  for i, name in ipairs(groups) do
    -- Background only, so syntax foregrounds remain readable.
    vim.api.nvim_set_hl(0, aliases[name], { bg = colors[i] })
  end
end

local function restore(win)
  local state = windows[win]
  if not state then return end
  if vim.api.nvim_win_is_valid(win) then
    if vim.wo[win].winhighlight == state.applied_hl then vim.wo[win].winhighlight = state.hl end
    if vim.wo[win].fillchars == state.applied_fill then vim.wo[win].fillchars = state.fill end
  end
  windows[win] = nil
end

function M.enter(buf, win, _, customize)
  restore(win)
  local state = {
    buf = buf,
    tab = vim.api.nvim_win_get_tabpage(win),
    hl = vim.wo[win].winhighlight,
    fill = vim.wo[win].fillchars,
  }
  local mapping = {}
  for _, item in ipairs(vim.split(state.hl, ",", { trimempty = true })) do
    if not aliases[item:match("^([^:]+):")] then mapping[#mapping + 1] = item end
  end
  for _, name in ipairs(groups) do
    -- DiffTextAdd is provided by newer Neovim versions.
    if name ~= "DiffTextAdd" or vim.fn.hlexists(name) == 1 then
      mapping[#mapping + 1] = name .. ":" .. aliases[name]
    end
  end
  vim.wo[win].winhighlight = table.concat(mapping, ",")
  vim.api.nvim_win_call(win, function() vim.opt_local.fillchars:append({ diff = " " }) end)
  if customize then customize(win) end
  state.applied_hl, state.applied_fill = vim.wo[win].winhighlight, vim.wo[win].fillchars
  inherited[state.applied_hl .. "\0" .. state.applied_fill] = { hl = state.hl, fill = state.fill }
  windows[win] = state
end

function M.close(view)
  for win, state in pairs(windows) do
    if state.tab == view.tabpage then restore(win) end
  end
end

function M.setup()
  set_colors()
  local api = vim.api
  local group = api.nvim_create_augroup("DiffviewPresentation", { clear = true })
  api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_colors })
  api.nvim_create_autocmd({ "WinEnter", "BufWinEnter" }, {
    group = group,
    callback = function()
      local win = api.nvim_get_current_win()
      local state = windows[win]
      if state then
        if state.buf ~= api.nvim_win_get_buf(win) or not vim.wo[win].diff then restore(win) end
      else
        -- :split/:tabnew can copy window options. A new ordinary window must
        -- not inherit this palette; a Diffview window gets its own enter hook.
        local original = inherited[vim.wo[win].winhighlight .. "\0" .. vim.wo[win].fillchars]
        if original then
          vim.wo[win].winhighlight, vim.wo[win].fillchars = original.hl, original.fill
        end
      end
    end,
  })
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(event) windows[tonumber(event.match)] = nil end,
  })
end

return M
