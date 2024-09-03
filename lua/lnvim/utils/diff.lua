local M = {}

function M.applyDiff(originalLines, diffText)
	local result = {}
	local currentLine = 1
	local hunkStart, hunkEnd, hunkLines

	for line in diffText:gmatch("[^\r\n]+") do
		-- Ignore file headers
		if
			line:match("^diff %-%-git")
			or line:match("^index %x+%.%x+ %d+")
			or line:match("^%-%-%- %S+")
			or line:match("^%+%+%+ %S+")
		then
			-- Skip these lines
		elseif line:match("^@@") then
			-- Apply previous hunk if exists
			if hunkLines then
				for _, hunkLine in ipairs(hunkLines) do
					table.insert(result, hunkLine)
				end
			end

			-- Parse new hunk header
			hunkStart, hunkEnd = line:match("@@ %-(%d+),?%d*%s+%+(%d+)")
			hunkStart, hunkEnd = tonumber(hunkStart), tonumber(hunkEnd)

			-- Copy lines before the hunk
			while currentLine < hunkStart do
				table.insert(result, originalLines[currentLine])
				currentLine = currentLine + 1
			end

			hunkLines = {}
		elseif line:sub(1, 1) == "+" then
			-- Add new line
			table.insert(hunkLines, line:sub(2))
		elseif line:sub(1, 1) == "-" then
			-- Skip removed line
			currentLine = currentLine + 1
		elseif line:sub(1, 1) == " " then
			-- Keep unchanged line
			table.insert(hunkLines, line:sub(2))
			currentLine = currentLine + 1
		end
	end

	-- Apply last hunk
	if hunkLines then
		for _, hunkLine in ipairs(hunkLines) do
			table.insert(result, hunkLine)
		end
	end

	-- Copy remaining lines after the last hunk
	while currentLine <= #originalLines do
		table.insert(result, originalLines[currentLine])
		currentLine = currentLine + 1
	end

	return result
end

return M
