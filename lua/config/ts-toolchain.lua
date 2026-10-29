local M = {}
local options = {}
local warned = {}
local filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "vue" }
local groups = { "dependencies", "devDependencies", "optionalDependencies", "peerDependencies" }
local locks = { "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lock", "bun.lockb" }

local function exists(path) return vim.uv.fs_stat(path) ~= nil end
local function is_deno(dir)
  return exists(dir .. "/deno.json") or exists(dir .. "/deno.jsonc") or exists(dir .. "/deno.lock")
end
local function normalize(path)
  path = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(path), ":p")):gsub("/+$", "")
  return vim.uv.fs_realpath(path) or path
end
local function contains(root, path) return path == root or vim.startswith(path, root .. "/") end
local function json(path)
  if not exists(path) then return nil end
  local ok, value = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"), { luanil = { object = true, array = true } })
  end)
  if ok and type(value) == "table" then return value end
  return nil, "Invalid JSON object: " .. path
end
local function declares(pkg, name)
  for _, group in ipairs(groups) do
    if pkg and type(pkg[group]) == "table" and pkg[group][name] then return true end
  end
  return false
end

-- Bound discovery at Git (including worktrees). Without Git, use a lockfile
-- workspace, then the nearest package; never pick up a home/global SDK.
local function directories(dirname)
  local dirs, nearest_package, workspace = {}, nil, nil
  local home = normalize(vim.uv.os_homedir())
  for dir in vim.fs.parents(dirname .. "/_") do
    if dir == "/" or dir == home then break end
    dirs[#dirs + 1] = dir
    if exists(dir .. "/package.json") then nearest_package = nearest_package or #dirs end
    for _, lock in ipairs(locks) do
      if exists(dir .. "/" .. lock) then workspace = workspace or #dirs end
    end
    if exists(dir .. "/.git") or is_deno(dir) then return dirs end
  end
  return vim.list_slice(dirs, 1, workspace or nearest_package or 1)
end

local function profiles_file()
  return options.profiles_file or (vim.fn.stdpath("config") .. "/ts-toolchains.local.json")
end

local function override(dirname)
  local path = profiles_file()
  local profiles, err = json(path)
  if err then return nil, nil, err end
  local selected, selected_root
  for root, value in pairs(profiles or {}) do
    if type(root) ~= "string" or root:sub(1, 1) ~= "/" or type(value) ~= "table" then
      return nil, nil, "Expected absolute project paths mapped to objects in " .. path
    end
    root = normalize(root)
    if contains(root, dirname) and (not selected_root or #root > #selected_root) then
      selected, selected_root = value, root
    end
  end
  return selected or {}, selected_root
end

local function sdk(path)
  path = normalize(path)
  if path:match("/tsserver%.js$") then path = vim.fs.dirname(path) end
  local pkg = json(vim.fs.dirname(path) .. "/package.json")
  if not pkg or type(pkg.version) ~= "string" then
    return nil, "No usable TypeScript SDK at " .. path .. " (expected lib/tsserver.js and package.json)"
  end
  local major = tonumber(pkg.version:match("^(%d+)"))
  if not major or major >= 7 then
    return nil, "TypeScript " .. pkg.version .. " is incompatible with ts_ls; use a tested SDK below 7 explicitly"
  end
  if not exists(path .. "/tsserver.js") then return nil, "No usable TypeScript SDK at " .. path .. " (missing tsserver.js)" end
  return { path = path, version = pkg.version }
end

local function package_bin(path, name)
  local pkg = json(path .. "/package.json")
  if not pkg then return end
  local bin = type(pkg.bin) == "table" and pkg.bin[name] or pkg.bin
  if type(bin) == "string" and exists(path .. "/" .. bin) then
    return normalize(path .. "/" .. bin), pkg.version
  end
end

local function editor_sdk_message(ctx, explicit, reason)
  local directory = options.editor_sdk_root or (vim.fn.stdpath("data") .. "/ts-editor-sdk")
  local path = directory .. "/node_modules/typescript/lib"
  local installed = sdk(path)
  local lines = { reason .. " (build TypeScript is unchanged)." }
  if not installed or tonumber(installed.version:match("^(%d+)")) < 5 then
    lines[#lines + 1] = "Install editor SDK: npm install --prefix " .. vim.fn.shellescape(directory)
      .. " --ignore-scripts --save-exact typescript@5.9.3"
  end
  local entry = { tsdk = path }
  if explicit.profile ~= nil then entry.profile = explicit.profile end
  lines[#lines + 1] = "In " .. profiles_file() .. ", add/merge (keep other entries):"
  lines[#lines + 1] = vim.json.encode({ [ctx.root] = entry })
  lines[#lines + 1] = "Then restart Neovim."
  return table.concat(lines, "\n")
end

-- Resolve from disk each time. Installing dependencies or changing an override
-- must take effect on LSP restart without reloading Lua or trusting stale caches.
function M.resolve_path(filename, ft)
  local dirname = normalize(vim.fs.dirname(filename))
  local ctx = { filename = filename, dirs = directories(dirname), profile = "none" }
  local function fail(message) ctx.error = message; return ctx end
  local explicit, explicit_root, err = override(dirname)
  if err then return fail(err) end
  local packages, root = {}, nil
  for _, dir in ipairs(ctx.dirs) do
    local pkg, problem = json(dir .. "/package.json")
    if problem then return fail(problem) end
    packages[dir] = pkg
    if pkg then root = root or dir end
  end
  ctx.root = root or ctx.dirs[#ctx.dirs] or dirname
  if explicit_root and contains(ctx.root, explicit_root) then ctx.root = explicit_root end
  for _, dir in ipairs(ctx.dirs) do
    if is_deno(dir) then
      ctx.disabled = "Deno project"
      return ctx
    end
  end

  -- Probe Node's ancestor node_modules layout. pnpm's symlinks work as-is;
  -- Yarn PnP can provide its generated SDK through an explicit tsdk override.
  local vue, project_sdk, vue_declared, ts_declared
  for _, dir in ipairs(ctx.dirs) do
    vue_declared = vue_declared or declares(packages[dir], "vue")
    ts_declared = ts_declared or declares(packages[dir], "typescript")
    if not vue then vue = json(dir .. "/node_modules/vue/package.json") end
    if not project_sdk and exists(dir .. "/node_modules/typescript/package.json") then
      project_sdk = dir .. "/node_modules/typescript/lib"
    end
  end
  ctx.vue_version = vue and vue.version
  if explicit.profile ~= nil then
    if not vim.tbl_contains({ "vue2", "vue3", "none" }, explicit.profile) then
      return fail("Unknown profile: " .. tostring(explicit.profile))
    end
    ctx.profile, ctx.profile_source = explicit.profile, "override: " .. explicit_root
  elseif vue and type(vue.version) == "string" then
    local major = vue.version:match("^(%d+)")
    if major ~= "2" and major ~= "3" then return fail("Unsupported Vue version: " .. vue.version) end
    ctx.profile, ctx.profile_source = major == "2" and "vue2" or "vue3", "installed Vue " .. vue.version
  elseif vue_declared then
    return fail("Vue is declared but not installed; install project dependencies or select a profile explicitly")
  end
  if ft == "vue" and ctx.profile == "none" then
    return fail("No Vue profile: install project dependencies or set vue2/vue3 in ts-toolchains.local.json")
  end

  local mason = options.mason_root or (vim.fn.stdpath("data") .. "/mason")
  local wrapper = mason .. "/packages/typescript-language-server/node_modules/typescript-language-server"
  ctx.wrapper, ctx.wrapper_version = package_bin(wrapper, "typescript-language-server")
  if not ctx.wrapper then return fail("Run :MasonInstall typescript-language-server") end
  ctx.node = vim.fn.exepath("node")
  if ctx.node == "" then return fail("Node.js is not available on PATH") end

  if ctx.profile ~= "none" then
    local package_name = ctx.profile == "vue2" and "vue-language-server-vue2" or "vue-language-server"
    local installation = mason .. "/packages/" .. package_name
    ctx.vue_server = installation .. "/node_modules/@vue/language-server"
    ctx.vue_cmd, ctx.vue_toolchain_version = package_bin(ctx.vue_server, "vue-language-server")
    if not ctx.vue_cmd then return fail("Run :MasonInstall " .. package_name) end
    -- Prefer the server's own dependency, not an unrelated top-level plugin.
    ctx.plugin = ctx.vue_server .. "/node_modules/@vue/typescript-plugin"
    if not exists(ctx.plugin .. "/package.json") then
      ctx.plugin = installation .. "/node_modules/@vue/typescript-plugin"
    end
    local plugin = json(ctx.plugin .. "/package.json")
    if not plugin or plugin.version ~= ctx.vue_toolchain_version then
      return fail("Vue server/plugin versions differ in " .. installation .. "; reinstall that Mason package")
    end
    ctx.plugin_version = plugin.version
    if ctx.profile == "vue2" and not ctx.vue_toolchain_version:match("^3%.0%.%d+$") then
      return fail("The Vue 2 profile requires a stable Vue toolchain 3.0.x")
    end
    -- vue_ls itself needs modern compiler/server APIs (TS 4.9's typescript.js
    -- lacks ts.server.protocol). This is NOT the tsserver analyzing the project:
    -- that process, including the Vue plugin, still uses the project's SDK.
    ctx.vue_typescript, err = sdk(installation .. "/node_modules/typescript/lib")
    if err then return fail(err) end
  end

  local tsdk = explicit.tsdk or project_sdk
  ctx.ts_source = explicit.tsdk and "override" or "project"
  if explicit.tsdk ~= nil and (type(explicit.tsdk) ~= "string" or explicit.tsdk:sub(1, 1) ~= "/") then
    return fail("tsdk must be an absolute path to typescript/lib or lib/tsserver.js")
  end
  if not tsdk then
    if ts_declared then return fail("TypeScript is declared but not installed; install project dependencies") end
    tsdk = mason .. "/packages/typescript-language-server/node_modules/typescript/lib"
    ctx.ts_source = "Mason fallback (no project TypeScript dependency)"
  end
  ctx.typescript, err = sdk(tsdk)
  if err then
    return fail(err:match("incompatible") and editor_sdk_message(ctx, explicit, err) or err)
  end
  -- Volar's current resolver probes .d.vue.ts, introduced with TS 5's arbitrary
  -- extension resolution. With TS 4.9 the plugin loads but template/self-import
  -- inference silently degrades to any. Never pretend that this is working.
  if ctx.profile ~= "none" and tonumber(ctx.typescript.version:match("^(%d+)")) < 5 then
    return fail(editor_sdk_message(ctx, explicit,
      "Vue tools 3.x cannot provide reliable template types with TypeScript " .. ctx.typescript.version))
  end
  ctx.identity = vim.json.encode({ ctx.root, ctx.profile, ctx.wrapper, ctx.wrapper_version,
    ctx.vue_cmd or "", ctx.vue_toolchain_version or "", ctx.plugin or "", ctx.node,
    ctx.typescript.path, ctx.typescript.version,
    ctx.vue_typescript and ctx.vue_typescript.path or "", ctx.vue_typescript and ctx.vue_typescript.version or "" })
  return ctx
end

function M.resolve(bufnr)
  if not bufnr or bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  if not require("config.code-tools").is_file_buffer(bufnr) then return { disabled = "Not a file buffer" } end
  return M.resolve_path(vim.api.nvim_buf_get_name(bufnr), vim.bo[bufnr].filetype)
end

local function for_config(config)
  return M.resolve_path(config.root_dir .. "/__ts_toolchain__.ts", config.name == "vue_ls" and "vue" or nil)
end

function M.client_matches(client, config)
  if client:is_stopped() or client.name ~= config.name or client.config.root_dir ~= config.root_dir then return false end
  local ctx = for_config(config)
  local previous = client.config._ts_toolchain
  return not ctx.error and not ctx.disabled and previous ~= nil and previous.identity == ctx.identity
end

local function root_dir(name)
  return function(bufnr, on_dir)
    local ctx = M.resolve(bufnr)
    if ctx.error then
      local key = (ctx.root or "") .. ctx.error
      if not warned[key] then
        warned[key] = true
        vim.notify("TS/Vue: " .. ctx.error, vim.log.levels.WARN)
      end
    elseif not ctx.disabled and (name ~= "vue_ls" or ctx.profile ~= "none") then
      on_dir(ctx.root)
    end
  end
end

local function start(name)
  return function(dispatchers, config)
    local ctx = for_config(config)
    assert(not ctx.error and not ctx.disabled, ctx.error or ctx.disabled)
    config._ts_toolchain = ctx
    local cmd = { ctx.node, name == "ts_ls" and ctx.wrapper or ctx.vue_cmd, "--stdio" }
    if name == "vue_ls" then cmd[#cmd + 1] = "--tsdk=" .. ctx.vue_typescript.path end
    return vim.lsp.rpc.start(cmd, dispatchers, { cwd = ctx.root, env = config.cmd_env })
  end
end

function M.info(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ctx = M.resolve(bufnr)
  ctx.clients = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if client.name == "ts_ls" or client.name == "vue_ls" then
      ctx.clients[#ctx.clients + 1] = {
        name = client.name, id = client.id, root = client.config.root_dir,
        actual_typescript = client._ts_toolchain_version,
        matches = ctx.identity ~= nil and client.config._ts_toolchain ~= nil
          and client.config._ts_toolchain.identity == ctx.identity,
      }
    end
  end
  return ctx
end

function M.setup(opts)
  options = opts or {}
  warned = {}
  vim.lsp.config("ts_ls", {
    filetypes = filetypes,
    root_dir = root_dir("ts_ls"),
    cmd = start("ts_ls"),
    reuse_client = M.client_matches,
    before_init = function(params, config)
      local ctx = config._ts_toolchain
      -- Set both: replacing config.init_options alone is too late for initialize.
      config.init_options = vim.tbl_deep_extend("force", config.init_options or {}, {
        tsserver = { path = ctx.typescript.path .. "/tsserver.js" },
      })
      config.init_options.plugins = ctx.plugin and {
        { name = "@vue/typescript-plugin", location = ctx.vue_server, languages = { "vue" } },
      } or {}
      params.initializationOptions = config.init_options
    end,
    handlers = {
      ["$/typescriptVersion"] = function(_, result, context)
        local client = vim.lsp.get_client_by_id(context.client_id)
        if client then client._ts_toolchain_version = result end
      end,
    },
  })
  vim.lsp.config("vue_ls", {
    root_dir = root_dir("vue_ls"),
    cmd = start("vue_ls"),
    reuse_client = M.client_matches,
    -- Keep nvim-lspconfig's official tsserver/request forwarding on_init.
  })
  vim.api.nvim_create_user_command("TsToolchainInfo", function()
    vim.notify(vim.inspect(M.info()), vim.log.levels.INFO, { title = "TS / Vue toolchain" })
  end, { desc = "Show selected TS/Vue tools, SDK and attached clients", force = true })
end

return M
