local M = {}

function M.setup(opts)
	-- Check Hyprland
	if os.getenv("XDG_CURRENT_DESKTOP") ~= "Hyprland" and not os.getenv("HYPRLAND_INSTANCE_SIGNATURE") then
		return
	end

	local saved_layout_index = nil
	local autocmd = vim.api.nvim_create_autocmd

	-- parse opts
	opts = opts or {}
	M.device = opts.device or "current"
	M.us_layout_index = opts.us_layout_index or 0

	local function get_current_layout_index_async(callback)
		local job = vim.fn.jobstart(
			{ 'hyprctl', '-j', 'devices' },
			{
				stdout_buffered = true,
				stderr_buffered = true,
				on_stdout = function(_, data, _)
					local raw = table.concat(data or {}, "\n")
					if raw == "" then
						vim.schedule(function()
							vim.notify(
								"[hyprland-switch] Ошибка: пустой ответ от hyprctl devices",
								vim.log.levels.WARN
							)
							callback(nil)
						end)
						return
					end

					local ok, parsed = pcall(vim.fn.json_decode, raw)
					if not ok or type(parsed) ~= "table" or not parsed.keyboards then
						vim.schedule(function()
							vim.notify(
								"[hyprland-switch] Не удалось распарсить JSON из hyprctl devices",
								vim.log.levels.ERROR
							)
							callback(nil)
						end)
						return
					end

					for _, kb in ipairs(parsed.keyboards) do
						local is_target = false
						if M.device == 'current' then
							is_target = (kb.main == true)
						else
							is_target = (kb.name == M.device)
						end

						if is_target then
							-- Проверяем kb.active_keymap. Если в нём встречается "(US)" (регистр неважен) —
							-- считаем, что эта раскладка US. Иначе — любая другая.
							if type(kb.active_keymap) == "string" then
								-- Пример: "English (US)" → найдём "US"
								local code = kb.active_keymap:match('%((%w+)%)')
								if code and code:lower() == 'us' then
									vim.schedule(function()
										callback(0)
									end)
								else
									vim.schedule(function()
										callback(1)
									end)
								end
							else
								vim.schedule(function()
									vim.notify(
										"[hyprland-switch] Не удалось прочитать active_keymap",
										vim.log.levels.WARN
									)
									callback(nil)
								end)
							end
							return
						end
					end

					vim.schedule(function()
						vim.notify(
							string.format("[hyprland-switch] Девайс '%s' не найден", M.device),
							vim.log.levels.ERROR
						)
						callback(nil)
					end)
				end,

				on_stderr = function(_, data, _)
					local err = table.concat(data or {}, "\n")
					if err ~= "" then
						vim.schedule(function()
							vim.notify(
								"[hyprland-switch] Ошибка от hyprctl devices: " .. err,
								vim.log.levels.ERROR
							)
						end)
					end
				end,

				on_exit = function(_, exit_code, _)
					if exit_code ~= 0 then
						vim.schedule(function()
							vim.notify(
								"[hyprland-switch] hyprctl devices завершился с кодом " .. exit_code,
								vim.log.levels.ERROR
							)
						end)
						callback(nil)
					end
				end,
			}
		)

		if job <= 0 then
			vim.schedule(function()
				vim.notify(
					"[hyprland-switch] Не удалось запустить hyprctl devices",
					vim.log.levels.ERROR
				)
				callback(nil)
			end)
		end
	end


	local function switch_layout_raw(layout_index)
		vim.fn.jobstart(
			{ 'hyprctl', 'switchxkblayout', M.device, tostring(layout_index) },
			{
				detach = false,
				on_exit = function(_, exit_code)
					if exit_code ~= 0 then
						vim.schedule(function()
							vim.notify(
								string.format(
									"[hyprland-switch] Ошибка переключения на %d (код %d)",
									layout_index, exit_code
								),
								vim.log.levels.ERROR
							)
						end)
					end
				end,
			}
		)
	end

	local function switch_layout_checked(layout_index)
		-- Сначала «асинхронно» получаем, что сейчас реально стоит
		get_current_layout_index_async(function(real_now)
			-- real_now может быть 0, 1 или nil
			if not real_now then
				vim.schedule(function()
					vim.notify(
						"[hyprland-switch] Не удалось корректно прочитать текущую раскладку, переключение отменено",
						vim.log.levels.ERROR
					)
				end)
				return
			end

			if real_now == layout_index then
				return
			end

			-- Нужно переключить: кидаем асинхронную команду
			vim.fn.jobstart(
				{ 'hyprctl', 'switchxkblayout', M.device, tostring(layout_index) },
				{
					detach = false,
					on_exit = function(_, exit_code)
						if exit_code ~= 0 then
							vim.schedule(function()
								vim.notify(
									string.format(
										"[hyprland-switch] Ошибка переключения на %d (код %d)",
										layout_index, exit_code
									),
									vim.log.levels.ERROR
								)
							end)
						end
					end,
				}
			)
		end)
	end

	autocmd("VimEnter", {
		once = true,
		callback = function()
			get_current_layout_index_async(function(idx)
				if idx and idx ~= M.us_layout_index then
					switch_layout_raw(M.us_layout_index)
				end
			end)
		end
	})

	-- === 1) InsertLeave: сохраним «не-US», переключим на US ===
	autocmd('InsertLeave', {
		pattern = "*",
		callback = function()
			vim.schedule(function()
				get_current_layout_index_async(function(now)
					if now then
						saved_layout_index = now
					end
					switch_layout_raw(M.us_layout_index)
				end)
			end)
		end
	})

	-- === 2) InsertEnter: вернём «сохранённое» (или US, если saved == nil) ===
	autocmd('InsertEnter', {
		pattern = "*",
		callback = function()
			vim.schedule(function()
				local to_set = saved_layout_index or M.us_layout_index
				switch_layout_checked(to_set)
			end)
		end
	})

	-- === 3) FocusLost: сохраняем «не-US» ===
	autocmd('FocusLost', {
		pattern = "*",
		callback = function()
			vim.schedule(function()
				get_current_layout_index_async(function(now)
					if now then
						saved_layout_index = now
					end
				end)
			end)
		end
	})

	-- === 4) FocusGained: если в Insert — возвращаем saved, иначе ставим US ===
	autocmd('FocusGained', {
		pattern = "*",
		callback = function()
			vim.schedule(function()
				local mode = vim.fn.mode()
				if mode == 'i' or mode == 'ic' then
					get_current_layout_index_async(function(now)
						if now then
							saved_layout_index = now
						end
						switch_layout_raw(saved_layout_index)
					end)
				else
					switch_layout_checked(M.us_layout_index)
				end
			end)
		end
	})
end

return M
