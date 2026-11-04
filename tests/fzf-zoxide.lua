-- Run: nvim -n --headless -u NONE -i NONE -l tests/fzf-zoxide.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local config, calls
-- Exercise the configured callbacks without launching fzf, changing cwd, or
-- opening MiniFiles. This is callback coverage, not an interactive picker test.
package.loaded["fzf-lua"] = {
  setup = function(opts) config = opts end,
  register_ui_select = function() end,
}
package.loaded["fzf-lua.utils"] = {}
package.loaded["fzf-lua.path"] = {}
package.loaded["mini.files"] = {
  open = function(path) calls[#calls + 1] = { "open", path } end,
}
for _, command in ipairs({ "cd", "tcd" }) do
  vim.cmd[command] = function(opts) calls[#calls + 1] = { command, opts } end
end
dofile(root .. "/lua/plugins/fzf-lua.lua")[1].config()

for _, key in ipairs({ "default", "`", "~" }) do
  local action = config.zoxide.actions[key]
  calls = {}
  action({}, {})
  assert(#calls == 0, key .. ": empty selection must not change cwd or open MiniFiles")

  for _, entry in ipairs({ root, "1.0\t" .. root }) do
    calls = {}
    action({ entry }, {})
    local expected = {
      { key == "~" and "tcd" or "cd", {
        args = { vim.fn.fnameescape(root) }, mods = { silent = true },
      } },
      { "open", root },
    }
    assert(vim.deep_equal(calls, expected), key .. ": selected directory must retain its action: " .. vim.inspect(calls))
  end
  print("PASS: " .. key .. " empty and selected directory callbacks")
end
print("All zoxide callback regression checks passed")
