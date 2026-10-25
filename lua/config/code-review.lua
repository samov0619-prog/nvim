-- Diagnostics are buffer-local, while review mode follows the active tab.
-- Preserve each namespace's enablement, including user-disabled diagnostics.
local M = {}
local api = vim.api
local tools = require("config.code-tools")
local muted = {}
-- Capture user state before our per-buffer masks affect is_enabled().
local diagnostics_enabled = vim.diagnostic.is_enabled()

local function refresh(buf)
  local diagnostics = package.loaded["config.code-diagnostics"]
  if diagnostics then diagnostics.refresh(buf, false) end
end

function M.sync()
  local active = {}
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    local buf = api.nvim_win_get_buf(win)
    if tools.in_review(buf) then active[buf] = true end
  end
  for buf, namespaces in pairs(muted) do
    if not api.nvim_buf_is_valid(buf) then
      muted[buf] = nil
    elseif not active[buf] and api.nvim_buf_is_loaded(buf) and not tools.in_review(buf) then
      muted[buf] = nil
      for ns in pairs(namespaces) do vim.diagnostic.enable(true, { bufnr = buf, ns_id = ns }) end
      refresh(buf)
    end
  end
  for buf in pairs(active) do
    local entered = muted[buf] == nil
    muted[buf] = muted[buf] or {}
    for ns in pairs(vim.diagnostic.get_namespaces()) do
      if vim.diagnostic.is_enabled({ bufnr = buf, ns_id = ns }) then
        muted[buf][ns] = true
        vim.diagnostic.enable(false, { bufnr = buf, ns_id = ns })
      end
    end
    if entered then refresh(buf) end
  end
end

function M.toggle_diagnostics()
  diagnostics_enabled = not diagnostics_enabled
  vim.diagnostic.enable(diagnostics_enabled)
  -- Global enable/disable resets Neovim's per-buffer masks. Forget ownership
  -- of those old masks, then immediately suppress the active review again.
  muted = {}
  M.sync()
end

function M.setup()
  local group = api.nvim_create_augroup("CodeReview", { clear = true })
  api.nvim_create_autocmd({ "TabEnter", "WinEnter", "BufWinEnter", "DiagnosticChanged" }, {
    group = group, callback = M.sync,
  })
  api.nvim_create_autocmd("OptionSet", { group = group, pattern = "diff", callback = M.sync })
  api.nvim_create_autocmd("BufWipeout", {
    group = group, callback = function(args) muted[args.buf] = nil end,
  })
  M.sync()
end

return M
