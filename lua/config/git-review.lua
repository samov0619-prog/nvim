-- Provider CLIs own authentication; FzfLua and Diffview own the UI.
local M = {}
local busy = false

local function notify(message, level)
  vim.notify("Git review: " .. message, level or vim.log.levels.INFO)
end

local function start(task)
  if busy then notify("A request is already running", vim.log.levels.WARN); return end
  busy = true
  local thread = coroutine.create(function()
    local ok, err = pcall(task)
    busy = false
    if not ok then notify(tostring(err), vim.log.levels.ERROR) end
  end)
  assert(coroutine.resume(thread))
end

local function run(root, args)
  local thread = coroutine.running()
  vim.system(args, {
    cwd = root, text = true, timeout = 60000,
    env = { GIT_TERMINAL_PROMPT = "0", GH_PROMPT_DISABLED = "1", GIT_NO_LAZY_FETCH = "1" },
  }, vim.schedule_wrap(function(result) assert(coroutine.resume(thread, result)) end))
  local result = coroutine.yield()
  if result.code ~= 0 then
    local detail = vim.trim(result.stderr or "")
    if detail == "" then detail = "exit code " .. result.code end
    error(args[1] .. " failed: " .. detail ..
      (result.code == 124 and " (timed out)" or ""), 0)
  end
  return vim.trim(result.stdout or "")
end

local function git(root, args)
  return run(root, vim.list_extend({ "git", "-C", root }, args))
end

local function encode(value)
  return (value:gsub("[^%w%-%._~]", function(char) return ("%%%02X"):format(char:byte()) end))
end

local function context(root, remote)
  local raw = git(root, { "remote", "get-url", remote })
  local url, host = require("config.git-link").remote_base(raw)
  local project = url:match("^https?://[^/]+/(.+)$")
  local pattern = vim.env.GLBPATT
  local provider = host == "github.com" and "github"
    or ((host == "gitlab.com" or (pattern and pattern ~= "" and raw:match(pattern))) and "gitlab")
  if not provider then error("Unknown host; set GLBPATT (Lua pattern) for a self-hosted GitLab remote", 0) end
  if not project then error("Cannot determine the remote project", 0) end
  local cli = provider == "github" and "gh" or "glab"
  if vim.fn.executable(cli) == 0 then error("Install " .. cli .. " and authenticate it for " .. host, 0) end
  return { root = root, remote = remote, provider = provider, cli = cli,
    host = url:match("^https?://([^/]+)"), project = project }
end

local function api(ctx, suffix)
  local endpoint = ctx.provider == "github" and ("repos/" .. ctx.project .. "/pulls")
    or ("projects/" .. encode(ctx.project) .. "/merge_requests")
  local output = run(ctx.root, { ctx.cli, "api", "--hostname", ctx.host, endpoint .. suffix })
  local ok, data = pcall(vim.json.decode, output)
  if not ok or type(data) ~= "table" then error("Invalid JSON from " .. ctx.cli, 0) end
  return data
end

local function request(ctx, data)
  local github = ctx.provider == "github"
  local item = {
    id = github and data.number or data.iid,
    title = data.title,
    author = github and data.user and data.user.login or data.author and data.author.username,
    base = github and data.base and data.base.ref or data.target_branch,
    head = github and data.head and data.head.ref or data.source_branch,
    body = github and data.body or data.description,
    draft = data.draft or data.work_in_progress,
    url = github and data.html_url or data.web_url,
  }
  if type(item.id) ~= "number" or item.id < 1 or item.id % 1 ~= 0
      or type(item.base) ~= "string" or type(item.title) ~= "string" then
    error("Incomplete PR/MR data from " .. ctx.cli, 0)
  end
  item.body = type(item.body) == "string" and item.body or ""
  return item
end

