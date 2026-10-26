local M = {}
local warned = {}

local biome_markers = { "biome.json", "biome.jsonc" }
local eslint_flat_markers = {
  "eslint.config.js", "eslint.config.cjs", "eslint.config.mjs",
  "eslint.config.ts", "eslint.config.cts", "eslint.config.mts",
}
local eslint_legacy_markers = {
  ".eslintrc", ".eslintrc.js", ".eslintrc.cjs", ".eslintrc.json",
  ".eslintrc.yaml", ".eslintrc.yml",
}
local prettier_markers = {
  ".prettierrc", ".prettierrc.json", ".prettierrc.yml", ".prettierrc.yaml", ".prettierrc.json5",
  ".prettierrc.js", ".prettierrc.cjs", ".prettierrc.mjs", ".prettierrc.ts", ".prettierrc.cts",
  ".prettierrc.mts", ".prettierrc.toml", "prettier.config.js", "prettier.config.cjs",
  "prettier.config.mjs", "prettier.config.ts", "prettier.config.cts", "prettier.config.mts",
}
local stylelint_markers = {
  ".stylelintrc", ".stylelintrc.json", ".stylelintrc.yml", ".stylelintrc.yaml",
  ".stylelintrc.js", ".stylelintrc.cjs", ".stylelintrc.mjs",
  "stylelint.config.js", "stylelint.config.cjs", "stylelint.config.mjs",
  "stylelint.config.ts", "stylelint.config.cts", "stylelint.config.mts",
}
local biome_filetypes = {
  javascript = true,
  javascriptreact = true,
  typescript = true,
  typescriptreact = true,
  json = true,
  jsonc = true,
  css = true,
  scss = true,
  yaml = true,
  markdown = true,
  graphql = true,
  html = true,
  vue = true,
}
local eslint_filetypes = {
  javascript = true, javascriptreact = true, typescript = true, typescriptreact = true, vue = true,
}
local python_markers = {
  "pyproject.toml", "pyrightconfig.json", "setup.py", "setup.cfg", "requirements.txt", "Pipfile",
  "ruff.toml", ".ruff.toml",
}
local ruff_markers = { ".ruff.toml", "ruff.toml", "pyproject.toml" }
M.format_filetypes = biome_filetypes

-- Autocommands can outlive their buffer: an earlier nested callback may wipe
-- it (for example, MiniFiles returning to a previously visited directory).
-- Use buffer properties rather than a list of plugin-specific filetypes.
function M.is_file_buffer(bufnr)
  local api = vim.api
  if not bufnr or bufnr == 0 then bufnr = api.nvim_get_current_buf() end
  if not api.nvim_buf_is_valid(bufnr) or not api.nvim_buf_is_loaded(bufnr)
      or vim.bo[bufnr].buftype ~= "" then return false end
  local name = api.nvim_buf_get_name(bufnr)
  if name == "" or name:match("^%a[%w+.-]*://") then return false end
  local stat = vim.uv.fs_stat(name)
  -- A missing file is still a valid BufNewFile tooling context.
  return not stat or stat.type == "file"
end

-- Historical buffers stay read-only tooling contexts even outside their view.
-- A local file is a review context only while displayed in the active diff tab.
function M.in_review(bufnr)
  local api = vim.api
  if not bufnr or bufnr == 0 then bufnr = api.nvim_get_current_buf() end
  if not api.nvim_buf_is_valid(bufnr) then return false end
  local name = api.nvim_buf_get_name(bufnr)
  if name:match("^diffview://") or name:match("^merge%-preview[^:]*://") then return true end
  local lib = package.loaded["diffview.lib"]
  local view = lib and lib.get_current_view()
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_buf(win) == bufnr and (vim.wo[win].diff or view ~= nil) then return true end
  end
  return false
end

local function parent(dir)
  local up = vim.fs.dirname(dir)
  return up ~= dir and up or nil
end

