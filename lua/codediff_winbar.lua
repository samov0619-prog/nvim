local M = {}

function M.label()
  if not require("codediff_context").is_view() then return nil end
  -- No session internals or virtual-URI parsing. Use the ordinary buffer name
  -- and show its basename, just as a filename component with path=0 would.
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
  if name == "" then name = "[No Name]" end
  local suffix = vim.bo[buf].modified and " ●" or ""
  return (name .. suffix):gsub("%%", "%%%%"):gsub("[%c]", " ")
end

return M
