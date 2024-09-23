local M = {}
local buffers = require("lnvim.ui.buffers")

function M.get_lsp_definition(lsp_entry)
	-- Parse the lsp_entry
	local kind, name, file, line, col = lsp_entry:match("@lsp:(%w+):([^:]+):([^:]+):(%d+):(%d+)")
	if not kind or not name or not file or not line or not col then
		vim.notify("Invalid LSP entry format", vim.log.levels.ERROR)
		return nil
	end

	-- Convert line and col to numbers
	line = tonumber(line)
	col = tonumber(col)

	-- Get the LSP client
	local client = vim.lsp.get_active_clients()[1]
	if not client then
		vim.notify("No active LSP client found", vim.log.levels.ERROR)
		return nil
	end

	-- Prepare the LSP request
	local params = {
		textDocument = { uri = vim.uri_from_fname(file) },
		position = { line = line - 1, character = col - 1 },
	}

	-- Make the LSP request
	local result, err = client.request_sync("textDocument/definition", params, 1000, 0)
	if err then
		vim.notify("Error fetching definition: " .. err, vim.log.levels.ERROR)
		return nil
	end

	if not result or not result.result or #result.result == 0 then
		vim.notify("No definition found for " .. name, vim.log.levels.WARN)
		return nil
	end

	-- Get the definition location
	local definition = result.result[1]
	local def_uri = definition.uri or definition.targetUri
	local def_range = definition.range or definition.targetRange

	-- Read the file content
	local def_content = vim.fn.readfile(vim.uri_to_fname(def_uri))

	-- Extract the relevant lines
	local start_line = def_range.start.line
	local end_line = def_range["end"].line
	local definition_lines = vim.list_slice(def_content, start_line + 1, end_line + 1)

	-- Format the output
	local output = string.format("Definition of %s (%s):\n", name, kind)
	output = output .. table.concat(definition_lines, "\n")

	return output
end

function M.handle_lsp_selection(selection)
	local client = vim.lsp.get_clients()[1]
	if not client then
		vim.notify("No active LSP client found", vim.log.levels.ERROR)
		return
	end

	local params = vim.lsp.util.make_position_params()
	params.position = selection.lnum and { selection.lnum - 1, selection.col } or params.position

	client.request("textDocument/definition", params, function(err, result)
		if err then
			vim.notify("Error fetching definition: " .. err.message, vim.log.levels.ERROR)
			return
		end

		if result and #result > 0 then
			local definition = result[1]
			local uri = definition.uri or definition.targetUri
			local range = definition.range or definition.targetRange

			-- Fetch the content of the file
			local content = vim.fn.readfile(vim.uri_to_fname(uri))
			local start_line = range.start.line
			local end_line = range["end"].line

			-- Extract the relevant lines
			local definition_lines = vim.list_slice(content, start_line + 1, end_line + 1)

			-- Add the definition to the files buffer
			local lsp_entry = string.format(
				"@lsp:%s:%s:%s:%d:%d",
				selection.kind,
				selection.name,
				vim.uri_to_fname(uri),
				start_line + 1,
				range.start.character + 1
			)
			vim.api.nvim_buf_set_lines(buffers.files_buffer, -1, -1, false, { lsp_entry })

			vim.notify("LSP definition added to file buffer", vim.log.levels.INFO)
		else
			vim.notify("No definition found for " .. selection.name, vim.log.levels.WARN)
		end
	end)
end

return M
