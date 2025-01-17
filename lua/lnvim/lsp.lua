local M = {}
local buffers = require("lnvim.ui.buffers")

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
