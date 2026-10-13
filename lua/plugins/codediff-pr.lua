return {
  {
    "esmuellert/codediff.nvim",
    dependencies = { "ibhagwan/fzf-lua" },
    keys = {
      { "<leader>gdp", function() require("codediff_pr").pick() end, desc = "Diff: choose pull request" },
    },
  },
}
