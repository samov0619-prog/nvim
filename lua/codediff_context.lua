-- Only documented CodeDiff User events and public Neovim APIs.
local M = {}
local tabs, muted = {}, {}
local pending = false

function M.is_view()
  return tabs[vim.api.nvim_get_current_tabpage()] == true
end

local function file_root(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if vim.bo[buf].buftype ~= "" or name == "" or name:find("://", 1, true) then return nil end
  return vim.fs.root(name, ".git")
end

function M.root()
  local root = file_root(vim.api.nvim_get_current_buf())
  if root then return root end
  if M.is_view() then
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      root = file_root(vim.api.nvim_win_get_buf(win))
      if root then return root end
    end
  end
  return vim.fn.getcwd()
end

local function restore()
  require("codediff_actions").restore()
  for buf in pairs(muted) do
    if vim.api.nvim_buf_is_valid(buf) then vim.diagnostic.enable(true, { bufnr = buf }) end
  end
  muted = {}
end

local function refresh()
  local wanted = {}
  local buffers = {}
  if M.is_view() then
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local buf = vim.api.nvim_win_get_buf(win)
      buffers[buf] = true
      if vim.bo[buf].buftype == "" then wanted[buf] = true end
    end
  end
  require("codediff_actions").refresh(buffers)
  for buf in pairs(muted) do
    if not wanted[buf] then
      if vim.api.nvim_buf_is_valid(buf) then vim.diagnostic.enable(true, { bufnr = buf }) end
      muted[buf] = nil
    end
  end
  for buf in pairs(wanted) do
    if not muted[buf] and vim.diagnostic.is_enabled({ bufnr = buf }) then
      vim.diagnostic.enable(false, { bufnr = buf })
      muted[buf] = true
    end
  end
end

local function queue()
  if pending or (not M.is_view() and not next(muted)) then return end
  pending = true
  vim.schedule(function()
    pending = false
    refresh()
  end)
end

function M.setup()
  local api = vim.api
  local group = api.nvim_create_augroup("CodeDiffPresentation", { clear = true })
  api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffOpen",
    callback = function(event)
      local tab = event.data and event.data.tabpage
      if tab then tabs[tab] = true end
      queue()
    end,
  })
  api.nvim_create_autocmd("User", {
    group = group,
    pattern = "CodeDiffClose",
    callback = function(event)
      local tab = event.data and event.data.tabpage
      if tab then tabs[tab] = nil end
      if tab == api.nvim_get_current_tabpage() then restore() end
    end,
  })
  api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "TabEnter" }, { group = group, callback = queue })
  api.nvim_create_autocmd("TabLeave", { group = group, callback = restore })
end

return M
