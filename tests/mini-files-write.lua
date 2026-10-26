-- Run: nvim -n --headless -u NONE -i NONE -l tests/mini-files-write.lua
local source = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local root = vim.fn.fnamemodify(source, ":h:h")
local case = vim.env.MINIFILES_WRITE_CASE
if not case then
  local directory = vim.fn.tempname()
  for _, name in ipairs({ "open", "browse", "edited", "cancel", "write", "discard", "real-file" }) do
    local project = directory .. "/" .. name
    vim.fn.mkdir(project .. "/nested", "p")
    vim.fn.writefile({ "preview" }, project .. "/nested/file.txt")
    vim.fn.writefile({ "original" }, project .. "/original.txt")
    local result = vim.system({ vim.v.progpath, "-n", "--headless", "-u", "NONE", "-i", "NONE", "-l", source }, {
      text = true, env = { MINIFILES_WRITE_CASE = name, MINIFILES_WRITE_PROJECT = project },
    }):wait(10000)
    assert(result.code == 0, name .. ": " .. (result.stdout or "") .. (result.stderr or ""))
    assert((result.stderr or ""):find("READY: " .. name, 1, true), "Child must reach its real :qa: " .. name)
    print("PASS: " .. name)
  end
  vim.fn.delete(directory, "rf")
  print("All MiniFiles write/quit regression checks passed")
  vim.cmd("qa!")
  return
end

vim.opt.rtp:prepend(root)
for _, plugin in ipairs({ "mini.files", "mini.icons" }) do
  vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/" .. plugin)
end
vim.o.hidden, vim.o.swapfile = true, false
vim.o.lines, vim.o.columns = 55, 180
local api = vim.api
local project = assert(vim.env.MINIFILES_WRITE_PROJECT)
dofile(root .. "/lua/plugins/mini-files.lua")[1].config()
local mf = require("mini.files")
local real
if case == "real-file" then
  vim.cmd.edit(vim.fn.fnameescape(project .. "/original.txt"))
  real = api.nvim_get_current_buf()
end
vim.cmd.edit(vim.fn.fnameescape(project))
assert(vim.wait(3000, function() return vim.bo.filetype == "minifiles" end, 10), "Open MiniFiles")
local buf = api.nvim_get_current_buf()
-- Drain the initial programmatic TextChanged before simulating user input.
api.nvim_exec_autocmds("TextChanged", { buffer = buf })
local function clean()
  for _, b in ipairs(api.nvim_list_bufs()) do
    if vim.bo[b].filetype == "minifiles" then
      assert(not vim.bo[b].modified, "Unedited/refreshed MiniFiles buffer must be clean: " .. api.nvim_buf_get_name(b))
    end
  end
end
local function blocked()
  local ok, err = pcall(vim.cmd.qa)
  assert(not ok and tostring(err):match("E%d+: No write since last change"), "Unsaved edits must block :qa: " .. tostring(err))
end

if case == "open" then
  -- Execute real :qa without interception; the parent checks process success.
elseif case == "browse" then
  mf.go_in()
  mf.go_out()
  assert(mf.synchronize())
  clean()
elseif case == "real-file" then
  api.nvim_buf_set_lines(real, 0, -1, false, { "unsaved" })
  clean()
  blocked()
  assert(vim.bo[real].modified and vim.fn.readfile(project .. "/original.txt")[1] == "original")
else
  api.nvim_buf_set_lines(buf, -1, -1, false, { "created.txt" })
  api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  assert(vim.bo[buf].modified)
  if case == "edited" then
    mf.go_in()
    mf.go_out()
    mf.refresh()
    assert(vim.bo[buf].modified, "Navigation must not mark pending edits clean")
    blocked()
    assert(vim.fn.filereadable(project .. "/created.txt") == 0)
  else
    vim.fn.confirm = function() return case == "cancel" and 3 or case == "discard" and 2 or 1 end
    vim.cmd.write()
    if case == "cancel" then
      assert(vim.bo[buf].modified and vim.fn.filereadable(project .. "/created.txt") == 0)
      blocked()
    else
      clean()
      assert(vim.fn.filereadable(project .. "/created.txt") == (case == "write" and 1 or 0))
    end
  end
end

print("READY: " .. case)
if case == "edited" or case == "cancel" or case == "real-file" then vim.cmd("qa!")
else vim.cmd.qa() end
