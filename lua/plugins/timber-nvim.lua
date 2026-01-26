return {
	{
		"Goose97/timber.nvim",
		version = "*", -- Use for stability; omit to use `main` branch for the latest features
		event = "VeryLazy",
		config = function()
			require("timber").setup({
				log_templates = {
					default = {
						javascript =
						[[console.log("%watcher_marker_start %log_target", %log_target, "%watcher_marker_end")]],
						typescript =
						[[console.log("%watcher_marker_start %log_target", %log_target, "%watcher_marker_end")]],
						astro = [[console.log("%watcher_marker_start %log_target", %log_target, "%watcher_marker_end")]],
						vue = [[console.log("%watcher_marker_start %log_target", %log_target, "%watcher_marker_end")]],
						jsx = [[console.log("%watcher_marker_start %log_target", %log_target, "%watcher_marker_end")]],
						tsx = [[console.log("%watcher_marker_start %log_target", %log_target, "%watcher_marker_end")]],
						lua = [[print("%watcher_marker_start %log_target", %log_target, "%watcher_marker_end")]],
					},
					plain = {
						javascript = [[console.log("%watcher_marker_start %insert_cursor %watcher_marker_end")]],
						typescript = [[console.log("%watcher_marker_start %insert_cursor %watcher_marker_end")]],
						astro = [[console.log("%watcher_marker_start %insert_cursor %watcher_marker_end")]],
						vue = [[console.log("%watcher_marker_start %insert_cursor %watcher_marker_end")]],
						jsx = [[console.log("%watcher_marker_start %insert_cursor %watcher_marker_end")]],
						tsx = [[console.log("%watcher_marker_start %insert_cursor %watcher_marker_end")]],
						lua = [[print("%watcher_marker_start %insert_cursor %watcher_marker_end")]],
					},
				},
				batch_log_templates = {
					default = {
						javascript = [[
console.log(
  "%watcher_marker_start",
  { %repeat<"%log_target": %log_target><, > },
  "%watcher_marker_end"
)
]],
						typescript = [[
console.log(
  "%watcher_marker_start",
  { %repeat<"%log_target": %log_target><, > },
  "%watcher_marker_end"
)
]],
						astro = [[
console.log(
  "%watcher_marker_start",
  { %repeat<"%log_target": %log_target><, > },
  "%watcher_marker_end"
)
]],
						vue = [[
console.log(
  "%watcher_marker_start",
  { %repeat<"%log_target": %log_target><, > },
  "%watcher_marker_end"
)
]],
						jsx = [[
console.log(
  "%watcher_marker_start",
  { %repeat<"%log_target": %log_target><, > },
  "%watcher_marker_end"
)
]],
						tsx = [[
console.log(
  "%watcher_marker_start",
  { %repeat<"%log_target": %log_target><, > },
  "%watcher_marker_end"
)
]],
						lua =
						[[print(string.format("%repeat<%watcher_marker_start %log_target=%s %watcher_marker_end><, >", %repeat<%log_target><, >))]],
					},
				},
			})
		end
	}
}
