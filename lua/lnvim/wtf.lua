-- wtf.lua
local M = {}
local state = require("lnvim.state")

-- Helper function to check if a command exists
function M.command_exists(cmd)
	local handle = io.popen("command -v " .. cmd .. " 2>/dev/null")
	if handle then
		local result = handle:read("*a")
		handle:close()
		return result and result:len() > 0
	end
	return false
end

-- Map of commands to their installation instructions
local INSTALL_INSTRUCTIONS = {
	qask = "Install with:\n" .. "  - pipx: pipx install https://github.com/baketnk/qask",
	-- Add more tools as needed
}

function M.stream_command(cmd, callback)
	local Job = require("plenary.job")

	local job = Job:new({
		command = "bash",
		args = { "-c", cmd },
		on_stdout = function(_, data)
			if callback then
				callback(data)
			end
		end,
		on_stderr = function(_, data)
			if callback then
				callback("Error: " .. data)
			end
		end,
	})

	return job:start()
end

-- Function to check command and show installation instructions
function M.ensure_command(cmd)
	if not M.command_exists(cmd) then
		local msg =
			string.format("Command '%s' not found.\n%s", cmd, INSTALL_INSTRUCTIONS[cmd] or "Please install " .. cmd)
		vim.notify(msg, vim.log.levels.WARN)
		return false
	end
	return true
end

M.get_lsp_diagnostics_in_range = vim.schedule_wrap(function(start_line, end_line)
	local diagnostics = vim.diagnostic.get(0)
	local relevant_diagnostics = {}

	for _, diagnostic in ipairs(diagnostics) do
		-- Convert to 0-based line numbers for comparison
		local diag_line = diagnostic.lnum
		if diag_line >= start_line - 1 and diag_line <= end_line - 1 then
			table.insert(relevant_diagnostics, {
				severity = diagnostic.severity,
				message = diagnostic.message,
				line = diag_line + 1, -- Convert back to 1-based for display
			})
		end
	end

	if #relevant_diagnostics > 0 then
		local result = { "LSP Diagnostics:" }
		for _, diag in ipairs(relevant_diagnostics) do
			local severity = vim.diagnostic.severity[diag.severity]
			table.insert(result, string.format("- %s (line %d): %s", severity, diag.line, diag.message))
		end
		return table.concat(result, "\n")
	end
	return nil
end)

M.get_symbol_info_in_range = vim.schedule_wrap(function(start_line, end_line, callback)
	local bufnr = vim.api.nvim_get_current_buf()
	local symbols = {}
	local pending_requests = 0
	local has_results = false

	-- Get all clients that support hover
	local clients = vim.lsp.get_active_clients({
		bufnr = bufnr,
		method = "textDocument/hover",
	})

	if #clients == 0 then
		callback(nil)
		return
	end

	-- Function to process each line in the range
	local function process_line(lnum)
		local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
		local words = vim.split(line, "[^%w_]")

		for _, word in ipairs(words) do
			if word:match("^[%w_]+$") then -- Basic identifier check
				pending_requests = pending_requests + 1

				vim.lsp.buf_request(bufnr, "textDocument/hover", {
					textDocument = vim.lsp.util.make_text_document_params(),
					position = { line = lnum, character = line:find(word) - 1 },
				}, function(_, result, _, _)
					pending_requests = pending_requests - 1

					if result and result.contents then
						has_results = true
						local contents = result.contents
						if type(contents) == "table" then
							if contents.kind == "markdown" then
								contents = contents.value
							else
								contents = vim.inspect(contents)
							end
						end
						symbols[word] = contents
					end

					-- Check if we're done processing all requests
					if pending_requests == 0 then
						if has_results then
							local result = { "Symbol Information:" }
							for symbol, info in pairs(symbols) do
								table.insert(result, string.format("- %s: %s", symbol, info:gsub("\n", " ")))
							end
							callback(table.concat(result, "\n"))
						else
							callback(nil)
						end
					end
				end)
			end
		end
	end

	-- Process each line in the range
	for lnum = start_line - 1, end_line - 1 do
		process_line(lnum)
	end

	-- Handle case where no requests were made
	if pending_requests == 0 then
		callback(nil)
	end
end)

function M.visual_quick_ask()
	if not M.ensure_command("qask") then
		return
	end

	-- Get the selected text
	local _, start_line, start_col, _ = unpack(vim.fn.getpos("'<"))
	local _, end_line, end_col, _ = unpack(vim.fn.getpos("'>"))
	local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line + 1, false)
	vim.inspect(vim.fn.getpos("'<"))
	vim.inspect(vim.fn.getpos("'>"))
	vim.print(lines)
	-- Adjust the text selection
	if #lines == 1 then
		lines[1] = string.sub(lines[1], start_col, end_col + 1)
	else
		if lines[1] then
			lines[1] = string.sub(lines[1], start_col)
		end
		if lines[#lines] then
			lines[#lines] = string.sub(lines[#lines], 1, end_col + 1)
		end
	end

	-- Get LSP information asynchronously
	M.get_symbol_info_in_range(start_line, end_line, function(symbol_info)
		-- Get current buffer context
		local filetype = vim.bo.filetype
		local filename = vim.fn.expand("%:t")
		local relative_path = vim.fn.expand("%:.")
		local buf_context = string.format(
			"Context:\n" .. "- File: %s\n" .. "- Path: %s\n" .. "- Language: %s\n",
			filename,
			relative_path,
			filetype ~= "" and filetype or "unknown"
		)

		-- Add LSP clients
		local has_lsp = false
		for _, client in pairs(vim.lsp.get_active_clients({ bufnr = 0 })) do
			if client.name then
				buf_context = buf_context .. "- LSP: " .. client.name .. "\n"
				has_lsp = true
			end
		end

		-- Get diagnostics
		local diagnostics = M.get_lsp_diagnostics_in_range(start_line, end_line)
		if diagnostics then
			buf_context = buf_context .. "\n" .. diagnostics .. "\n"
		end

		-- Add symbol information if available
		if symbol_info then
			buf_context = buf_context .. "\n" .. symbol_info .. "\n"
		end

		-- Prepare the prompt content
		local prompt_content = {
			"You are an expert software engineer.",
			"Please help me understand this code or text:",
			"",
			buf_context,
			"Selected text to analyze:",
			"```" .. (filetype ~= "" and filetype or ""),
		}

		-- Add the selected content
		vim.list_extend(prompt_content, lines)
		table.insert(prompt_content, "```")
		table.insert(prompt_content, "Please explain what this means and provide any relevant insights.")

		-- If we have LSP, ask for more specific insights
		if has_lsp then
			table.insert(
				prompt_content,
				"Since we have LSP available, please also comment on any potential issues or improvements regarding:"
			)
			table.insert(prompt_content, "- Code style and best practices")
			table.insert(prompt_content, "- Potential bugs or edge cases")
			table.insert(prompt_content, "- Performance considerations")
		end

		-- Create a temporary file
		local temp_file = vim.fn.tempname()
		vim.fn.writefile(prompt_content, temp_file)

		-- Create the streaming window
		local modal = require("lnvim.ui.modal")
		local stream_win = modal.stream_window({
			width = math.min(120, vim.o.columns * 0.8),
			height = math.floor(vim.o.lines * 0.8),
		})

		-- Stream the command output
		M.stream_command(string.format("qask --model=%s --prompt-file=%s", state.wtf_model, temp_file), function(data)
			stream_win.append(data)
		end)

		-- Clean up the temporary file
		vim.defer_fn(function()
			vim.fn.delete(temp_file)
		end, 1000)
	end)
end

return M
