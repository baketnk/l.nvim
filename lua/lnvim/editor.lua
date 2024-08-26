local M = {}

local ns_id = vim.api.nvim_create_namespace("LnvimCodeblock")

function M.get_current_codeblock_contents(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = cursor[1] - 1
	local col = cursor[2]

	local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, { line, col }, { line, col }, {
		details = true,
		limit = 1,
		overlap = true,
	})
	if #extmarks <= 0 then
		return nil
	end
	local extmark = extmarks[1]
	local start_line = extmark[2] + 1 -- skip the leading backtick line
	-- local start_col = extmark[3]
	local end_line = extmark[4].end_row -- no +1 index here to skip final backticks
	-- local end_col = extmark[4].end_col
	vim.print(vim.inspect(extmark))
	local lines = vim.api.nvim_buf_get_lines(buf, start_line, end_line, false)
	return lines
end

function M.paste_to_mark(mark_str, lines)
	local destmark = vim.api.nvim_get_mark(mark_str, {})
	if not destmark then
		vim.notify("mark missing abort")
		return nil
	end
	vim.api.nvim_buf_set_lines(destmark[3], destmark[1], destmark[1], false, lines)
end

function M.yank_codeblock()
	local lines = M.get_current_codeblock_contents()
	if not lines then
		vim.notify("No codeblock found at cursor position", vim.log.levels.WARN)
		return
	end

	-- Join the lines into a single string
	local content = table.concat(lines, "\n")

	-- Copy to clipboard
	vim.fn.setreg("+", content)
	vim.fn.setreg('"', content)

	-- Provide feedback
	vim.notify("Codeblock yanked to clipboard", vim.log.levels.INFO)
end

function M.put_codeblock(mark, buf)
	buf = buf or vim.api.nvim_get_current_buf() -- TODO: this needs to be the marked buff
	-- TODO: allow for treesitter or other pointing addreses for one-key work
	--
	-- First, call yank_codeblock to ensure we have the latest codeblock content
	M.yank_codeblock()

	-- Get the content from the clipboard
	local content = vim.fn.getreg("+")

	if content == "" then
		vim.notify("No codeblock content to paste", vim.log.levels.WARN)
		return
	end

	-- Split the content into lines
	-- Get-a-load-of-this-llm-cam
	local lines = vim.split(content, "\n")

	-- Use the previously set mark as the destination
	local mark = vim.api.nvim_mark(0, mark or "T")
	if mark[1] == 0 and mark[2] == 0 then
		vim.notify("No destination mark set. Use 'mT' to set a mark first.", vim.log.levels.WARN)
		return
	end

	local dest_buf = vim.api.nvim_get_current_buf()
	local dest_line = mark[1] - 1 -- Convert to 0-indexed
	local dest_col = mark[2]

	-- Insert the codeblock
	vim.api.nvim_buf_set_text(dest_buf, dest_line, dest_col, dest_line, dest_col, lines)

	-- Add the codeblock markers
	vim.api.nvim_buf_set_lines(dest_buf, dest_line, dest_line, false, { "```" })
	vim.api.nvim_buf_set_lines(dest_buf, dest_line + #lines + 1, dest_line + #lines + 1, false, { "```" })

	-- Provide feedback
	vim.notify("Codeblock pasted at mark position", vim.log.levels.INFO)
end

function M.goto_next_codeblock(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local cursor_row = cursor[1] - 1 -- Convert to 0-indexed
	local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, cursor, -1, { details = true, limit = 2 })
	local next_block = nil

	if #extmarks > 0 then
		if cursor_row < extmarks[1][2] then
			next_block = extmarks[1]
		elseif #extmarks > 1 then
			next_block = extmarks[2]
		end
	end
	if not next_block then
		extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, cursor, { details = true, limit = 1 })
		next_block = extmarks[1]
	end

	if next_block then
		-- Move cursor to the start of the next block
		vim.api.nvim_win_set_cursor(0, { next_block[2] + 1, 0 }) -- Convert back to 1-indexed
	end
