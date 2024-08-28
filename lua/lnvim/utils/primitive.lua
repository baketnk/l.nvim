local M = {}

function M.flatten(table)
	local flat_table = {}

	for _, v in ipairs(table) do
		if type(v) == "table" then
			local flattened_subtable = M.flatten(v)
			for _, subvalue in ipairs(flattened_subtable) do
				flat_table[#flat_table + 1] = subvalue
			end
		else
			flat_table[#flat_table + 1] = v
		end
	end

	return flat_table
end

function M.debounce(func, wait)
	local timer = vim.timer
	return function(...)
		local context = { ... }
		timer:stop()
		timer:start(
			wait,
			0,
			vim.schedule_wrap(function()
				func(unpack(context))
			end)
		)
	end
end

function M.print_cursor_info(msg)
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_get_current_buf()
	local ok, cursor = pcall(vim.api.nvim_win_get_cursor, win)
	if not ok then
		vim.notify("Error getting cursor: " .. tostring(cursor), vim.log.levels.ERROR)
		return
	end
	vim.notify(msg .. " Win: " .. win .. "Buf: " .. buf .. "Cursor: " .. vim.inspect(cursor), vim.log.levels.DEBUG)
end
return M
