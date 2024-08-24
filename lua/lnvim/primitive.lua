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

return M
