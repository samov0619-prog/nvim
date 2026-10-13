local function is_light_theme()
  -- Sonokai's custom light palette can coexist with background=dark.
  local bg = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
  if not bg then return vim.o.background == "light" end
  local r, g, b = math.floor(bg / 65536), math.floor(bg / 256) % 256, bg % 256
  return (r * 299 + g * 587 + b * 114) / 1000 > 128
end

local function set_diff_colors()
  local colors = is_light_theme()
    and { "#E6F2E6", "#FBEAEA", "#B8DEB8", "#F0B8B8" }
    or { "#2E3D32", "#462F35", "#3E5B43", "#683D45" }
  for i, name in ipairs({ "LineInsert", "LineDelete", "CharInsert", "CharDelete" }) do
    vim.api.nvim_set_hl(0, "UserCodeDiff" .. name, { bg = colors[i] })
  end
end

local function compare_default_branch()
  local session = require("codediff.ui.lifecycle").get_session(vim.api.nvim_get_current_tabpage())
  local root = session and session.git_root
    or vim.fs.root(vim.api.nvim_buf_get_name(0), ".git") or vim.fn.getcwd()
  local function git(args)
    local result = vim.system(vim.list_extend({ "git", "-C", root }, args), { text = true }):wait(2000)
    return result.code == 0 and vim.trim(result.stdout) or nil
  end
  root = git({ "rev-parse", "--show-toplevel" })
  if not root then
    vim.notify("CodeDiff: текущий файл/каталог не принадлежит Git-репозиторию", vim.log.levels.INFO)
    return
  end
  local function exists(ref)
    return git({ "rev-parse", "--verify", "--quiet", ref .. "^{commit}" }) ~= nil
  end
  local function open(ref)
    if ref then
      vim.api.nvim_cmd({ cmd = "CodeDiff", args = { "--repo", root, ref } }, {})
    end
  end
  local default = git({ "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD" })
  if default and exists(default) then
    open(default)
    return
  end
  -- Use local refs only. No remote queries/fetches and no guess when both exist.
  for _, candidates in ipairs({
    { "refs/remotes/origin/main", "refs/remotes/origin/master" },
    { "refs/heads/main", "refs/heads/master" },
  }) do
    local found = vim.tbl_filter(exists, candidates)
    if #found == 1 then open(found[1]); return end
    if #found > 1 then
      vim.ui.select(found, { prompt = "CodeDiff: базовая ветка" }, open)
      return
    end
  end
  local refs = git({ "for-each-ref", "--format=%(refname)", "refs/heads", "refs/remotes" })
  if not refs or refs == "" then
    vim.notify("CodeDiff: нет доступных веток для сравнения", vim.log.levels.INFO)
    return
  end
  vim.ui.select(vim.split(refs, "\n", { trimempty = true }), { prompt = "CodeDiff: базовая ветка" }, open)
end

local function goto_file_smart()
  local api = vim.api
  local lifecycle = require("codediff.ui.lifecycle")
  local tab = api.nvim_get_current_tabpage()
  local session = lifecycle.get_session(tab)
  if not session then return end

  local path
  local panel = lifecycle.get_panel_view(tab)
  if panel and panel.bufnr == api.nvim_get_current_buf() and panel.tree then
    local node = panel.tree:get_node()
    local data = node and node.data
    if not data or data.type == "group" or data.type == "directory" then return end

    local root = data.git_root or panel.git_root or session.git_root
    if root and data.path then
      path = vim.fs.joinpath(root, data.path)
    end
  else
    local original, modified = lifecycle.get_paths(tab)
    path = modified and modified.absolute
    if not path or path == "" then
      path = original and original.absolute
    end
  end
  if not path or path == "" then return end

  local target
  for _, win in ipairs(api.nvim_list_wins()) do
    local buf = api.nvim_win_get_buf(win)
    local win_tab = api.nvim_win_get_tabpage(win)
    if win_tab ~= tab
      and not lifecycle.get_session(win_tab)
      and api.nvim_win_get_config(win).relative == ""
      and not vim.wo[win].winfixbuf
      and vim.bo[buf].buftype == ""
    then
      target = win
      break
    end
  end

  if target then
    api.nvim_set_current_win(target)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  else
    vim.cmd("0tabnew " .. vim.fn.fnameescape(path))
  end
  vim.schedule(function()
    pcall(function() require("mini.files").close() end)
  end)
