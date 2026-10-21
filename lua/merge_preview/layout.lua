-- Three native buffer views over an inert host; only RESULT accepts input.
local M = {}
local api = vim.api
local scroll = require("merge_preview.scroll")
local separator = { "", "", "", "", "", "", "│", "" }

function M.host(s)
  s.host = api.nvim_get_current_win()
  s.host_buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(s.host_buf, "merge-preview-host://" .. s.serial)
  vim.bo[s.host_buf].bufhidden, vim.bo[s.host_buf].modifiable = "wipe", false
  vim.bo[s.host_buf].filetype = "merge-preview-host"
  api.nvim_win_set_buf(s.host, s.host_buf)
  s.host_options = {}
  for name, value in pairs({
    number = false, relativenumber = false, signcolumn = "no", foldcolumn = "0",
    statuscolumn = "", winbar = "", statusline = "", cursorline = false,
    cursorcolumn = false, list = false, fillchars = "eob: ",
  }) do
    s.host_options[name] = vim.wo[s.host][name]
    vim.wo[s.host][name] = value
  end
end

function M.config(s, kind)
  local position = api.nvim_win_get_position(s.host)
  local width = api.nvim_win_get_width(s.host)
  local side = math.max(1, math.floor((width - 2) / 3))
  local middle = math.max(1, width - 2 * side - 2)
  local column = kind == "ours" and 0 or (kind == "result" and side or side + middle + 1)
  return {
    relative = "editor", row = position[1], col = position[2] + column,
    width = kind == "result" and middle or side,
    height = api.nvim_win_get_height(s.host),
    border = kind == "ours" and "none" or separator,
    focusable = kind == "result", mouse = kind == "result", zindex = 40,
  }
end

function M.help_config(buf)
  local width = math.max(1, math.min(84, vim.o.columns - 4))
  local height = math.max(1, math.min(api.nvim_buf_line_count(buf), vim.o.lines - vim.o.cmdheight - 4))
  return {
    relative = "editor", style = "minimal", border = "rounded", zindex = 80,
    title = " Merge · g? ", width = width, height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2) - 1),
  }
end

function M.resize(s)
  if s.laying_out or s.closing or s.disposing or not api.nvim_win_is_valid(s.host)
      or api.nvim_get_current_tabpage() ~= s.tab then return end
  for _, win in pairs(s.windows) do if not api.nvim_win_is_valid(win) then return end end
  s.laying_out = true
  local ok, err = pcall(function()
    for kind, win in pairs(s.windows) do
      local desired, current = M.config(s, kind), api.nvim_win_get_config(win)
      if current.width ~= desired.width or current.height ~= desired.height
          or current.row ~= desired.row or current.col ~= desired.col then
        api.nvim_win_set_config(win, desired)
      end
    end
    if s.help and api.nvim_win_is_valid(s.help) then
      api.nvim_win_set_config(s.help, M.help_config(api.nvim_win_get_buf(s.help)))
    end
  end)
  s.laying_out = false
  if not ok then vim.notify("Merge preview layout: " .. tostring(err), vim.log.levels.WARN) end
  scroll.align(s, s.windows.result)
end

function M.attach(s, group)
  api.nvim_create_autocmd({ "VimResized", "WinResized", "TabEnter" }, {
    group = group, callback = function() M.resize(s) end,
  })
  api.nvim_create_autocmd("OptionSet", {
    group = group, pattern = { "laststatus", "showtabline", "cmdheight" },
    callback = function() M.resize(s) end,
  })
  api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      if s.closing or s.disposing or s.busy or s.laying_out or api.nvim_get_current_tabpage() ~= s.tab then return end
      local win = api.nvim_get_current_win()
      if (win == s.host or win == s.windows.ours or win == s.windows.theirs)
          and api.nvim_win_is_valid(s.windows.result) then
        api.nvim_set_current_win(s.windows.result)
      end
    end,
  })
end

return M
