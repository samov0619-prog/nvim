local M = {}

local function notify(message, level)
  vim.notify("CodeDiff PR: " .. message, level or vim.log.levels.INFO)
end

-- gh accepts HOST/OWNER/REPO. Pin it to the same remote CodeDiff will fetch.
local function repository(url)
  local host, path = url:match("^https?://([^/]+)/(.+)$")
  local ssh_destination
  if not host then
    ssh_destination, path = url:match("^ssh://([^/]+)/(.+)$")
    if not ssh_destination then ssh_destination, path = url:match("^([^/:]+):(.+)$") end
    if ssh_destination then
      -- Resolve Host aliases / Include / Match through OpenSSH itself, without
      -- connecting or unlocking keys. Keep the user for Match User rules.
      local destination, port = ssh_destination:match("^(.-):(%d+)$")
      local args = { "ssh", "-G" }
      if port then vim.list_extend(args, { "-p", port }) end
      args[#args + 1] = destination or ssh_destination
      if vim.fn.executable("ssh") ~= 1 then return nil, "для SSH remote нужен ssh" end
      local result = vim.system(args, { text = true }):wait(2000)
      if result.code ~= 0 then return nil, "не удалось прочитать настройки SSH через ssh -G" end
      for line in (result.stdout or ""):gmatch("[^\r\n]+") do
        host = line:match("^hostname%s+(%S+)$")
        if host then break end
      end
    end
  end
  if not host then return end
  host = host:gsub("^.*@", "")
  path = path:gsub("/$", ""):gsub("%.git$", "")
  if not path:match("^[^/]+/[^/]+$") then return end
  return host .. "/" .. path
end

function M.pick(remote)
  if vim.fn.executable("gh") ~= 1 then
    notify("для списка GitHub PR нужен gh (GitHub CLI)", vim.log.levels.WARN)
    return
  end
  local lifecycle = require("codediff.ui.lifecycle")
  local session = lifecycle.get_session(vim.api.nvim_get_current_tabpage())
  local cwd = session and session.git_root
    or vim.fs.root(vim.api.nvim_buf_get_name(0), ".git") or vim.fn.getcwd()
  local function git(args)
    local result = vim.system(vim.list_extend({ "git", "-C", cwd }, args), { text = true }):wait(2000)
    return result.code == 0 and vim.trim(result.stdout) or nil
  end
  local root = git({ "rev-parse", "--show-toplevel" })
  if not root then
    notify("текущий файл/каталог не принадлежит Git-репозиторию", vim.log.levels.WARN)
    return
  end
  local remotes = vim.split(git({ "remote" }) or "", "\n", { trimempty = true })
  if #remotes == 0 then notify("в репозитории нет remotes"); return end
  if not remote then
    if vim.tbl_contains(remotes, "origin") then
      remote = "origin"
    elseif #remotes == 1 then
      remote = remotes[1]
    else
      vim.ui.select(remotes, { prompt = "CodeDiff PR: remote" }, function(choice)
        if choice then M.pick(choice) end
      end)
      return
    end
  end
  local url = git({ "remote", "get-url", remote })
  local repo, err
  if url then repo, err = repository(url) end
  if not repo then
    notify(err or ("не удалось определить GitHub-репозиторий для remote " .. remote), vim.log.levels.WARN)
    return
  end
  notify("загрузка открытых PR: " .. repo)
  vim.system({
    "gh", "pr", "list", "--repo", repo, "--state", "open", "--limit", "100",
    "--json", "number,title,author,headRefName,baseRefName,isDraft",
  }, { cwd = root, text = true, timeout = 30000 }, vim.schedule_wrap(function(result)
    if result.code ~= 0 then
      notify(vim.trim(result.stderr or "") ~= "" and vim.trim(result.stderr)
        or "не удалось получить список PR (ошибка или таймаут gh)", vim.log.levels.WARN)
      return
    end
    local ok, prs = pcall(vim.json.decode, result.stdout)
    if not ok or type(prs) ~= "table" then
      notify("gh вернул некорректный JSON", vim.log.levels.WARN)
      return
    end
    if #prs == 0 then notify("открытых PR нет"); return end
    local entries, numbers = {}, {}
    local function text(value) return tostring(value or ""):gsub("%c", " ") end
    for _, pr in ipairs(prs) do
      local number = tostring(pr.number)
      if number:match("^%d+$") then
        numbers[number] = true
        entries[#entries + 1] = ("#%s\t%s%s\t@%s\t%s → %s"):format(
          number, pr.isDraft and "[draft] " or "", text(pr.title),
          text(pr.author and pr.author.login), text(pr.headRefName), text(pr.baseRefName)
        )
      end
    end
    require("fzf-lua").fzf_exec(entries, {
      prompt = "PR> ",
      winopts = { title = "CodeDiff · " .. repo .. " · open PRs (max 100)" },
      fzf_opts = { ["--no-multi"] = true },
      actions = {
        ["default"] = function(selected)
          local number = selected[1] and selected[1]:match("^#(%d+)")
          if number and numbers[number] then
            vim.api.nvim_cmd({ cmd = "CodeDiff", args = { "--repo", root, "pr", number, "--remote", remote } }, {})
          end
        end,
      },
    })
  end))
end

return M
