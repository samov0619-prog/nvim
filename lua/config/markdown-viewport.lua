local M = {}
local started = false

function M.setup()
  if started then return end
  started = true
  local views, pending, scheduled = {}, {}, false
  local filetypes = { markdown = true, quarto = true }
  local function flush()
    scheduled = false
    local batch = pending
    pending = {}
    local md = package.loaded['render-markdown']
    if not md or not md.get() then return end
    local buffers = {}
    for win, buf in pairs(batch) do
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf
          and filetypes[vim.bo[buf].filetype] then
        buffers[buf] = buffers[buf] or {}
        buffers[buf][#buffers[buf] + 1] = win
      end
    end
    for buf, wins in pairs(buffers) do md.render({ buf = buf, win = wins }) end
  end
  vim.api.nvim_set_decoration_provider(vim.api.nvim_create_namespace('markdown-viewport'), {
    on_win = function(_, win, buf, top, bottom)
      if not filetypes[vim.bo[buf].filetype] then
        views[win] = nil
        return false
      end
      local width = vim.api.nvim_win_get_width(win)
      local previous = views[win]
      if not previous or previous.buf ~= buf or previous.top ~= top
          or previous.bottom ~= bottom or previous.width ~= width then
        views[win] = { buf = buf, top = top, bottom = bottom, width = width }
        pending[win] = buf
        if not scheduled then
          scheduled = true
          -- UFO can change the bottom buffer row without changing topline,
          -- cursor or changedtick. WinScrolled does not report that change.
          -- Observe the real view during redraw, but set extmarks only later.
          vim.schedule(flush)
        end
      end
      return false
    end,
  })
  local group = vim.api.nvim_create_augroup('MarkdownViewport', { clear = true })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    callback = function(ev)
      local win = tonumber(ev.match)
      views[win], pending[win] = nil, nil
    end,
  })
end

return M
