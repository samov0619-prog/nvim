local M = {}
local installed = false

-- JSON null is vim.NIL, not Lua nil. Some servers send it for optional
-- FileOperationFilter fields; MiniFiles assumes absent fields are Lua nil.
local function normalize()
  for _, client in ipairs(vim.lsp.get_clients()) do
    local workspace = client.server_capabilities.workspace
    local operations = type(workspace) == "table" and workspace.fileOperations
    if type(operations) == "table" then
      for _, operation in pairs(operations) do
        local filters = type(operation) == "table" and operation.filters
        if type(filters) == "table" then
          for _, filter in ipairs(filters) do
            if filter.scheme == vim.NIL then filter.scheme = nil end
            local pattern = filter.pattern
            if type(pattern) == "table" then
              if pattern.matches == vim.NIL then pattern.matches = nil end
              if pattern.options == vim.NIL then pattern.options = nil end
              if type(pattern.options) == "table" and pattern.options.ignoreCase == vim.NIL then
                pattern.options.ignoreCase = nil
              end
            end
          end
        end
      end
    end
  end
end

function M.setup(mf)
  if installed then return end
  installed = true
  local synchronize = mf.synchronize
  mf.synchronize = function(...)
    -- Read live capabilities each time, including dynamically registered ones.
    normalize()
    return synchronize(...)
  end
end

return M
