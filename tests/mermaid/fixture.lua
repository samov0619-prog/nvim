-- A valid PNG for file/header tests. Terminal transmission is mocked.
return function()
  local file = vim.fn.tempname() .. '.png'
  local png = vim.base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aK1cAAAAASUVORK5CYII=')
  local f = assert(io.open(file, 'wb'))
  assert(f:write(png))
  assert(f:close())
  vim.api.nvim_create_autocmd('VimLeavePre', { once = true, callback = function() vim.fn.delete(file) end })
  return file
end
