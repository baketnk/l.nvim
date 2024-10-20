local M = {}

local function init_buffer(buf)
	if buf ~= nil then
		return buf
	end
	return vim.api.nvim_create_buf(false, true)
end

M.preamble_buffer = init_buffer(nil)
M.diff_buffer = init_buffer(nil)
M.files_buffer = init_buffer(nil)
M.new_version_buffer = init_buffer(nil)
M.progress_buffer = init_buffer(nil)

return M