end

-- Internal CodeDiff APIs: recheck these ranges/tracking when upgrading the plugin.
local function setup_conflict_focus()
  local api = vim.api
  local lifecycle = require("codediff.ui.lifecycle")
  local tracking = require("codediff.ui.conflict.tracking")
  local ns = api.nvim_create_namespace("CodeDiffConflictFocus")
  local group = api.nvim_create_augroup("CodeDiffConflictFocus", { clear = true })
  local painted = {}
  local pending = false

  local function clear()
    for buf in pairs(painted) do
      if api.nvim_buf_is_valid(buf) then
        api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      end
    end
    painted = {}
  end

  local function set_colors()
    api.nvim_set_hl(0, "CodeDiffConflictFocus", { bg = is_light_theme() and "#E5EDF9" or "#28364A" })
  end

  -- Zero-based, end-exclusive; RESULT extmarks follow edits.
  local function get_ranges(session, block)
    local ranges = {
      {
        buf = session.original_bufnr,
        first = block.output1_range.start_line - 1,
        last = block.output1_range.end_line - 1,
      },
      {
        buf = session.modified_bufnr,
        first = block.output2_range.start_line - 1,
        last = block.output2_range.end_line - 1,
      },
    }
    if block.extmark_id then
      local mark = api.nvim_buf_get_extmark_by_id(
        session.result_bufnr, tracking.tracking_ns, block.extmark_id, { details = true }
      )
      if #mark >= 3 and mark[3].end_row then
        ranges[#ranges + 1] = { buf = session.result_bufnr, first = mark[1], last = mark[3].end_row }
      end
    end
    return ranges
  end

  local function refresh()
    clear()
    local session = lifecycle.get_session(api.nvim_get_current_tabpage())
    if not session or session.suspended or not session.result_bufnr
      or not api.nvim_buf_is_valid(session.result_bufnr)
    then
      return
    end
    local current_buf = api.nvim_get_current_buf()
    if current_buf ~= session.original_bufnr and current_buf ~= session.modified_bufnr
      and current_buf ~= session.result_bufnr
    then
      return
    end
    local row = api.nvim_win_get_cursor(0)[1] - 1
    for _, block in ipairs(session.conflict_blocks or {}) do
      local ranges = get_ranges(session, block)
      local selected = false
      for _, range in ipairs(ranges) do
        if range.buf == current_buf and row >= range.first
          and row < math.max(range.first + 1, range.last)
        then
          selected = true
          break
        end
      end
      -- Only read/compare RESULT text for the block under the cursor.
      if selected and tracking.is_block_active(session, block) then
        for _, range in ipairs(ranges) do
          if range.buf and api.nvim_buf_is_valid(range.buf) then
            local count = api.nvim_buf_line_count(range.buf)
            -- Empty ranges must not paint the adjacent line.
            for line = math.max(0, range.first), math.min(count, range.last) - 1 do
              api.nvim_buf_set_extmark(range.buf, ns, line, 0, {
                line_hl_group = "CodeDiffConflictFocus",
                priority = 90, -- Below CodeDiff's line/character highlights (100+).
              })
              painted[range.buf] = true
            end
          end
        end
        return
      end
    end
  end

  local function queue_refresh()
    if pending then return end
    local session = lifecycle.get_session(api.nvim_get_current_tabpage())
    if not next(painted) and (not session or not session.result_bufnr) then return end
    pending = true
    vim.schedule(function()
      pending = false
      refresh()
    end)
  end

  set_colors()
  api.nvim_create_autocmd({
    "CursorMoved", "CursorMovedI", "BufEnter", "BufWinEnter", "WinEnter", "TabEnter",
    "TextChanged", "TextChangedI",
  }, { group = group, callback = queue_refresh })
  api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "CodeDiffOpen", "CodeDiffFileSelect" },
    callback = queue_refresh,
  })
  api.nvim_create_autocmd("User", { group = group, pattern = "CodeDiffClose", callback = clear })
  api.nvim_create_autocmd("TabLeave", { group = group, callback = clear })
  api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      set_colors()
      queue_refresh()
    end,
  })
