local M = {}

---describes argument, useful in mapping when you have *prototype*-like mapping
---options.
---@param x table
---@param desc string
---@return table

function M.described(x, desc)
    return vim.tbl_extend("force", x, { desc = desc })
end

return M