local function project_directories(dirname, ft)
  local dirs, dir = {}, dirname
  local home = vim.uv.os_homedir()
  while dir and dir ~= home and dir ~= "/" do
    dirs[#dirs + 1] = dir
    -- fs_stat accepts both the directory and worktree's .git file.
    if vim.uv.fs_stat(vim.fs.joinpath(dir, ".git")) then return dirs end
    dir = parent(dir)
  end
  -- Without Git, the nearest language-specific project is the boundary.
  local markers = ft == "python" and python_markers or { "package.json" }
  for i, candidate in ipairs(dirs) do
    for _, marker in ipairs(markers) do
      if vim.fn.filereadable(vim.fs.joinpath(candidate, marker)) == 1 then
        return vim.list_slice(dirs, 1, i)
      end
    end
  end
  return dirs[1] and { dirs[1] } or {}
end

local function read_package(dir)
  local ok, lines = pcall(vim.fn.readfile, vim.fs.joinpath(dir, "package.json"))
  if not ok then return nil end
  local decoded, value = pcall(vim.json.decode, table.concat(lines, "\n"))
  return decoded and type(value) == "table" and value or nil
end

function M.project(bufnr)
  local valid = vim.api.nvim_buf_is_valid(bufnr)
  local filename = valid and vim.api.nvim_buf_get_name(bufnr) or ""
  local dirname = filename ~= "" and vim.fs.dirname(filename) or vim.fn.getcwd()
  local ft = valid and vim.bo[bufnr].filetype or ""
  local dirs = M.is_file_buffer(bufnr) and project_directories(dirname, ft) or {}
  local ctx = {
    filename = filename,
    dirname = dirname,
    dirs = dirs,
    boundary = dirs[#dirs] or dirname,
    packages = {},
    ft = ft,
    lsp = {},
    linters = {},
  }
  if ctx.ft:match("^yaml%.") then ctx.ft = "yaml" end
  for _, dir in ipairs(dirs) do ctx.packages[dir] = read_package(dir) end
  return ctx
end

local function find_config(ctx, markers, package_key)
  for _, dir in ipairs(ctx.dirs) do
    for _, marker in ipairs(markers) do
      local path = vim.fs.joinpath(dir, marker)
      if vim.fn.filereadable(path) == 1 then return { path = path, root = dir, marker = marker } end
    end
    local pkg = ctx.packages[dir]
    if package_key and pkg and pkg[package_key] ~= nil then
      return { path = vim.fs.joinpath(dir, "package.json"), root = dir, marker = "package.json" }
    end
  end
end

function M.find_config(bufnr, markers)
  return find_config(M.project(bufnr), markers)
end

local function dependency(ctx, name)
  for _, dir in ipairs(ctx.dirs) do
    local pkg = ctx.packages[dir]
    for _, group in ipairs({ "dependencies", "devDependencies", "optionalDependencies", "peerDependencies" }) do
      if pkg and type(pkg[group]) == "table" and pkg[group][name] then return dir end
    end
  end
end

function M.executable(name, dirname, boundary)
  local dirs = project_directories(dirname)
  for _, dir in ipairs(dirs) do
    local candidate = vim.fs.joinpath(dir, "node_modules", ".bin", name)
    if vim.fn.executable(candidate) == 1 then return candidate, dir end
    if dir == boundary then break end
  end
  local mason = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin", name)
  if vim.fn.executable(mason) == 1 then return mason end
  local path = vim.fn.exepath(name)
  return path ~= "" and path or nil
end

local function provider(ctx, id, label, config, executable)
  local cmd, bin_root = M.executable(executable, ctx.dirname, ctx.boundary)
  return {
    id = id,
    name = label,
    config = config.path,
    cwd = config.root,
    cmd = cmd,
    bin_root = bin_root,
  }
end

function M.biome_client_matches(client, tool)
  local config = client.config
  local cmd = config._code_tools_cmd
      or (type(config.cmd) == "table" and vim.fn.exepath(config.cmd[1]))
  return client.name == "biome" and client.config.root_dir == tool.cwd
      and cmd == tool.cmd
end

local function bounded_editorconfig(ctx)
  -- Prettier's EditorConfig search has no stop-directory option. Enable it
  -- only when an in-project root=true will stop it before leaving the project.
  for _, dir in ipairs(ctx.dirs) do
    local ok, lines = pcall(vim.fn.readfile, vim.fs.joinpath(dir, ".editorconfig"))
    if ok then
      for _, line in ipairs(lines) do
        if line:match("^%s*%[") then break end
        if line:lower():match("^%s*root%s*=%s*true%s*$") then return true end
      end
    end
  end
  return false
end

local function python_tools(ctx)
  local cmd
  for _, dir in ipairs(ctx.dirs) do
    local candidate = vim.fs.joinpath(dir, ".venv", "bin", "ruff")
    if vim.fn.executable(candidate) == 1 then cmd = candidate; break end
  end
  cmd = cmd or M.executable("ruff", ctx.dirname, ctx.boundary)
  local config = find_config(ctx, ruff_markers)
  local tool = { name = "Ruff", cmd = cmd, cwd = ctx.boundary, config = config and config.path }
  -- Let Ruff discover its configuration natively: a nearer pyproject.toml
  -- without [tool.ruff] must not hide an ancestor's Ruff settings.
  ctx.config_files = {}
  for _, dir in ipairs(ctx.dirs) do
    for _, marker in ipairs(ruff_markers) do
      ctx.config_files[#ctx.config_files + 1] = vim.fs.joinpath(dir, marker)
    end
  end
  ctx.profile = "python"
  ctx.formatter = vim.tbl_extend("force", tool, {
    id = "ruff_format", args = { "format", "--stdin-filename", ctx.filename, "-" },
  })
  ctx.linter = vim.tbl_extend("force", tool, {
    id = "ruff", args = { "check", "--force-exclude", "--stdin-filename", ctx.filename },
    fix_stdout = true,
    fix_args = { "check", "--fix", "--exit-zero", "--no-unsafe-fixes", "--stdin-filename", ctx.filename, "-" },
  })
  ctx.linters[1] = ctx.linter
  return ctx
end

function M.resolve(bufnr)
  local ctx = M.project(bufnr)
  if not M.is_file_buffer(bufnr) then return ctx end
  if ctx.ft == "python" then return python_tools(ctx) end
  local biome = find_config(ctx, biome_markers)
  local eslint = find_config(ctx, eslint_flat_markers)
      or find_config(ctx, eslint_legacy_markers, "eslintConfig")
  local prettier = find_config(ctx, prettier_markers, "prettier")
  local prettier_dep = dependency(ctx, "prettier")
  local stylelint = find_config(ctx, stylelint_markers, "stylelint")
  ctx.profile = biome and "biome" or (eslint and "eslint" or (prettier or prettier_dep) and "prettier" or nil)

  if biome and (eslint or dependency(ctx, "eslint") or prettier or prettier_dep) and not warned[ctx.boundary] then
    warned[ctx.boundary] = true
    vim.notify("Biome and ESLint/Prettier found in " .. ctx.boundary .. "; using Biome", vim.log.levels.WARN)
  end

  if biome then
    local tool = provider(ctx, "biome", "Biome", biome, "biome")
    ctx.lsp.biome = vim.deepcopy(tool)
    -- A shared config can cover packages with different Biome installations.
    -- Narrow the LSP workspace to the binary's scope, keeping config discovery
    -- inside the same project. CLI cwd stays at the config root for its globs.
    if tool.bin_root and #tool.bin_root > #tool.cwd then ctx.lsp.biome.cwd = tool.bin_root end
    if M.format_filetypes[ctx.ft] then
      ctx.formatter = vim.deepcopy(tool)
      ctx.formatter.args = { "format", "--stdin-file-path", ctx.filename, "--config-path", biome.path }
    end
  elseif ctx.ft ~= "html" and M.format_filetypes[ctx.ft] and (prettier or prettier_dep) then
    local config = prettier or { path = nil, root = prettier_dep }
    ctx.formatter = provider(ctx, "prettier", "Prettier", config, "prettier")
    ctx.formatter.args = { "--stdin-filepath", ctx.filename }
    if prettier then
      vim.list_extend(ctx.formatter.args, { "--config", prettier.path })
    else
      ctx.formatter.args[#ctx.formatter.args + 1] = "--no-config"
    end
    if not bounded_editorconfig(ctx) then ctx.formatter.args[#ctx.formatter.args + 1] = "--no-editorconfig" end
  end

  if (ctx.ft == "css" or ctx.ft == "scss") and stylelint then
    ctx.linter = provider(ctx, "stylelint", "Stylelint", stylelint, "stylelint")
    ctx.linter.args = { "--config", stylelint.path }
    ctx.linter.fix_args = vim.list_extend(vim.deepcopy(ctx.linter.args), { "--fix", ctx.filename })
    ctx.lsp.stylelint_lsp = ctx.linter
  elseif biome and biome_filetypes[ctx.ft] then
    ctx.linter = provider(ctx, "biomejs", "Biome", biome, "biome")
  elseif not biome and eslint and eslint_filetypes[ctx.ft] then
    local legacy = not eslint.marker:match("^eslint%.config%.")
    -- eslint_d invokes ESLint's flat-config API; legacy configs need the CLI.
    ctx.linter = provider(ctx, "eslint_d", "ESLint", eslint, legacy and "eslint" or "eslint_d")
    local daemon = not legacy and ctx.linter.cmd ~= nil
    ctx.linter.cmd = ctx.linter.cmd or M.executable("eslint", ctx.dirname, ctx.boundary)
    local package = find_config(ctx, { "package.json" }) or eslint
    -- Keep config globs relative to the config root, while eslint_d resolves
    -- the target package's ESLint version in a monorepo.
    ctx.linter.env = { ESLINT_D_ROOT = package.root, ESLINT_USE_FLAT_CONFIG = legacy and "false" or "true" }
    ctx.linter.args = { legacy and "--no-eslintrc" or "--no-config-lookup", "--config", eslint.path }
    if daemon then
      -- Killing eslint_d's client cannot cancel work in its daemon. Only ask
      -- for text; the editor owns the guarded write after a successful reply.
      ctx.linter.fix_stdout = true
      ctx.linter.fix_args = vim.list_extend(vim.deepcopy(ctx.linter.args), {
        "--fix-to-stdout", "--stdin", "--stdin-filename", ctx.filename,
      })
    else
      ctx.linter.fix_args = vim.list_extend(vim.deepcopy(ctx.linter.args), { "--fix", ctx.filename })
    end
    ctx.lsp.eslint = ctx.linter
  elseif ctx.ft == "yaml" then
    local config = find_config(ctx, { ".yamllint", ".yamllint.yaml", ".yamllint.yml" })
    if config then
      ctx.linter = provider(ctx, "yamllint", "yamllint", config, "yamllint")
      ctx.linter.args = { "--config-file", config.path }
    end
  elseif ctx.ft == "php" then
    local config = find_config(ctx, { "phpstan.neon", "phpstan.neon.dist", "phpstan.dist.neon" })
    if config then
      ctx.linter = provider(ctx, "phpstan", "PHPStan", config, "phpstan")
      local local_bin = find_config(ctx, { "vendor/bin/phpstan" })
      if local_bin and vim.fn.executable(local_bin.path) == 1 then ctx.linter.cmd = local_bin.path end
      ctx.linter.args = { "analyze", "--configuration", config.path, "--error-format=json", "--no-progress" }
    end
  end
  if ctx.linter then ctx.linters[1] = ctx.linter end
  if biome and biome_filetypes[ctx.ft] then
    local check = ctx.linter
    if check.id ~= "biomejs" then
      check = provider(ctx, "biomejs", "Biome", biome, "biome")
      ctx.linters[#ctx.linters + 1] = check
    end
    check.args = { "check", "--config-path", biome.path }
    -- Stylelint owns CSS linting; Biome still checks formatting and assists.
    if ctx.linter.id == "stylelint" then check.args[#check.args + 1] = "--linter-enabled=false" end
    check.fix_args = vim.list_extend(vim.deepcopy(check.args), { "--write", ctx.filename })
    check.fix_formats = true
  end
  return ctx
end

return M
