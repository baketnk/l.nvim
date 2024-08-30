local M = {}

function M.applyDiff(lines, diffText)
	local function split(str, sep)
		local result = {}
		for s in (str .. sep):gmatch("(.-)" .. sep) do
			table.insert(result, s)
		end
		return result
	end

	for diffLine in diffText:gmatch("[^\r\n]+") do
		local lineNum, operation, content = diffLine:match("(%d+):?(%S*) (.+)")
		lineNum = tonumber(lineNum)

		if operation == "+" then
			-- Add a new line
			table.insert(lines, lineNum + 1, content:match('"(.+)"'))
		elseif operation:match("%d+%-%d+") then
			-- Replace part of a line
			local start, finish = operation:match("(%d+)%-(%d+)")
			start, finish = tonumber(start), tonumber(finish)
			local old, new = content:match('"(.+)" %-> "(.+)"')
			lines[lineNum] = lines[lineNum]:sub(1, start - 1) .. new .. lines[lineNum]:sub(finish + 1)
		else
			-- Replace entire line
			local old, new = content:match('"(.+)" %-> "(.+)"')
			lines[lineNum] = new
		end
	end

	return lines
end

return M
