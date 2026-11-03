local M = {}
local projects = {}

-- Keep rustup shims intact (resolving symlinks would turn rustfmt into rustup).
-- All Rust subprocesses inherit the same project/Nix PATH, without Mason tools.
function M.environment()
  local mason = vim.fs.normalize(vim.fn.stdpath("data") .. "/mason")
  local paths = {}
  for _, path in ipairs(vim.split(vim.env.PATH or "", ":", { plain = true })) do
    local absolute = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
    local real = vim.uv.fs_realpath(absolute) or absolute
    if absolute ~= mason and not vim.startswith(absolute, mason .. "/")
        and real ~= mason and not vim.startswith(real, mason .. "/") then
      paths[#paths + 1] = absolute
    end
  end
  return { PATH = table.concat(paths, ":") }
end

function M.executable(name)
  for _, path in ipairs(vim.split(M.environment().PATH, ":", { plain = true })) do
    local candidate = vim.fs.joinpath(path, name)
    if vim.fn.executable(candidate) == 1 then return candidate end
  end
end

local function ancestors(dirname)
  local dirs, dir = {}, dirname
  while dir do
    dirs[#dirs + 1] = dir
    local up = vim.fs.dirname(dir)
    dir = up ~= dir and up or nil
  end
  return dirs
end

local function stamp(path)
  local stat = vim.uv.fs_stat(path)
  return stat and { path, stat.size, stat.mtime } or { path }
end

local function key(paths)
  local result = { M.environment().PATH, M.executable("cargo") or "", vim.env.RUSTUP_TOOLCHAIN or "", vim.env.RUSTUP_HOME or "",
    vim.env.CARGO_HOME or "", vim.env.RUSTC or "", vim.env.RUSTFLAGS or "" }
  for _, path in ipairs(paths) do result[#result + 1] = stamp(path) end
  return result
end

local function close_timer(entry)
  if entry.timer and not entry.timer:is_closing() then entry.timer:stop(); entry.timer:close() end
  entry.timer = nil
end

local function changed()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "rust" then
      vim.api.nvim_exec_autocmds("User", { pattern = "CodeProjectChanged", data = { bufnr = buf } })
    end
  end
end

-- Cargo, rather than a partial TOML parser, owns workspace membership, explicit
-- package.workspace paths, inherited editions and excluded/nested crates.
function M.project(dirname, callback)
  local dirs = ancestors(dirname)
  local manifest
  for _, dir in ipairs(dirs) do
    local path = vim.fs.joinpath(dir, "Cargo.toml")
    if vim.fn.filereadable(path) == 1 then manifest = path; break end
  end
  if not manifest then
    local result = { root = dirname, edition = "2021", paths = {}, standalone = true }
    if callback then callback(result) end
    return result
  end

  local entry = projects[manifest]
  local callbacks = {}
  if entry and not vim.deep_equal(entry.key, key(entry.paths)) then
    callbacks = entry.callbacks
    if entry.process then entry.process:kill(9) end
    close_timer(entry)
    projects[manifest] = nil
    entry = nil
  end
  if not entry then
    local paths = {}
    for _, dir in ipairs(ancestors(vim.fs.dirname(manifest))) do
      for _, name in ipairs({ "Cargo.toml", "Cargo.lock", "rust-toolchain", "rust-toolchain.toml",
        ".cargo/config", ".cargo/config.toml" }) do
        paths[#paths + 1] = vim.fs.joinpath(dir, name)
      end
    end
    entry = { root = vim.fs.dirname(manifest), manifest = manifest, paths = paths, pending = true, callbacks = callbacks }
    entry.key = key(paths)
    projects[manifest] = entry
    local cargo = M.executable("cargo")
    local function complete(output)
      vim.schedule(function()
        if projects[manifest] ~= entry or not entry.pending then return end
        entry.pending, entry.process = false, nil
        close_timer(entry)
        -- Never mark a reply as current if manifests changed while Cargo ran.
        if not vim.deep_equal(entry.key, key(entry.paths)) then
          projects[manifest] = nil
          M.project(dirname)
          for _, done in ipairs(entry.callbacks) do M.project(dirname, done) end
          return
        end
        local ok, metadata = pcall(vim.json.decode, output.stdout or "")
        if output.code == 0 and (output.signal or 0) == 0 and ok and type(metadata) == "table" and metadata.workspace_root then
          entry.root = vim.fs.normalize(metadata.workspace_root)
          for _, package in ipairs(metadata.packages or {}) do
            entry.paths[#entry.paths + 1] = package.manifest_path
            local path = vim.uv.fs_realpath(package.manifest_path) or vim.fs.normalize(package.manifest_path)
            if path == (vim.uv.fs_realpath(manifest) or manifest) then entry.edition = package.edition end
          end
          entry.paths[#entry.paths + 1] = vim.fs.joinpath(entry.root, "Cargo.toml")
          entry.paths[#entry.paths + 1] = vim.fs.joinpath(entry.root, "Cargo.lock")
          for _, name in ipairs({ "rust-toolchain", "rust-toolchain.toml", ".cargo/config", ".cargo/config.toml" }) do
            entry.paths[#entry.paths + 1] = vim.fs.joinpath(entry.root, name)
          end
          if not entry.edition then entry.error = "Cargo metadata did not identify this crate's edition" end
        else
          entry.error = "Cargo metadata failed: " .. vim.trim(output.stderr or "no metadata")
        end
        entry.key = key(entry.paths)
        for _, done in ipairs(entry.callbacks) do done(entry) end
        entry.callbacks = {}
        changed()
      end)
    end
    if cargo then
      local ok, process = pcall(vim.system, { cargo, "metadata", "--offline", "--no-deps",
        "--format-version", "1", "--manifest-path", manifest },
        { cwd = vim.fs.dirname(manifest), env = M.environment(), text = true, timeout = 5000 }, complete)
      if ok then
        entry.process = process
        entry.timer = vim.defer_fn(function()
          process:kill(9)
          complete({ code = 124, stderr = "cargo metadata timed out" })
        end, 5000)
      else complete({ code = 1, stderr = tostring(process) }) end
    else
      complete({ code = 1, stderr = "cargo is unavailable in the project toolchain" })
    end
  end
  if callback then
    if entry.pending then entry.callbacks[#entry.callbacks + 1] = callback else callback(entry) end
  end
  return entry
end

-- Keep navigation into dependency/std sources on an existing workspace client,
-- as nvim-lspconfig does, rather than starting an analyzer for the library itself.
function M.library_root(filename)
  local home = vim.uv.os_homedir()
  local cargo_home = vim.env.CARGO_HOME or vim.fs.joinpath(home, ".cargo")
  local roots = { vim.fs.joinpath(cargo_home, "registry/src"), vim.fs.joinpath(cargo_home, "git/checkouts"),
    vim.fs.joinpath(vim.env.RUSTUP_HOME or vim.fs.joinpath(home, ".rustup"), "toolchains") }
  if vim.env.RUST_SRC_PATH then roots[#roots + 1] = vim.env.RUST_SRC_PATH end
  local library = filename:find("/lib/rustlib/src/rust/library/", 1, true) ~= nil
  for _, path in ipairs(roots) do
    path = vim.fs.normalize(path)
    if filename == path or vim.startswith(filename, path .. "/") then library = true; break end
  end
  if library then
    local clients = vim.lsp.get_clients({ name = "rust_analyzer" })
    return clients[#clients] and clients[#clients].config.root_dir or nil
  end
end

function M.expand_macro(bufnr)
  local client = vim.lsp.get_clients({ bufnr = bufnr, name = "rust_analyzer" })[1]
  if not client then return end
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  client:request("rust-analyzer/expandMacro", params, function(err, result)
    if err then vim.notify(err.message, vim.log.levels.WARN); return end
    if not result then vim.notify("No macro at cursor", vim.log.levels.INFO); return end
    vim.lsp.util.open_floating_preview(vim.split(result.expansion, "\n", { plain = true }), "rust", {
      title = result.name, border = "rounded", focus_id = "rust-analyzer/expandMacro",
    })
  end, bufnr)
end

return M
