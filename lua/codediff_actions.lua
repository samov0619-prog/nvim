-- Dispatch our keys to configured native mappings. No CodeDiff internals,
-- range calculations, cursor relocation or direct changes to buffer text.
local M = {}
local owned = {}
local routes = {
  { key = "<leader>co", side = "<Plug>(UserCodeDiffAcceptLeft)", result = "<Plug>(UserCodeDiffGetLeft)", desc = "Conflict: accept ours" },
  { key = "<leader>ct", side = "<Plug>(UserCodeDiffAcceptRight)", result = "<Plug>(UserCodeDiffGetRight)", desc = "Conflict: accept theirs" },
}

local function local_map(lhs)
  local mapping = vim.fn.maparg(lhs, "n", false, true)
  return mapping.buffer == 1 and mapping or nil
end

local function restore_buffer(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_call(buf, function()
      for key, entry in pairs(owned[buf]) do
        local mapping = local_map(key)
        -- Respect a mapping changed by the user while the diff was open.
        if mapping and mapping.callback == entry.callback then
          if entry.previous then
            vim.fn.mapset("n", false, entry.previous)
          else
            vim.keymap.del("n", key, { buffer = buf })
          end
        end
      end
    end)
  end
  owned[buf] = nil
end

function M.restore()
  for buf in pairs(owned) do restore_buffer(buf) end
end

function M.refresh(buffers)
  for buf in pairs(owned) do
    if not buffers[buf] then restore_buffer(buf) end
  end
  for buf in pairs(buffers) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_call(buf, function()
        local available = false
        for _, route in ipairs(routes) do
          if local_map(route.side) or local_map(route.result) then available = true; break end
        end
        if not available then
          if owned[buf] then restore_buffer(buf) end
          return
        end
        for _, route in ipairs(routes) do
          if local_map(route.side) or local_map(route.result) then
            owned[buf] = owned[buf] or {}
            if not owned[buf][route.key] then
              local side, result = route.side, route.result
              local callback = function()
                if local_map(result) then return result end
                if local_map(side) then return side end
                return "<Ignore>"
              end
              owned[buf][route.key] = { previous = local_map(route.key), callback = callback }
              vim.keymap.set("n", route.key, callback, {
                buffer = buf, expr = true, remap = true, silent = true,
                desc = route.desc,
              })
            end
          end
        end
      end)
    end
  end
end

return M