end

return {
  {
    "esmuellert/codediff.nvim",
    cmd = "CodeDiff",
    keys = {
      { "<leader>gdo", "<cmd>CodeDiff<cr>", desc = "Diff: working tree" },
      { "<leader>gdO", compare_default_branch, desc = "Diff: default branch" },
      { "<leader>gdu", "<cmd>CodeDiff @{u}<cr>", desc = "Diff: upstream" },
      { "<leader>gdh", "<cmd>CodeDiff history %<cr>", desc = "Diff: file history" },
      { "<leader>gdH", "<cmd>CodeDiff history<cr>", desc = "Diff: repository history" },
    },
    opts = {
      diff = {
        conflict_ours_position = "left",
        conflict_result_position = "center",
        filler_text = " ",
        gutter_signs = {
          insert_text = "+",
          delete_text = "-",
          highlight_numbers = true,
          -- With signcolumn=yes:1, mask Gitsigns (priority 6) on unchanged lines.
          unchanged_priority = 7,
        },
      },
      highlights = {
        line_insert = "UserCodeDiffLineInsert",
        line_delete = "UserCodeDiffLineDelete",
        char_insert = "UserCodeDiffCharInsert",
        char_delete = "UserCodeDiffCharDelete",
      },
      explorer = {
        position = "left",
        width = 32,
        view_mode = "tree",
      },
      keymaps = {
        view = {
          quit = { "q", "<leader>gdc" },
          open_in_prev_tab = false, -- Custom gf also skips graph/floating windows.
        },
        conflict = {
          accept_current = "<leader>co",
          accept_incoming = "<leader>ct",
          accept_both = "<leader>cb",
          next_conflict = "]x",
          prev_conflict = "[x",
        },
      },
    },
    config = function(_, opts)
      local group = vim.api.nvim_create_augroup("CodeDiffCustom", { clear = true })
      set_diff_colors()
      -- The plugin entrypoint may register CodeDiff's ColorScheme handler first.
      -- Explicitly rebuild derived highlights after updating our source palette.
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = group,
        callback = function()
          set_diff_colors()
          require("codediff").setup({ highlights = opts.highlights })
        end,
      })
      local function map_gf(tab)
        if not tab or not vim.api.nvim_tabpage_is_valid(tab) then return end
        local lifecycle = require("codediff.ui.lifecycle")
        if not lifecycle.get_session(tab) then return end
        lifecycle.set_tab_keymap(tab, "n", "gf", goto_file_smart, {
          desc = "Open file (skip graph)",
          silent = true,
        })
      end
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = { "CodeDiffOpen", "CodeDiffFileSelect" },
        callback = function(event)
          local tab = event.data and event.data.tabpage
          vim.schedule(function() map_gf(tab) end)
        end,
      })
      -- FileSelect fires before asynchronous buffer loading finishes.
      vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
        group = group,
        callback = function()
          local tab = vim.api.nvim_get_current_tabpage()
          if not require("codediff.ui.lifecycle").get_session(tab) then return end
          vim.schedule(function() map_gf(tab) end)
        end,
      })
      require("codediff").setup(opts)
      setup_conflict_focus()
    end,
  },
}
