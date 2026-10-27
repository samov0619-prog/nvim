-- Run: nvim -n --headless -u NONE -i NONE -l tests/mini-files-lsp.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
for _, plugin in ipairs({ "mini.files", "mini.icons" }) do
  vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/" .. plugin)
end
vim.o.hidden, vim.o.swapfile = true, false
vim.o.lines, vim.o.columns = 55, 180
local api = vim.api
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p")
local requests, notifications = {}, {}
local workspace_edit
local client = {
  name = "null-filter-test",
  server_capabilities = { workspace = { fileOperations = {} } },
  request_sync = function(_, method, params)
    requests[#requests + 1] = { method = method, params = vim.deepcopy(params) }
    return { result = method == "workspace/willRenameFiles" and workspace_edit or nil }
  end,
  notify = function(_, method, params)
    notifications[#notifications + 1] = { method = method, params = vim.deepcopy(params) }
  end,
}
local operations = client.server_capabilities.workspace.fileOperations
local get_clients = vim.lsp.get_clients
vim.lsp.get_clients = function(opts)
  if not opts then return { client } end
  local method = (opts.method or ""):match("workspace/(.+)Files")
  return method and operations[method] and { client } or {}
end
vim.fn.confirm = function() return 1 end
dofile(root .. "/lua/plugins/mini-files.lua")[1].config()
local mf = require("mini.files")
local function filters()
  -- Refresh capabilities between operations, as with dynamic registration.
  for _, method in ipairs({ "willRename", "didRename", "willDelete", "didDelete" }) do
    operations[method] = { filters = {
      vim.json.decode('{"scheme":null,"pattern":{"glob":"**","matches":null,"options":{"ignoreCase":null}}}'),
    } }
  end
end
local function change(path, new_name)
  mf.open(path, false)
  local buf = api.nvim_get_current_buf()
  api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  local row = api.nvim_win_get_cursor(0)[1]
  if new_name then
    local line = api.nvim_get_current_line()
    api.nvim_buf_set_lines(buf, row - 1, row, false, { line:sub(1, #line - #vim.fs.basename(path)) .. new_name })
  else
    api.nvim_buf_set_lines(buf, row - 1, row, false, {})
  end
  api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  vim.cmd.write()
  assert(not vim.bo[buf].modified, "Successful synchronization must leave the listing clean")
  mf.close()
end
for _, opened in ipairs({ false, true }) do
  local name = opened and "opened.zip" or "closed.zip"
  local path = directory .. "/" .. name
  vim.fn.writefile({ "archive fixture" }, path)
  if opened then vim.cmd("noautocmd edit " .. vim.fn.fnameescape(path)) end
  filters()
  change(path, "renamed-" .. name)
  local renamed = directory .. "/renamed-" .. name
  assert(vim.fn.filereadable(path) == 0 and vim.fn.filereadable(renamed) == 1)
  local request, notice = requests[#requests], notifications[#notifications]
  assert(request.method == "workspace/willRenameFiles" and notice.method == "workspace/didRenameFiles")
  assert(request.params.files[1].oldUri == vim.uri_from_fname(path))
  assert(request.params.files[1].newUri == vim.uri_from_fname(renamed))
  filters()
  change(renamed)
  assert(vim.fn.filereadable(renamed) == 0)
  assert(requests[#requests].method == "workspace/willDeleteFiles")
  assert(notifications[#notifications].method == "workspace/didDeleteFiles")
end
-- Valid restrictions must remain restrictions, rather than becoming wildcards.
operations.willRename = { filters = { { scheme = "https", pattern = { glob = "**", matches = "file" } } } }
operations.didRename = vim.deepcopy(operations.willRename)
local before = #requests
local path = directory .. "/restricted.zip"
vim.fn.writefile({ "fixture" }, path)
change(path, "restricted-renamed.zip")
assert(#requests == before + 1 and #requests[#requests].params.files == 0)
assert(operations.willRename.filters[1].scheme == "https")
-- Keep MiniFiles' native workspace-edit path: a rename may update imports.
local imports = directory .. "/imports.ts"
vim.fn.writefile({ "old import" }, imports)
workspace_edit = { changes = { [vim.uri_from_fname(imports)] = {
  { range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } }, newText = "new import" },
} } }
client.offset_encoding = "utf-16"
filters()
local code_path = directory .. "/code.ts"
vim.fn.writefile({ "export {}" }, code_path)
change(code_path, "renamed.ts")
local import_buf = vim.fn.bufnr(imports)
assert(import_buf > 0 and api.nvim_buf_get_lines(import_buf, 0, 1, false)[1] == "new import")
assert(vim.bo[import_buf].modified and vim.fn.readfile(imports)[1] == "old import", "Do not auto-save LSP edits")
vim.lsp.get_clients = get_clients
vim.fn.delete(directory, "rf")
print("PASS: MiniFiles LSP null filters, opened/closed ZIP rename/delete, strict schemes, and import edits")
vim.cmd("qa!")
