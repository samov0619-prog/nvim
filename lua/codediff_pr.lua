local M = {}
local host_providers = {}

local function notify(message, level)
  vim.notify("CodeDiff PR/MR: " .. message, level or vim.log.levels.INFO)
end

-- Resolve the API host, but keep the original remote for CodeDiff's Git fetch.
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
  if not path:match("^[^/]+/.+") or path:find("//", 1, true) then return end
  return { host = host:lower(), path = path, name = host:lower() .. "/" .. path }
end

local function select_provider(repo, callback)
  -- Optional persistent mapping for self-hosted instances:
  -- vim.g.codediff_pr_providers = { ["git.company.example"] = "gitlab" }
  local overrides = vim.g.codediff_pr_providers or {}
  local provider = overrides[repo.host] or host_providers[repo.host]
  if not provider then
    if repo.host == "github.com" then provider = "github"
    elseif repo.host == "gitlab.com" then provider = "gitlab" end
  end
  if provider then
    if provider ~= "github" and provider ~= "gitlab" then
      notify("неизвестный провайдер для " .. repo.host .. ": " .. tostring(provider), vim.log.levels.WARN)
      return
    end
    callback(provider)
    return
  end
  vim.ui.select({ "GitHub", "GitLab" }, { prompt = "CodeDiff: провайдер " .. repo.host }, function(choice)
    if not choice then return end
    provider = choice:lower()
    host_providers[repo.host] = provider
    callback(provider)
  end)
end

local function list_requests(repo, root, remote, provider)
  local gitlab = provider == "gitlab"
  local cli, kind = gitlab and "glab" or "gh", gitlab and "MR" or "PR"
  if vim.fn.executable(cli) ~= 1 then
    notify("для списка " .. kind .. " нужен " .. cli, vim.log.levels.WARN)
    return
  end
  local args = gitlab and {
    "glab", "mr", "list", "--repo", "https://" .. repo.name, "--output", "json", "--per-page", "100",
  } or {
    "gh", "pr", "list", "--repo", repo.name, "--state", "open", "--limit", "100",
    "--json", "number,title,author,headRefName,baseRefName,isDraft",
  }
  notify("загрузка открытых " .. kind .. ": " .. repo.name)
  vim.system(args, { cwd = root, text = true, timeout = 30000 }, vim.schedule_wrap(function(result)
    if result.code ~= 0 then
      notify(vim.trim(result.stderr or "") ~= "" and vim.trim(result.stderr)
        or ("не удалось получить список (ошибка или таймаут " .. cli .. ")"), vim.log.levels.WARN)
      return
    end
    local ok, requests = pcall(vim.json.decode, result.stdout)
    if not ok or type(requests) ~= "table" or not vim.islist(requests) then
      notify(cli .. " вернул некорректный JSON-список", vim.log.levels.WARN)
      return
    end
    if #requests == 0 then notify("открытых " .. kind .. " нет"); return end
    local entries, numbers = {}, {}
    local function text(value) return tostring(value or ""):gsub("%c", " ") end
    for _, request in ipairs(requests) do
      if type(request) ~= "table" then
        notify(cli .. " вернул некорректную запись", vim.log.levels.WARN)
        return
      end
      -- GitLab's global id is NOT the project-local number used in refs.
      local number = tostring(gitlab and request.iid or request.number)
      local author = type(request.author) == "table" and request.author or {}
      local head = gitlab and request.source_branch or request.headRefName
      local base = gitlab and request.target_branch or request.baseRefName
      local draft = request.isDraft or request.draft or request.work_in_progress
      if number:match("^%d+$") then
        numbers[number] = { base = base }
        entries[#entries + 1] = ("%s%s\t%s%s\t@%s\t%s → %s"):format(
          gitlab and "!" or "#", number, draft and "[draft] " or "", text(request.title),
          text(gitlab and author.username or author.login), text(head), text(base)
        )
      end
    end
    require("fzf-lua").fzf_exec(entries, {
      prompt = kind .. "> ",
      winopts = { title = "CodeDiff · " .. repo.name .. " · open " .. kind .. "s (max 100)" },
      fzf_opts = { ["--no-multi"] = true },
      actions = {
        ["default"] = function(selected)
          local number = selected[1] and selected[1]:match("^[#!](%d+)")
          local request = number and numbers[number]
          if request then
            local command = { "--repo", root, "pr", number, "--remote", remote }
            -- Required when the server has only a head ref and the target is
            -- not the remote's default branch (e.g. a release-branch MR).
            if type(request.base) == "string" and request.base ~= "" then
              vim.list_extend(command, { "--base", request.base })
            end
            vim.api.nvim_cmd({ cmd = "CodeDiff", args = command }, {})
          end
        end,
      },
    })
  end))
end

function M.pick(remote)
  local cwd = require("codediff_context").root()
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
      vim.ui.select(remotes, { prompt = "CodeDiff PR/MR: remote" }, function(choice)
        if choice then M.pick(choice) end
      end)
      return
    end
  end
  local url = git({ "remote", "get-url", remote })
  local repo, err
  if url then repo, err = repository(url) end
  if not repo then
    notify(err or ("не удалось определить репозиторий для remote " .. remote), vim.log.levels.WARN)
    return
  end
  select_provider(repo, function(provider) list_requests(repo, root, remote, provider) end)
end

return M
