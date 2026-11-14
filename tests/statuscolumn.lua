-- Run: nvim -n --headless -u NONE -i NONE -l tests/statuscolumn.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local child = vim.fn.jobstart({ vim.v.progpath, '--embed', '--headless', '-n', '-u', 'NONE', '-i', 'NONE' }, { rpc = true })
local function lua(code, ...)
  return vim.rpcrequest(child, 'nvim_exec_lua', code, { ... })
end

local ok, err = xpcall(function()
  vim.rpcrequest(child, 'nvim_ui_attach', 80, 24, { rgb = true })
  lua([[
    local root = ...
    vim.opt.rtp:prepend(vim.fn.stdpath('data') .. '/lazy/statuscol.nvim')
    vim.o.number, vim.o.relativenumber, vim.o.numberwidth = true, false, 1
    vim.o.foldcolumn, vim.o.signcolumn = '0', 'yes:1'
    vim.o.laststatus, vim.o.showtabline, vim.o.wrap = 0, 0, false
    local spec = dofile(root .. '/lua/plugins/statuscol-nvim.lua')[1]
    local ns = vim.api.nvim_create_namespace('vim.diagnostic.test/signs')
    for _, case in ipairs({
      { count = 12, top = 1, rows = { 6, 9, 10, 12 }, digits = 2 },
      -- One-digit numbers in a three-digit buffer exposed %l's implicit spacer.
      { count = 120, top = 1, rows = { 6, 9, 10, 12 }, digits = 3 },
      { count = 120, top = 97, rows = { 97, 99, 100, 102 }, digits = 3 },
    }) do
      vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.fn['repeat']({ 'CODE' }, case.count))
      vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
      for row = 0, case.count - 1 do
        vim.api.nvim_buf_set_extmark(0, ns, row, 0, {
          sign_text = 'W', sign_hl_group = 'SignColumn', priority = 100,
        })
      end
      require('statuscol').setup(spec.opts())
      vim.api.nvim_win_set_cursor(0, { case.top, 0 })
      vim.cmd('normal! zt')
      vim.cmd('redraw!')
      for _, lnum in ipairs(case.rows) do
        local cells = {}
        local expected = ' W ' .. tostring(lnum)
          .. (' '):rep(case.digits - #tostring(lnum) + 1) .. 'CODE'
        for col = 1, #expected do
          cells[#cells + 1] = vim.fn.screenstring(lnum - case.top + 1, col)
        end
        local actual = table.concat(cells)
        assert(actual == expected, ('line %d/%d: expected %q, got %q')
          :format(lnum, case.count, expected, actual))
      end
    end

    vim.api.nvim_win_set_cursor(0, { 97, 0 })
    local segments = spec.opts().segments
    local format = segments[#segments].text[1]
    for _, case in ipairs({
      { nu = true, rnu = false, row = 100, expected = '100' },
      { nu = true, rnu = true, row = 100, expected = '3  ' },
      { nu = true, rnu = true, row = 97, expected = '97 ' },
      { nu = false, rnu = true, row = 97, expected = '0  ' },
      { nu = false, rnu = false, row = 97, expected = '   ' },
    }) do
      vim.wo.number, vim.wo.relativenumber = case.nu, case.rnu
      local actual = vim.api.nvim_eval_statusline(format, {
        use_statuscol_lnum = case.row, maxwidth = 3,
      }).str
      assert(actual == case.expected, vim.inspect({ case = case, actual = actual }))
    end
  ]], root)
end, debug.traceback)
vim.fn.jobstop(child)
if not ok then error(err) end
print('PASS: 12 rendered rows align left; absolute, relative and hidden numbers work')
