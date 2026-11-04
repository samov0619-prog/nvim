-- Local Kitty transport and pixel/cell geometry; no rendering subprocesses.
local M = {}
local terminal_path = '/dev/tty'

function M.cell_size()
  local ok, ffi = pcall(require, 'ffi')
  if not ok then return nil, 'LuaJIT FFI is unavailable' end
  local system = vim.uv.os_uname().sysname
  local request = ({ Linux = 0x5413, Darwin = 0x40087468 })[system]
  if not request then return nil, 'Unsupported terminal platform: ' .. system end
  ffi.cdef[[
    int open(const char *pathname, int flags, ...);
    int close(int fd);
    int ioctl(int fd, unsigned long request, ...);
    char *ttyname(int fd);
  ]]
  local paths = { '/dev/tty' }
  for fd = 0, 2 do
    local name = ffi.C.ttyname(fd)
    if name ~= nil then paths[#paths + 1] = ffi.string(name) end
  end
  -- A detached Neovim server may use its TUI parent's stdio, not unrelated ttys.
  if system == 'Linux' then
    for fd = 0, 2 do
      local name = vim.uv.fs_readlink('/proc/' .. vim.uv.os_getppid() .. '/fd/' .. fd)
      if name and name:match('^/dev/') then paths[#paths + 1] = name end
    end
  end
  for _, name in ipairs(paths) do
    local fd = ffi.C.open(name, 2)
    if fd >= 0 then
      local size = ffi.new('unsigned short[4]')
      local valid = ffi.C.ioctl(fd, request, size) == 0 and size[0] > 0 and size[1] > 0
        and size[2] > 0 and size[3] > 0
      ffi.C.close(fd)
      if valid then
        terminal_path = name
        return { width = tonumber(size[2]) / tonumber(size[1]), height = tonumber(size[3]) / tonumber(size[0]) }
      end
    end
  end
  return nil, 'Terminal did not report pixel geometry (TIOCGWINSZ)'
end

function M.send(text)
  local tty = assert(io.open(terminal_path, 'w'))
  local written, write_error = tty:write(text)
  local flushed, flush_error = tty:flush()
  local closed, close_error = tty:close()
  assert(written, write_error)
  assert(flushed, flush_error)
  assert(closed, close_error)
end

function M.graphics(command, payload)
  return '\27_G' .. command .. (payload and ';' .. payload or '') .. '\27\\'
end

-- Crop the source PNG in Kitty; all placement stays inside the float.
function M.geometry(iw, ih, columns, rows, cw, ch, zoom, x, y)
  local fit = math.min(columns * cw / iw, rows * ch / ih)
  local scale = fit * zoom
  local width = math.min(iw, columns * cw / scale)
  local height = math.min(ih, rows * ch / scale)
  x = math.max(0, math.min(iw - width, x))
  y = math.max(0, math.min(ih - height, y))
  local c = math.min(columns, math.max(1, math.floor(width * scale / cw)))
  local r = math.min(rows, math.max(1, math.floor(height * scale / ch)))
  return { x = math.floor(x), y = math.floor(y), w = math.max(1, math.floor(width)),
    h = math.max(1, math.floor(height)), c = c, r = r,
    left = math.floor((columns - c) / 2), top = math.floor((rows - r) / 2), scale = scale }
end

return M
