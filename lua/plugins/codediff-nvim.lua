local function set_diff_colors()
  -- The custom light Sonokai palette can coexist with background=dark.
  local bg = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
  local light = vim.o.background == "light"
  if bg then
    local r, g, b = math.floor(bg / 65536), math.floor(bg / 256) % 256, bg % 256
    light = (r * 299 + g * 587 + b * 114) / 1000 > 128
  end
  local colors = light
    and { "#E6F2E6", "#FBEAEA", "#B8DEB8", "#F0B8B8" }
    or { "#2E3D32", "#462F35", "#3E5B43", "#683D45" }
  for i, name in ipairs({ "LineInsert", "LineDelete", "CharInsert", "CharDelete" }) do
    vim.api.nvim_set_hl(0, "UserCodeDiff" .. name, { bg = colors[i] })
  end
end

local function compare_default_branch()
  local root = require("codediff_context").root()
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
  if default and exists(default) then open(default); return end
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
          -- Documented masking for Gitsigns in the single sign column.
          unchanged_priority = 7,
        },
      },
      highlights = {
        line_insert = "UserCodeDiffLineInsert",
        line_delete = "UserCodeDiffLineDelete",
        char_insert = "UserCodeDiffCharInsert",
        char_delete = "UserCodeDiffCharDelete",
      },
      explorer = { position = "left", width = 32, view_mode = "tree" },
      keymaps = {
        view = { quit = { "q", "<leader>gdc" } },
        conflict = {
          -- In the installed version these actions mean input2/right and
          -- input1/left. Our layout puts OURS (:2) on the left.
          accept_incoming = "<Plug>(UserCodeDiffAcceptLeft)",
          accept_current = "<Plug>(UserCodeDiffAcceptRight)",
          accept_all_incoming = "<leader>cO",
          accept_all_current = "<leader>cT",
          -- Native result-only actions, also exposed through co/ct by our
          -- public Neovim keymap adapter. Keep the original 2do/3do bindings.
          diffget_incoming = { "2do", "<Plug>(UserCodeDiffGetLeft)" },
          diffget_current = { "3do", "<Plug>(UserCodeDiffGetRight)" },
          accept_both = "<leader>cb",
          next_conflict = "]x",
          prev_conflict = "[x",
        },
      },
    },
    config = function(_, opts)
      require("codediff_context").setup()
      set_diff_colors()
      local group = vim.api.nvim_create_augroup("CodeDiffColors", { clear = true })
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = group,
        callback = function()
          set_diff_colors()
          -- setup is the supported API for rebuilding derived highlights.
          require("codediff").setup({ highlights = opts.highlights })
        end,
      })
      require("codediff").setup(opts)
    end,
  },
}