function M.show(ctx, id)
  local tab = vim.api.nvim_get_current_tabpage()
  start(function()
    -- Refresh the target branch: the request may have changed since listing.
    local item = request(ctx, api(ctx, "/" .. id))
    git(ctx.root, { "check-ref-format", "refs/heads/" .. item.base })
    local prefix = "refs/nvim-review/" .. vim.fn.sha256(ctx.remote):sub(1, 16) .. "/" .. item.id
    local head = (ctx.provider == "github" and "refs/pull/" or "refs/merge-requests/") .. item.id .. "/head"
    notify("Fetching " .. ctx.remote .. " " .. (ctx.provider == "github" and "PR #" or "MR !") .. item.id)
    -- Only our private refs change: not FETCH_HEAD, tags, remote-tracking refs,
    -- branches, the index, submodules, working files or unsaved buffers.
    git(ctx.root, { "fetch", "--atomic", "--no-tags", "--no-prune", "--no-prune-tags", "--no-write-fetch-head", "--no-recurse-submodules",
      "--no-auto-maintenance", "--refmap=", "--", ctx.remote,
      "+refs/heads/" .. item.base .. ":" .. prefix .. "/base", "+" .. head .. ":" .. prefix .. "/head" })
    local base = git(ctx.root, { "rev-parse", "--verify", prefix .. "/base^{commit}" })
    local tip = git(ctx.root, { "rev-parse", "--verify", prefix .. "/head^{commit}" })
    local ok, merge_base = pcall(git, ctx.root, { "merge-base", base, tip })
    if not ok then error("Common ancestor unavailable (check for shallow history): " .. merge_base, 0) end
    if vim.api.nvim_get_current_tabpage() ~= tab then
      notify("Fetched, but the active tab changed; select the request again to open it", vim.log.levels.WARN)
      return
    end
    -- Immutable commit IDs keep existing views stable across later fetches.
    vim.api.nvim_cmd({ cmd = "DiffviewOpen", args = {
      "-C=" .. vim.fn.fnameescape(ctx.root), "--imply-local=false", merge_base .. ".." .. tip,
    } }, {})
    if vim.api.nvim_get_current_tabpage() ~= tab then
      vim.t.git_review_readonly = true
      notify((ctx.provider == "github" and "PR #" or "MR !") .. item.id .. ": " .. item.title .. " (read-only)")
    end
  end)
end

local function one_line(value)
  return tostring(value or ""):gsub("[%z\1-\31\127]", " ")
end

local function list(ctx)
  local items, page = {}, 1
  while true do
    local state = ctx.provider == "github" and "open" or "opened"
    local data = api(ctx, "?state=" .. state .. "&per_page=100&page=" .. page)
    if not vim.islist(data) then error("Expected a PR/MR list from " .. ctx.cli, 0) end
    for _, value in ipairs(data) do items[#items + 1] = request(ctx, value) end
    if #data < 100 then break end
    page = page + 1
  end
  if #items == 0 then notify("No open PRs/MRs in " .. ctx.project); return end
  local rows, by_id = {}, {}
  for _, item in ipairs(items) do
    by_id[tostring(item.id)] = item
    rows[#rows + 1] = ("%d\t%s%s\t@%s\t%s → %s"):format(item.id, item.draft and "[Draft] " or "",
      one_line(item.title), one_line(item.author), one_line(item.head), one_line(item.base))
  end
  local function selected_item(selected)
    return selected[1] and by_id[selected[1]:match("^(%d+)")]
  end
  require("fzf-lua").fzf_exec(rows, {
    prompt = ctx.provider == "github" and "PR> " or "MR> ",
    winopts = { title = ctx.remote .. " · " .. ctx.project .. " · read-only" },
    fzf_opts = { ["--no-multi"] = true, ["--nth"] = false, ["--with-nth"] = false },
    preview = function(selected)
      local item = selected_item(selected)
      if not item then return "" end
      -- Plain text only: never render untrusted PR text as terminal escapes.
      return one_line(item.url) .. "\n" .. one_line(item.title) .. "\n\n"
        .. tostring(item.body or ""):gsub("[%z\1-\8\11-\31\127]", " ")
    end,
    actions = { enter = function(selected)
      local item = selected_item(selected)
      if item then M.show(ctx, item.id) end
    end },
  })
end

function M.open(remote)
  local directory = vim.fn.getcwd()
  local file = vim.api.nvim_buf_get_name(0)
  if vim.bo.buftype == "" and file ~= "" then directory = vim.fs.dirname(file) end
  start(function()
    local root = git(directory, { "rev-parse", "--show-toplevel" })
    local remotes = vim.split(git(root, { "remote" }), "\n", { trimempty = true })
    if #remotes == 0 then error("This repository has no remotes", 0) end
    if remote and remote ~= "" then
      if not vim.tbl_contains(remotes, remote) then error("Unknown remote: " .. remote, 0) end
      list(context(root, remote))
    elseif #remotes == 1 then
      list(context(root, remotes[1]))
    else
      -- Multiple remotes can mean forks; do not guess which project to review.
      vim.ui.select(remotes, { prompt = "Review PRs/MRs from remote" }, function(choice)
        if choice then vim.schedule(function() start(function() list(context(root, choice)) end) end) end
      end)
    end
  end)
end

-- Diffview already makes commit buffers nonmodifiable and guards restore and
-- per-file staging. Its bulk stage/unstage actions do NOT guard revision views.
-- Wrap only these documented actions, through supported keymap configuration.
function M.index_action(action)
  return function()
    if vim.t.git_review_readonly then notify("PR/MR review is read-only", vim.log.levels.WARN); return end
    require("diffview.actions")[action]()
  end
end

function M.setup()
  vim.api.nvim_create_user_command("GitReview", function(opts) M.open(opts.args) end, {
    nargs = "?", desc = "Review open GitHub PRs / GitLab MRs (read-only)",
  })
  vim.keymap.set("n", "<leader>gr", function() M.open() end, { desc = "git PR/MR review (read-only)" })
end

return M
