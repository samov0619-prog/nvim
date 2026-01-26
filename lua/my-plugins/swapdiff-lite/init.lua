---@mod swapdiff SwapDiff Plugin
---@brief [[
---SwapDiff is a Neovim plugin for advanced swap file management and recovery.
---It provides interactive tools to review, diff, and recover changes from swap files.
---@brief ]]

local M = {}

local api, fn, v = vim.api, vim.fn, vim.v
---@class SwapDiffSwapInfo
---@field swappath string
---@field info NvimSwapInfo
---@class SwapDiffBuffer
---@field relfile string
---@field absfile string
---@field swapinfos SwapDiffSwapInfo[]
---@field main_buf integer
---@class NvimSwapInfo
---@field version string
---@field user string
---@field host string
---@field fname string
---@field pid integer
---@field mtime integer
---@field inode? integer
---@field dirty integer
---@field error? string

-- State --
---@type table<string, SwapDiffBuffer>

-- Queue of files to process (for sessions)
local recovery_tab = nil
local file_queue = {}
local processing = false

-- Helpers --
---Get absolute path of a file
---@param filename string
---@return string
local function abs_path(filename)
	if not filename or filename == '' then
		return ''
	end
	return fn.fnamemodify(filename, ':p')
end

---Get absolute directory path
---@param filepath string
---@return string
local function abs_dir(filepath)
	if not filepath or filepath == '' then
		return ''
	end
	return fn.fnamemodify(filepath, ':p:h')
end

