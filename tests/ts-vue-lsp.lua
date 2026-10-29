-- Install fixture dependencies OUTSIDE projects/config, then run with Fish:
-- set -lx NVIM_TS_VUE_FIXTURES /tmp/opencode/nvim-vue-fixtures
-- npm install --prefix $NVIM_TS_VUE_FIXTURES/vue2 --ignore-scripts vue@2.7.16 typescript@4.9.5
-- npm install --prefix $NVIM_TS_VUE_FIXTURES/vue3 --ignore-scripts vue@3.5.22 typescript@5.9.3
-- nvim -n --headless -u NONE -i NONE -l tests/ts-vue-lsp.lua
-- Requires the three Mason packages described in doc/ts-toolchain.md.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/nvim-lspconfig")
vim.o.hidden, vim.o.swapfile, vim.o.backup, vim.o.writebackup = true, false, false, false
local fixtures = assert(vim.env.NVIM_TS_VUE_FIXTURES, "Set NVIM_TS_VUE_FIXTURES to the fixture dependencies directory")
local directory = "/tmp/opencode/ts-vue-lsp-" .. vim.fn.getpid()
assert(not vim.uv.fs_stat(directory), "Test directory already exists")
local api = vim.api
local notices = {}
vim.notify = function(message) notices[#notices + 1] = tostring(message) end
local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(vim.split(text, "\n", { plain = true }), path)
end
local function wait(predicate, label)
  assert(vim.wait(30000, predicate, 20), label .. "\n" .. vim.inspect(notices))
end
local tools = require("config.ts-toolchain")
tools.setup({ profiles_file = directory .. "/overrides.json" })
vim.lsp.config("ts_ls", { init_options = { tsserver = { logDirectory = directory .. "/logs", logVerbosity = "verbose" } } })
vim.lsp.enable({ "ts_ls", "vue_ls" })
local function client(bufnr, name)
  for _, item in ipairs(vim.lsp.get_clients({ bufnr = bufnr, name = name })) do
    if item.initialized then return item end
  end
end
local function open(path, ft)
  vim.cmd.edit(vim.fn.fnameescape(path))
  vim.bo.filetype = ft
  local buf = api.nvim_get_current_buf()
  wait(function() return client(buf, "ts_ls") and (ft ~= "vue" or client(buf, "vue_ls")) end, "Attach " .. path)
  return buf
end
local function position(buf, row, word)
  local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  return { line = row, character = assert(line:find(word, 1, true)) - 1 + 2 }
end
local function request(server, buf, method, pos, extra)
  local params = vim.tbl_extend("force", {
    textDocument = { uri = vim.uri_from_bufnr(buf) }, position = pos,
  }, extra or {})
  local result = server:request_sync(method, params, 15000, buf)
  assert(result and not result.err, method .. ": " .. vim.inspect(result))
  return result.result
end

vim.fn.mkdir(directory .. "/.git", "p")
write(directory .. "/package.json", '{"private":true}')
local apps = {}
for _, profile in ipairs({ "vue2", "vue3" }) do
  local dir = directory .. "/packages/" .. profile
  local deps = fixtures .. "/" .. profile .. "/node_modules"
  assert(vim.uv.fs_stat(deps .. "/typescript/lib/tsserver.js"), "Install fixture dependencies for " .. profile)
  write(dir .. "/package.json", '{"dependencies":{"vue":"*"},"devDependencies":{"typescript":"*"}}')
  assert(vim.uv.fs_symlink(deps, dir .. "/node_modules"))
  write(dir .. "/tsconfig.json", vim.json.encode({
    compilerOptions = { target = "ES2020", module = "ESNext", moduleResolution = "Node", strict = true,
      skipLibCheck = true, noEmit = true, esModuleInterop = true },
    include = { "src/**/*" },
  }))
  local import = profile == "vue2" and "import Vue from 'vue'" or "import { defineComponent } from 'vue'"
  local component = profile == "vue2" and "Vue.extend" or "defineComponent"
  local source = table.concat({
    "<template><div>{{ message.toUpperCase() }}</div></template>",
    '<script lang="ts">',
    import,
    "export default " .. component .. "({",
    "  data() { return { message: '" .. profile .. "' } },",
    "  methods: { shout() { return this.message.toUpperCase() } }",
    "})",
    "</script>",
  }, "\n")
  write(dir .. "/src/App.vue", source)
  write(dir .. "/src/other.ts", "export const ordinary: string = 'ok'")
  if profile == "vue2" then
    local initial = tools.resolve_path(dir .. "/src/App.vue", "vue")
    if initial.error and initial.error:match("reliable template types") then
      -- Deliberately opt into an editor-only SDK for this fixture. Production
      -- never performs this replacement automatically; project TS stays 4.9.
      write(directory .. "/overrides.json", vim.json.encode({
        [dir] = { tsdk = fixtures .. "/vue3/node_modules/typescript/lib" },
      }))
      print("PASS: TS 4.9 is rejected for Vue; fixture explicitly selects editor TS 5.9 without changing project dependencies")
    end
  end
  local buf = open(dir .. "/src/App.vue", "vue")
  local ts, vue = client(buf, "ts_ls"), client(buf, "vue_ls")
  local ctx = tools.resolve(buf)
  assert(not ctx.error and ctx.profile == profile, vim.inspect(ctx))
  assert(ts.config._ts_toolchain.identity == vue.config._ts_toolchain.identity)
  wait(function() return ts._ts_toolchain_version ~= nil end, "Report actual TypeScript version")
  assert(ts._ts_toolchain_version.version == ctx.typescript.version)
  local hover, next_hover = nil, 0
  wait(function()
    local now = vim.uv.hrtime()
    if now < next_hover then return false end
    next_hover = now + 500000000
    hover = request(ts, buf, "textDocument/hover", position(buf, 0, "message"))
    return hover and hover ~= vim.NIL and vim.inspect(hover):find("string", 1, true)
  end, profile .. " template hover must infer message: string")
  local definition = request(ts, buf, "textDocument/definition", position(buf, 0, "message"))
  assert(definition and #definition > 0, profile .. " template -> script definition")
  local rename = request(ts, buf, "textDocument/rename", position(buf, 4, "message"), { newName = "renamedMessage" })
  local edits = rename and rename ~= vim.NIL and rename.changes and rename.changes[vim.uri_from_bufnr(buf)]
  assert(edits and #edits >= 3, profile .. " rename must include template, data and method: " .. vim.inspect(rename))
  local completion = request(ts, buf, "textDocument/completion", { line = 0, character = 26 })
  local has_string_method = false
  for _, item in ipairs(completion and completion ~= vim.NIL and (completion.items or completion) or {}) do
    if item.label == "toUpperCase" then has_string_method = true end
  end
  assert(has_string_method, profile .. " template completion must include string.toUpperCase")
  local forwarded, response = 0, nil
  local exec = ts.exec_cmd
  ts.exec_cmd = function(self, command, ...)
    if command.command == "typescript.tsserverRequest" then forwarded = forwarded + 1 end
    return exec(self, command, ...)
  end
  local notify = vue.notify
  vue.notify = function(self, method, params)
    if method == "tsserver/response" and params[1][1] == 2147483000 then response = params[1][2] end
    return notify(self, method, params)
  end
  -- Deterministically exercise the inherited bridge with a real tsserver
  -- request/response; semantic tokens may already be cached by auto-highlighting.
  vue.handlers["tsserver/request"](nil, {
    { 2147483000, "_vue:projectInfo", { file = api.nvim_buf_get_name(buf), needFileNameList = false } },
  }, { client_id = vue.id, bufnr = buf })
  wait(function() return forwarded > 0 and response ~= nil end, "Official Vue -> ts_ls request forwarding")
  assert(response.configFileName == dir .. "/tsconfig.json", vim.inspect(response))
  vue.notify, ts.exec_cmd = notify, exec
  local other = open(dir .. "/src/other.ts", "typescript")
  assert(client(other, "ts_ls").id == ts.id, "Same package must reuse TS client")
  assert(client(other, "vue_ls") == nil, "Vue server only attaches to .vue")
  apps[#apps + 1] = { buf = buf, ts = ts, vue = vue, dir = dir }
  print("PASS: " .. profile .. ", TS " .. ctx.typescript.version .. ", Vue tools " .. ctx.vue_toolchain_version
    .. ": template hover, definition, completion, rename, official forwarding and client reuse")
end
assert(apps[1].ts.id ~= apps[2].ts.id and apps[1].vue.id ~= apps[2].vue.id)
assert(#vim.lsp.get_clients({ bufnr = apps[1].buf, name = "ts_ls" }) == 1)
assert(#vim.lsp.get_clients({ bufnr = apps[2].buf, name = "vue_ls" }) == 1)
print("PASS: Vue 2 and Vue 3 coexist in one workspace without duplicate or cross-profile clients")

for _, app in ipairs(apps) do
  api.nvim_buf_set_lines(app.buf, 0, 1, false, { "<template><div>{{ message.noSuchMethod() }}</div></template>" })
  wait(function()
    for _, diagnostic in ipairs(vim.diagnostic.get(app.buf)) do
      if diagnostic.code == 2339 or diagnostic.code == "2339" then return true end
    end
  end, "Unsaved Vue template type error for " .. app.dir)
  local info = tools.info(app.buf)
  assert(#info.clients == 2 and info.clients[1].matches and info.clients[2].matches)
end
print("PASS: both profiles publish template type errors for unsaved buffers; diagnostic info matches actual clients")

local plain = directory .. "/packages/plain"
write(plain .. "/package.json", "{}")
write(plain .. "/src/plain.js", "const value = 1")
local plain_buf = open(plain .. "/src/plain.js", "javascript")
assert(#client(plain_buf, "ts_ls").config.init_options.plugins == 0)
assert(client(plain_buf, "vue_ls") == nil)
print("PASS: plain JS uses Mason's fallback TypeScript without a Vue plugin")

for _, item in ipairs(vim.lsp.get_clients()) do item:stop() end
wait(function() return #vim.lsp.get_clients() == 0 end, "Stop test clients")
vim.fn.delete(directory, "rf")
print("All TS/Vue LSP integration tests passed")
