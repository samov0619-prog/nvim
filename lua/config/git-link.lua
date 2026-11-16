local M = {}

local function git(directory, args, opts)
  opts = opts or {}
  local result = vim.system(vim.list_extend({ "git", "-C", directory }, args), {
    text = true, env = { GIT_NO_LAZY_FETCH = "1" },
  }):wait()
  if result.code ~= 0 then
    if opts.optional then return nil end
    error(vim.trim(result.stderr), 0)
  end
  if opts.raw then return result.stdout end
  return (result.stdout:gsub("\n$", ""))
end

local function encode(path)
  return (path:gsub("[^%w%-%._~/]", function(char)
    return ("%%%02X"):format(char:byte())
  end))
end

local function remote_base(remote)
  local scheme, authority, path = remote:match("^(%w+)://([^/]+)/(.+)$")
  local ssh_target
  if scheme then
    if scheme == "ssh" then ssh_target = authority:gsub(":%d+$", "") end
    authority = authority:gsub("^.*@", "")
    if scheme == "ssh" or scheme == "git" then
      authority = authority:gsub(":%d+$", "")
      scheme = "https"
    elseif scheme ~= "http" and scheme ~= "https" then
      error("Unsupported Git remote URL", 0)
    end
  else
    authority, path = remote:match("^([^/:]+):(.+)$")
    if not authority then error("Expected an SSH or HTTP Git remote", 0) end
    ssh_target = authority
    authority = authority:gsub("^.*@", "")
    scheme = "https"
  end
  if ssh_target then
    -- Ask OpenSSH to resolve Host/HostName aliases without connecting.
    local result = vim.system({ "ssh", "-G", "-T", "-o", "CanonicalizeHostname=no", "--", ssh_target },
      { text = true }):wait()
    if result.code ~= 0 then error("Cannot read SSH configuration: " .. vim.trim(result.stderr), 0) end
    authority = ("\n" .. result.stdout):match("\nhostname ([^\r\n]+)")
    if not authority then error("SSH configuration did not return a hostname", 0) end
  end
  path = path:gsub("/+$", ""):gsub("%.git$", "")
  return scheme .. "://" .. authority .. "/" .. path, authority:match("^[^:]+")
end

local function map_range(published, current, first, last)
  if first < 1 or last > #current then return nil, "Selected lines are outside the file" end
  local function text(lines) return #lines == 0 and "" or table.concat(lines, "\n") .. "\n" end
  local offset = 0
  for _, hunk in ipairs((vim.text and vim.text.diff or vim.diff)(text(published), text(current), {
    result_type = "indices", algorithm = "histogram",
  })) do
    local old_count, start, count = hunk[2], hunk[3], hunk[4]
    if count > 0 and start <= last and start + count > first then
      return nil, "Selected lines contain local changes not present in the upstream snapshot"
    end
    if count == 0 and start >= first and start < last then
      return nil, "Selected range is not contiguous in the upstream snapshot (locally deleted lines)"
    end
    if (count > 0 and start + count <= first) or (count == 0 and start < first) then
      offset = offset + old_count - count
    end
  end
  -- Verify the mapped text too: never copy a plausible-looking but wrong range.
  for line = first, last do
    if published[line + offset] ~= current[line] then
      return nil, "Selected lines could not be matched to the upstream snapshot"
    end
  end
  return first + offset, last + offset
end

function M.url(file, first, last, lines)
  local directory = vim.fs.dirname(file)
  local tracked = git(directory, {
    "ls-files", "--full-name", "--error-unmatch", "-z", "--", ":(literal)" .. vim.fs.basename(file),
  }, { optional = true })
  if not tracked then return nil, "File is not tracked by Git; no upstream link can be copied" end
  local path = tracked:gsub("%z$", "")
  local branch = git(directory, { "symbolic-ref", "--quiet", "--short", "HEAD" }, { optional = true })
  local remote = branch and git(directory, { "config", "--get", "branch." .. branch .. ".remote" }, { optional = true })
  if not remote or remote == "" or remote == "." then return nil, "No remote upstream configured for the current branch" end
  local upstream = git(directory, { "rev-parse", "--verify", "@{upstream}^{commit}" }, { optional = true })
  if not upstream then return nil, "Upstream revision is unavailable locally; check upstream configuration and remote-tracking refs" end
  local head = git(directory, { "rev-parse", "--verify", "HEAD" })
  -- Local remote-tracking refs are our evidence, not a live check of the server.
  local commit = git(directory, { "merge-base", head, upstream }, { optional = true })
  if not commit then return nil, "HEAD and upstream have no available common ancestor" end
  local blob = git(directory, { "show", commit .. ":" .. path }, { optional = true, raw = true })
  if not blob then return nil, "File is not present in the upstream snapshot; it may only exist locally" end
  if first then
    last = last or first
    first, last = math.min(first, last), math.max(first, last)
    local published = vim.split(blob, "\n", { plain = true })
    if published[#published] == "" then table.remove(published) end
    first, last = map_range(published, lines or vim.fn.readfile(file), first, last)
    if not first then return nil, last end
  end
  local raw = git(directory, { "remote", "get-url", remote })
  local base, host = remote_base(raw)
  local pattern = vim.env.GLBPATT
  local gitlab = host == "gitlab.com" or (pattern and pattern ~= "" and raw:match(pattern) ~= nil)
  if not gitlab and host ~= "github.com" then
    error("Unknown Git host; set GLBPATT (Lua pattern) for your GitLab remote", 0)
  end

  local url = base .. (gitlab and "/-/blob/" or "/blob/") .. commit .. "/" .. encode(path)
  local label = vim.fs.basename(path):gsub("([\\%[%]`*_])", "\\%1")
  if first then
    url = url .. "#L" .. first
    label = label .. ":" .. first
    if last ~= first then
      url = url .. (gitlab and "-" or "-L") .. last
      label = label .. "-" .. last
    end
  end
  return "[" .. label .. "](" .. url .. ")"
end

function M.copy(visual)
  if vim.bo.buftype ~= "" or vim.api.nvim_buf_get_name(0) == "" then
    vim.notify("Git link: open a tracked file first", vim.log.levels.WARN)
    return
  end
  local first = vim.fn.line(".")
  local last = visual and vim.fn.line("v") or first
  local ok, result, reason = pcall(function()
    local url, message = M.url(vim.api.nvim_buf_get_name(0), first, last,
      vim.api.nvim_buf_get_lines(0, 0, -1, false))
    if not url then return nil, message end
    vim.fn.setreg("+", url)
    return url
  end)
  if not ok then
    vim.notify("Git link: " .. result, vim.log.levels.ERROR)
    return
  end
  if not result then
    vim.notify("Git link: " .. reason, vim.log.levels.WARN)
    return
  end
  vim.notify("Copied: " .. result)
end

-- Shared remote parsing, including local OpenSSH HostName resolution.
M.remote_base = remote_base

return M
