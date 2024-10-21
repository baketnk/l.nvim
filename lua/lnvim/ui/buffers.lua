local M = {}

local function init_buffer(buf)
	if buf ~= nil then
		return buf
	end
	return vim.api.nvim_create_buf(false, true)
end

M.diff_buffer = init_buffer(nil)
M.summary_buffer = init_buffer(nil)

return M
