local M = {}

function M.setup(opts)
	-- === PLATFORM DETECTION ===
	local is_hyprland = os.getenv("XDG_CURRENT_DESKTOP") == "Hyprland" or os.getenv("HYPRLAND_INSTANCE_SIGNATURE")
	-- === MACOS: Platform detection ===
	local is_macos = vim.fn.has("macunix") == 1
	-- === END MACOS ===
	
	-- Check supported platforms
	if not is_hyprland and not is_macos then
		return
	end

	local saved_layout_index = nil
	local autocmd = vim.api.nvim_create_autocmd

	-- parse opts
	opts = opts or {}
	M.device = opts.device or "current"
	M.us_layout_index = opts.us_layout_index or 0

	-- === MACOS: Find xkbswitch library ===
	local xkb_switch_lib = nil
	if is_macos then
		if vim.fn.filereadable('/usr/local/lib/libInputSourceSwitcher.dylib') == 1 then
			xkb_switch_lib = '/usr/local/lib/libInputSourceSwitcher.dylib'
		elseif vim.fn.filereadable('/usr/lib/libInputSourceSwitcher.dylib') == 1 then
			xkb_switch_lib = '/usr/lib/libInputSourceSwitcher.dylib'
		end
		
		if xkb_switch_lib == nil then
			vim.notify(
				"[hyprland-switch] libInputSourceSwitcher.dylib not found. Please install input-source-switcher.",
				vim.log.levels.ERROR
			)
			return
		end
	end
	-- === END MACOS ===

	-- === MACOS: Function to get current layout index using library ===
	local function get_current_layout_index_async_macos(callback)
		local job = vim.fn.jobstart(
			{ 'sh', '-c', string.format('echo "$(echo \'%s\' | luajit -e "print(vim.fn.libcall(\'%s\', \'Xkb_Switch_getXkbLayout\', \'\'))")"', '', xkb_switch_lib) },
			{
				stdout_buffered = true,
				stderr_buffered = true,
				on_stdout = function(_, data, _)
					local raw = table.concat(data or {}, "\n"):gsub("%s+", "")
					if raw == "" then
						vim.schedule(function()
							callback(nil)
						end)
						return
					end
					
					vim.schedule(function()
						-- Check if current layout is US-based (ABC, US, etc.)
						if raw:match('ABC') or raw:match('US') or raw:match('us') then
							callback(0) -- US layout
						else
							callback(1) -- Non-US layout
						end
					end)
				end,
				
				on_stderr = function(_, data, _)
					local err = table.concat(data or {}, "\n")
					if err ~= "" then
						vim.schedule(function()
							vim.notify(
								"[hyprland-switch] Error getting macOS layout: " .. err,
								vim.log.levels.ERROR
							)
						end)
					end
				end,
				
				on_exit = function(_, exit_code, _)
					if exit_code ~= 0 then
						vim.schedule(function()
							callback(nil)
						end)
					end
				end,
			}
		)

		if job <= 0 then
			vim.schedule(function()
				vim.notify(
					"[hyprland-switch] Failed to start macOS layout detection",
					vim.log.levels.ERROR
				)
				callback(nil)
			end)
		end
	end
	-- === END MACOS ===

	local function get_current_layout_index_async(callback)
		-- === MACOS: Use library-based detection ===
		if is_macos then
			get_current_layout_index_async_macos(callback)
			return
		end
		-- === END MACOS ===

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

	-- === MACOS: Find US layout variation ===
	local user_us_layout_variation = nil
	if is_macos then
		local user_layouts = vim.fn.systemlist('issw -l')
		-- Find the used US layout (ABC, US, etc.)
		for _, value in ipairs(user_layouts) do
			if value:match('ABC') or value:match('US') then
				user_us_layout_variation = value
				break
			end
		end
		
		if user_us_layout_variation == nil then
			vim.notify(
				"[hyprland-switch] Could not find US layout. Check 'issw -l' output.",
				vim.log.levels.ERROR
			)
			return
		end
	end
	-- === END MACOS ===

	-- === MACOS: Function to switch layout using library ===
	local function switch_layout_raw_macos(layout_index)
		local target_layout
		if layout_index == 0 then
			target_layout = user_us_layout_variation
		else
			-- For non-US, we need to get first non-US layout
			local user_layouts = vim.fn.systemlist('issw -l')
			for _, layout in ipairs(user_layouts) do
				if not (layout:match('ABC') or layout:match('US')) then
					target_layout = layout
					break
				end
			end
		end
		
		if not target_layout then
			return
		end

		vim.fn.jobstart(
			{ 'sh', '-c', string.format('luajit -e "vim.fn.libcall(\'%s\', \'Xkb_Switch_setXkbLayout\', \'%s\')"', xkb_switch_lib, target_layout) },
			{
				detach = false,
				on_exit = function(_, exit_code)
					if exit_code ~= 0 then
						vim.schedule(function()
							vim.notify(
								string.format(
									"[hyprland-switch] Error switching to layout %d (code %d)",
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
	-- === END MACOS ===

	local function switch_layout_raw(layout_index)
		-- === MACOS: Use library-based switching ===
		if is_macos then
			switch_layout_raw_macos(layout_index)
			return
		end
		-- === END MACOS ===

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

			-- === MACOS: Use library-based checked switching ===
			if is_macos then
				switch_layout_raw_macos(layout_index)
				return
			end
			-- === END MACOS ===

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
