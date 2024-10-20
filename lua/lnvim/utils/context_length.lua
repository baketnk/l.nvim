local M = {}

-- Assuming token counting is approximated by character count
function M.calculate_context_length(context)
	local total = 0
	for _, segment in ipairs(context) do
		total = total + #segment
	end
	return total
end

-- Function to reduce context when exceeding a limit
function M.manage_context(context, max_length)
	local current_length = M.calculate_context_length(context)
	if current_length <= max_length then
		return context
	end

	-- Simple strategy: Remove the oldest entries
	while #context > 0 and M.calculate_context_length(context) > max_length do
		table.remove(context, 1)
	end

	return context
end

return M
