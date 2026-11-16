-- Run: nvim -n --headless -u NONE -i NONE -l tests/lsp-keymaps.lua
-- Native LSP attachment/filtering with in-process capability fixtures, no server binaries.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/nvim-lspconfig')
package.loaded.lazydev = { setup = function() end }
local enable = vim.lsp.enable
vim.lsp.enable = function() end
dofile(root .. '/lua/plugins/nvim-lspconfig.lua')[1].config()
vim.lsp.enable = enable
local api = vim.api
api.nvim_buf_set_name(0, root .. '/tests/signature-fixture.nix')
vim.bo.filetype = 'nix'
local source = api.nvim_get_current_buf()
local notices, calls = {}, 0
vim.notify = function(message) notices[#notices + 1] = message end
local function start(name, signatures)
  return assert(vim.lsp.start({ name = name, root_dir = root, cmd = function(dispatchers)
    local closing = false
    return {
      request = function(method, _, callback)
        local result
        if method == 'initialize' then
          result = { capabilities = signatures and { signatureHelpProvider = { triggerCharacters = { '(' } } } or {} }
        elseif method == 'textDocument/signatureHelp' then
          calls = calls + 1
          result = { signatures = { { label = 'fixture(argument)' } } }
        end
        vim.schedule(function() callback(nil, result) end)
        return true, 1
      end,
      notify = function(method)
        if method == 'exit' then closing = true; dispatchers.on_exit(0, 0) end
        return true
      end,
      is_closing = function() return closing end,
      terminate = function() closing = true; dispatchers.on_exit(0, 0) end,
    }
  end }))
end
local function binding(mode)
  return assert(vim.fn.maparg('<C-s>', mode, false, true).callback, 'Buffer-local signature binding')
end
local unsupported = start('signature-unsupported-fixture', false)
assert(vim.wait(1000, function() return vim.fn.maparg('<C-s>', 'n') ~= '' end, 10), 'Native LspAttach installed mappings')
binding('n')()
binding('i')()
assert(calls == 0 and #notices == 0, 'Unsupported server is silent in Normal and Insert')
local supported = start('signature-supported-fixture', true)
assert(vim.wait(1000, function()
  return #vim.lsp.get_clients({ bufnr = source, method = 'textDocument/signatureHelp' }) == 1
end, 10), 'Native capability filter finds the supported client')
binding('n')()
assert(vim.wait(1000, function() return calls == 1 end, 10), 'Supported client receives the real signature request')
api.nvim_set_current_buf(source)
binding('i')()
assert(vim.wait(1000, function() return calls == 2 end, 10), 'Insert binding also sends the real signature request')
assert(vim.wait(1000, function()
  for _, win in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_config(win).relative ~= '' then
      local lines = api.nvim_buf_get_lines(api.nvim_win_get_buf(win), 0, -1, false)
      if table.concat(lines, '\n'):find('fixture(argument)', 1, true) then return true end
    end
  end
  return false
end, 10), 'Native signature handler displays the returned signature')
vim.lsp.get_client_by_id(supported):stop(true)
assert(vim.wait(1000, function()
  return #vim.lsp.get_clients({ bufnr = source, method = 'textDocument/signatureHelp' }) == 0
end, 10), 'Supported client detached')
api.nvim_set_current_buf(source)
binding('n')()
assert(calls == 2 and #notices == 0, 'Stale mapping after detach stays silent')
vim.lsp.get_client_by_id(unsupported):stop(true)
print('PASS: unsupported signatures are silent; supported/mixed clients still work; detach rechecks capabilities.')