---Remove prefix from string
---@param prefix string
---@param str string
---@return string
local function remove_prefix(prefix, str)
	if str:sub(1, #prefix) == prefix then
		return str:sub(#prefix + 1)
	else
		return str
	end
end

---Get swap file information for a file
---@param filepath string absolute filepath
---@return SwapDiffSwapInfo[]
local function get_swapinfos(filepath)
	local swapfiles = fn.swapfilelist() or {}
	local results = {}
	local swap_dir = abs_dir(v.swapname) .. '//'

	for _, swapfile in ipairs(swapfiles) do
		local abs_swap = abs_path(remove_prefix(swap_dir, swapfile))
		local info = fn.swapinfo(abs_swap)

		if info and info.fname then
			local abs_fname = abs_path(info.fname)
			if abs_fname == filepath and info.dirty ~= 0 then
				table.insert(results, {
					info = info,
					swappath = abs_swap
				})
			end
		end
	end

	return results
end

---Check if buffer is a swap diff buffer
---@param bufnr integer
---@return table|nil meta Swap metadata or nil
local function get_swap_meta(bufnr)
	if not api.nvim_buf_is_valid(bufnr) then
		return nil
	end

	local ok, meta = pcall(api.nvim_buf_get_var, bufnr, 'swapdiff_meta')
	return ok and meta and meta.swappath and meta or nil
end

---Find all swap buffers in current tab or globally
---@return integer[] bufnrs List of swap buffer numbers
local function find_swap_buffers()
	local buffers = {}

	for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
		if api.nvim_win_is_valid(win) then
			local bufnr = api.nvim_win_get_buf(win)
			if api.nvim_buf_is_loaded(bufnr) and get_swap_meta(bufnr) then
				table.insert(buffers, bufnr)
			end
		end
	end

	return buffers
end

---Clean up a single swap buffer (delete temp file, swap file, buffer)
---@param bufnr integer
local function cleanup_swap_buffer(bufnr)
	local meta = get_swap_meta(bufnr)
	if not meta then return end

	-- Delete temporary recovered file
	local tmp_path = api.nvim_buf_get_name(bufnr)
	if tmp_path and tmp_path ~= '' and fn.filereadable(tmp_path) == 1 then
		local ok, err = pcall(fn.delete, tmp_path)
		if not ok then
			vim.notify('Failed to delete temp file: ' .. tostring(err), vim.log.levels.WARN)
		end
	end

	-- Delete original swap file
	if meta.swappath and fn.filereadable(meta.swappath) == 1 then
		local ok, err = pcall(fn.delete, meta.swappath)
		if not ok then
			vim.notify('Failed to delete swap file: ' .. tostring(err), vim.log.levels.WARN)
		end
	end

	-- Force delete buffer
	if api.nvim_buf_is_valid(bufnr) then
		api.nvim_buf_delete(bufnr, { force = true })
	end
end

---Turn off diff mode for all windows with swap buffers
local function turn_off_current_tab_diff_mode()
	for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
		if api.nvim_win_is_valid(win) and vim.wo[win].diff then
			local ok = pcall(function()
				api.nvim_set_current_win(win)
				vim.cmd('diffoff')
			end)
			if not ok then
				vim.notify('Failed to turn off diff in window ' .. win, vim.log.levels.WARN)
			end
		end
	end
end

---Clean up all swap buffers in scope
---@return integer count Number of cleaned buffers
local function cleanup_all_swap_buffers()
	turn_off_current_tab_diff_mode()

	local swap_buffers = find_swap_buffers()
	local count = #swap_buffers

	for _, bufnr in ipairs(swap_buffers) do
		cleanup_swap_buffer(bufnr)
	end

	return count
end

---Find windows for original and swap buffers
---@param original_bufnr integer
---@return integer|nil orig_win
local function find_buffer_windows_in_tab(original_bufnr)
	for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
		if api.nvim_win_is_valid(win) then
			local win_buf = api.nvim_win_get_buf(win)
			if win_buf == original_bufnr then
				return win
			end
		end
	end
	return nil
end

---Get current buffnr by nvim_get_current_buf and get_swap_meta
---@return integer|nil orig_buffnr
local function get_original_buffnr()
	local current_bufnr = api.nvim_get_current_buf()
	local meta = get_swap_meta(current_bufnr)

	local orig_bufnr
	if meta and meta.original_bufnr then
		-- Current buffer is swap, get original from metadata
		orig_bufnr = meta.original_bufnr
	else
		-- Current buffer is original
		orig_bufnr = current_bufnr
	end

	return api.nvim_buf_is_valid(orig_bufnr) and orig_bufnr or nil
end

---Completion function
---@param arglead string
local function completion(arglead)
	local bufs = {}
	for _, bufnr in ipairs(find_swap_buffers()) do
		local name = api.nvim_buf_get_name(bufnr)
		if name ~= '' then
			table.insert(bufs, name)
		end
	end
	return vim.tbl_filter(function(item)
		return vim.startswith(item, arglead)
	end, bufs)
end

---Recover a swap file to temporary file
---@param swapfile SwapDiffSwapInfo
---@param callback function
local function recover_swapfile(swapfile, callback)
    local original_file = swapfile.info.fname
    local ext = vim.fn.fnamemodify(original_file, ':e')
	local mtime_formatted = os.date('%Y-%m-%d-%H', swapfile.info.mtime)

    local tmpfile = fn.tempname()
    if ext ~= '' then
        local base_tmpfile = tmpfile
        tmpfile = base_tmpfile .. '.' .. mtime_formatted .. '.' .. ext
    else
        tmpfile = tmpfile .. '.' .. mtime_formatted
    end

	local cmd = {
		'nvim',
		'--noplugin',
		'--headless',
		'-n',
		'-r',
		string.format('+w! %s', tmpfile),
		'+q!',
		swapfile.swappath,
	}

	local success, result = pcall(
		vim.system, cmd,
		{
			text = true,
			timeout = 10000
		},
		function(out)
			vim.schedule(function()
				if out.code ~= 0 then
					callback(nil, 'nvim recovery failed with code ' .. out.code)
				elseif fn.filereadable(tmpfile) ~= 1 then
					callback(nil, 'temporary file was not created')
				else
					callback(tmpfile, nil)
				end
			end)
		end)

	if not success then
		vim.schedule(function()
			callback(nil, 'failed to start recovery process: ' .. tostring(result))
		end)
	end
end

---Create recovery tab with original file
---@param pending SwapDiffBuffer
---@return integer main_buf, integer main_win
local function create_recovery_tab(pending)
	vim.cmd.tabnew(pending.relfile)
	local main_win = api.nvim_get_current_win()
	local main_buf = api.nvim_get_current_buf()
	recovery_tab = api.nvim_get_current_tabpage()
	return main_buf, main_win
end

---Create diff split for recovered swap file
---@param tmpfile string
---@param pending SwapDiffBuffer
---@param swapfile SwapDiffSwapInfo
---@param main_buf integer
---@return boolean success
local function create_diff_split(tmpfile, pending, swapfile, main_buf)
	local ok = pcall(function()
		vim.cmd('vert noswapfile diffsplit ' .. vim.fn.fnameescape(tmpfile))
		vim.bo.readonly = true
		vim.bo.modifiable = false
		vim.bo.bufhidden = 'wipe'

		local bufnr = api.nvim_get_current_buf()
		api.nvim_buf_set_var(bufnr, 'swapdiff_meta', {
			relfile = pending.relfile,
			absfile = pending.absfile,
			swappath = swapfile.swappath,
			original_bufnr = main_buf
		})
	end)

	if not ok and fn.filereadable(tmpfile) == 1 then
		pcall(fn.delete, tmpfile)
	end

	return ok
end

---Show recovery completion message
---@param recovered integer
---@param failed integer
---@param total integer
---@param main_win integer
local function show_recovery_summary(recovered, failed, total, main_win)
	vim.schedule(function()
		api.nvim_set_current_win(main_win)
		local msg = string.format('Recovery complete: %d/%d swapfiles processed', recovered, total)

		if failed > 0 then
			msg = msg .. string.format(' (%d failed)', failed)
			vim.notify(msg, vim.log.levels.WARN)
		else
			vim.notify(msg)
		end
	end)
end

---Open recovery interface
---@param pending SwapDiffBuffer
local function start_recovery(pending)
	local main_buf, main_win = create_recovery_tab(pending)

	local stats = { recovered = 0, failed = 0, total = #pending.swapinfos }
	local pending_recoveries = stats.total


	-- Process all swapfiles
	for _, swapfile in ipairs(pending.swapinfos) do
		recover_swapfile(swapfile, function(tmpfile, error_msg)
			if tmpfile then
				if create_diff_split(tmpfile, pending, swapfile, main_buf) then
					stats.recovered = stats.recovered + 1
				else
					stats.failed = stats.failed + 1
				end
			else
				stats.failed = stats.failed + 1
				local swap_name = vim.fn.fnamemodify(swapfile.swappath, ':t')
				vim.notify(string.format('Failed to recover %s: %s', swap_name, error_msg or 'unknown error'),
					vim.log.levels.ERROR)
			end

			-- Check if all recoveries completed
			pending_recoveries = pending_recoveries - 1
			if pending_recoveries == 0 then
				show_recovery_summary(stats.recovered, stats.failed, stats.total, main_win)
			end
		end)
	end
end

local function complete_processing()
	vim.api.nvim_exec_autocmds('User', { pattern = 'SwapDiffProcessComplete' })
end

local function delete_swaps(pending)
	local count = 0
	for _, info in ipairs(pending.swapinfos) do
		if fn.filereadable(info.swappath) == 1 and pcall(fn.delete, info.swappath) then
			count = count + 1
		end
	end
	vim.notify('Deleted ' .. count .. ' swapfiles')
end

---Show prompt using vim.ui.select
---@param pending SwapDiffBuffer
local function show_prompt(pending)
	local options = {
		'Recover and diff all swapfiles',
		'Edit file normally, leaving swapfiles intact',
		'Delete all swapfiles and edit file normally',
	}

	vim.ui.select(options, {
		prompt = string.format(
			'SwapDiff: found %d dirty swapfile(s) for %s:',
			#pending.swapinfos,
			pending.relfile),
	}, function(_, idx)
		if not idx then
			complete_processing()
			return -- User cancelled
		end

		if idx == 1 then
			-- Recover and diff
			start_recovery(pending)
		elseif idx == 2 then
			-- Edit normally
			complete_processing()
		elseif idx == 3 then
			-- Delete swapfiles
			delete_swaps(pending)
			complete_processing()
		end
	end)
end

local function process_next_file()
	if processing or #file_queue == 0 then return end

	processing = true

	local pending = table.remove(file_queue, 1)

	show_prompt(pending)
end

---Handle SwapExists autocmd
---@param args table
function M.onSwapExists(args)
	local filename = args.file
	if not filename or filename == '' then
		return
	end

	vim.v.swapchoice = 'e'
	local filepath = args.match or abs_path(filename)
	if not filepath or filepath == '' then
		return
	end

	local swapfiles = get_swapinfos(filepath)
	if #swapfiles == 0 then
		return
	end

	local pending = {
		relfile = filename,
		absfile = filepath,
		swapinfos = swapfiles,
		main_buf = nil,
	}

	-- Create buffer-local command
	pending.main_buf = vim.api.nvim_get_current_buf()
	api.nvim_buf_create_user_command(pending.main_buf, 'SwapDiff', function()
		show_prompt(pending)
	end, {
		desc = 'Prompt user for action on swap files',
		force = true,
	})

	table.insert(file_queue, pending)

	if not processing then
		vim.schedule(process_next_file)
	end
end

---Setup the plugin
function M.setup()
	-- Create SwapExists autocmd
	local grp = api.nvim_create_augroup('SwapDiff', { clear = true })
	api.nvim_create_autocmd('SwapExists', {
		group = grp,
		callback = M.onSwapExists,
	})

	api.nvim_create_autocmd('User', {
		pattern = 'SwapDiffProcessComplete',
		group = grp,
		callback = function()
			processing = false
			if #file_queue > 0 then
				vim.schedule(process_next_file)
			end
		end
	})

	-- Handle manual tab closure during recovery
	api.nvim_create_autocmd('TabClosed', {
		group = grp,
		callback = function(args)
			local closed_tab = tonumber(args.file)
			if recovery_tab and closed_tab == recovery_tab then
				recovery_tab = nil
				complete_processing()
			end
		end,
	})

	-- SwapDiffDelete command
	vim.api.nvim_create_user_command('SwapDiffDelete', function(opts)
		local bufnr
		if opts.args == '' then
			bufnr = api.nvim_get_current_buf()
		else
			bufnr = tonumber(opts.args) or fn.bufnr(opts.args)
			if bufnr <= 0 then
				return vim.notify('Buffer not found: ' .. opts.args, vim.log.levels.ERROR)
			end
		end

		if not api.nvim_buf_is_loaded(bufnr) then
			return vim.notify('Buffer is not loaded: ' .. opts.args, vim.log.levels.ERROR)
		end

		local meta = get_swap_meta(bufnr)
		if not meta then
			return vim.notify('Error: not a swap diff buffer', vim.log.levels.ERROR)
		end

		cleanup_swap_buffer(bufnr)
		vim.notify('Deleted swap buffer and file: ' .. (meta.swappath or 'unknown'))
	end, {
		nargs = "?",
		complete = completion,
		desc = 'Delete a swap diff buffer by buffer-number or path',
		force = true,
	})

	-- SwapDiffApply command
	vim.api.nvim_create_user_command('SwapDiffApply', function()
		local current_bufnr = api.nvim_get_current_buf()
		local meta = get_swap_meta(current_bufnr)

		if not meta then
			return vim.notify('Error: not a swap diff buffer', vim.log.levels.ERROR)
		end

		local original_bufnr = meta.original_bufnr;
		if not original_bufnr then
			return vim.notify('Original buffer not available', vim.log.levels.ERROR)
		end

		local orig_win = find_buffer_windows_in_tab(original_bufnr)
		if not orig_win then
			return vim.notify('Original window not found', vim.log.levels.ERROR)
		end

		-- Switch to original buffer
		-- Основная логика - если что-то пойдет не так, pcall поймает
		local success, err = pcall(function()
			local swap_lines = api.nvim_buf_get_lines(current_bufnr, 0, -1, false)
			api.nvim_buf_set_lines(original_bufnr, 0, -1, false, swap_lines)
			api.nvim_set_current_win(orig_win)

			if not vim.bo[original_bufnr].modifiable then
				vim.notify('Warning: original buffer is not modifiable', vim.log.levels.WARN)
				return
			end
			vim.cmd('write')
		end)

		if not success then
			return vim.notify('Error applying changes: ' .. (err or 'unknown'), vim.log.levels.ERROR)
		end

		local count = cleanup_all_swap_buffers()
		vim.cmd('tabclose')
		complete_processing()
		vim.notify(string.format('Applied swap to original and cleaned up %d swap buffer(s)', count))
	end, {
		desc = 'Apply swap from current diff-buffer to original and cleanup all',
		force = true,
	})

	-- SwapDiffSaveMerge command
	vim.api.nvim_create_user_command('SwapDiffSaveMerge', function()
		local original_bufnr = get_original_buffnr();

		if not original_bufnr or not api.nvim_buf_is_loaded(original_bufnr) then
			return vim.notify('Original buffer not loaded', vim.log.levels.ERROR)
		end
		-- Save merged original
		local success, err = pcall(function()
			api.nvim_buf_call(original_bufnr, function()
				if not vim.bo.modifiable then
					vim.notify('Warning: buffer is not modifiable', vim.log.levels.WARN)
					return
				end
				vim.cmd('write')
			end)
		end)

		if not success then
			return vim.notify('Failed to save file: ' .. (err or 'unknown error'), vim.log.levels.ERROR)
		end

		local count = cleanup_all_swap_buffers()
		vim.cmd('tabclose')
		complete_processing()
		vim.notify(string.format('Saved original file and cleaned up %d swap buffer(s)', count))
	end, {
		desc = 'Save original file with merged changes and cleanup all swap buffers',
		force = true,
	})
end

return M