end

function M.goto_prev_codeblock(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local cursor_row = cursor[1] - 1 -- Convert to 0-indexed

	local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, { details = true })
	local prev_block_start = nil

	-- Sort extmarks by start line in reverse order
	table.sort(extmarks, function(a, b)
		return a[2] > b[2]
	end)

	local current_block_index = nil
	for i, mark in ipairs(extmarks) do
		local start_line = mark[2]
		local end_line = mark[4].end_row

		if cursor_row >= start_line and cursor_row <= end_line then
			current_block_index = i
			break
		end
	end

	if current_block_index then
		-- Cursor is within a block, move to the previous one
		if current_block_index < #extmarks then
			prev_block_start = extmarks[current_block_index + 1][2]
		else
			-- If this is the first block, wrap to the last one
			prev_block_start = extmarks[1][2]
		end
	else
		-- Cursor is not within any block, find the previous one
		for _, mark in ipairs(extmarks) do
			if mark[2] < cursor_row then
				prev_block_start = mark[2]
				break
			end
		end
		-- If no previous block found, wrap to the last one
		if not prev_block_start and #extmarks > 0 then
			prev_block_start = extmarks[1][2]
		end
	end

	if prev_block_start then
		-- Move cursor to the start of the previous block
		vim.api.nvim_win_set_cursor(0, { prev_block_start + 1, 0 }) -- Convert back to 1-indexed
	end
end

function M.mark_codeblocks(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

	-- Pattern to match codeblocks (triple backticks)
	local codeblock_pattern = "^```.*"

	-- Flag to track if we are inside a codeblock
	local in_codeblock = false
	local block_start = -1
	-- Iterate over each line
	for i, line in ipairs(lines) do
		-- Check if the line matches the codeblock pattern
		if line:match(codeblock_pattern) then
			-- Toggle the in_codeblock flag
			in_codeblock = not in_codeblock

			-- If we are entering a codeblock, add a highlight group
			if in_codeblock then
				block_start = i - 1
			else
				-- vim.notify("extmark set " .. block_start .. "," .. (i - 1))
				vim.api.nvim_buf_set_extmark(buf, ns_id, block_start, 0, {
					end_line = i - 1,
					end_col = #lines[i],
					hl_group = "CodeBlock",
				})
				block_start = -1
			end
		end
	end
end

function M.highlight_extmarks(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, { details = true })
	for _, mark in ipairs(extmarks) do
		local row, col, details = unpack(mark, 2)
		for i = row, details.end_row do
			local start_col = (i == row) and col or 0
			local end_col = (i == details.end_row) and details.end_col or -1
			vim.api.nvim_buf_add_highlight(buf, ns_id, "CodeBlock", i, start_col, end_col)
		end
	end
end

function M.print_extmarks(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	local extmarks = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, { details = true })
	-- print("extmarks")
	for _, mark in ipairs(extmarks) do
		local row, col, details = unpack(mark, 2)
		local start_line, start_col = row, col
		local end_line, end_col = details.end_row, details.end_col
		local hl_group = details.hl_group

		print(
			string.format(
				"Extmark: start=(%d, %d), end=(%d, %d), hl_group=%s",
				start_line,
				start_col,
				end_line,
				end_col,
				hl_group
			)
		)
	end
end

vim.api.nvim_set_hl(0, "CodeBlock", {
	bg = vim.o.background == "dark" and "#2c2c2c" or "#eeeeee",
	fg = vim.o.background == "dark" and "#eeeeee" or "#2c2c2c",
})
vim.api.nvim_set_hl(0, "CodeBlockActive", {
	bg = vim.o.background == "dark" and "#3c3c3c" or "#dddddd",
	fg = vim.o.background == "dark" and "#ffffff" or "##000000",
})
vim.api.nvim_set_hl(0, "LLMStream", {
	bg = vim.o.background == "dark" and "#111111" or "#eeeeee",
	fg = vim.o.background == "dark" and "#bcbcbc" or "#454545",
})

return M
