local M = {}
local constants = require("lnvim.constants")
local buffers = require("lnvim.ui.buffers")
local state = require("lnvim.state")
local function get_cfg()
	return require("lnvim.cfg")
end

function M.create_layout()
	local width = vim.o.columns
	local height = vim.o.lines

	-- Calculate dimensions
	local col1_width = math.floor(width * 0.6)
	local col2_width = width - col1_width

	local layout = {}

	-- Create column layout
	layout.main = vim.api.nvim_get_current_win()
	vim.cmd("vsplit")
	layout.diff = vim.api.nvim_get_current_win()

	-- Set buffers to windows
	vim.api.nvim_win_set_buf(layout.diff, buffers.diff_buffer)

	-- Create summary window
	vim.cmd("split")
	layout.summary = vim.api.nvim_get_current_win()
	buffers.summary_buffer = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(layout.summary, buffers.summary_buffer)

	-- Set window sizes
	vim.cmd("vertical resize " .. col2_width)
	vim.cmd("resize " .. math.floor(5))

	M.layout = layout

	vim.api.nvim_create_autocmd("BufEnter", {
		buffer = buffers.diff_buffer,
		callback = function()
			vim.schedule(M.ensure_correct_diff_buffer)
		end,
	})

	return layout
end

function M.update_summary()
	if M.layout and vim.api.nvim_win_is_valid(M.layout.summary) then
		local summary = state.get_summary()
		vim.api.nvim_buf_set_option(buffers.summary_buffer, "modifiable", true)
		vim.api.nvim_buf_set_lines(buffers.summary_buffer, 0, -1, false, vim.split(summary, "\n"))
		vim.api.nvim_buf_set_option(buffers.summary_buffer, "modifiable", false)
	end
end

function M.get_layout()
	return M.layout
end

function M.close_layout()
	pcall(vim.api.nvim_win_close, M.layout.diff, true)
	pcall(vim.api.nvim_win_close, M.layout.files, true)
	pcall(vim.api.nvim_win_close, M.layout.progress, true)
	pcall(vim.api.nvim_win_close, M.layout.preamble, true)
	M.layout = nil
end
function M.focus_drawer()
	vim.api.nvim_set_current_win(M.layout.diff)
end

local function init_buffer(buf)
	if buf ~= nil then
		return buf
	end
	return vim.api.nvim_create_buf(false, true)
end

function M.ensure_correct_diff_buffer()
	if M.layout and vim.api.nvim_win_is_valid(M.layout.diff) then
		local current_buf = vim.api.nvim_win_get_buf(M.layout.diff)
		if current_buf ~= buffers.diff_buffer then
			-- Switch the diff window back to the correct buffer
			vim.api.nvim_win_set_buf(M.layout.diff, buffers.diff_buffer)

			-- Move the user to the main window
			vim.api.nvim_set_current_win(M.layout.main)

			-- Switch to the intended buffer in the main window
			vim.api.nvim_win_set_buf(M.layout.main, current_buf)

			-- Notify the user
			vim.notify("Switched to the intended buffer in the main window", vim.log.levels.INFO)
		end
	end
end

function M.show_drawer()
	local cfg = get_cfg()
	-- Set up buffers
	buffers.diff_buffer = init_buffer(buffers.diff_buffer)
	local layout = M.create_layout()
	-- Mount the layout

	vim.api.nvim_buf_set_name(
		buffers.diff_buffer,
		"~" .. os.date("!%Y-%m-%d_%H-%M-%S_out") .. "." .. constants.filetype_ext
	)
	-- diff buffer opts
	vim.api.nvim_win_set_option(layout.diff, "wrap", true)

	-- Focus on the prompt window
	vim.api.nvim_set_current_win(layout.diff)
	if
		vim.api.nvim_buf_line_count(buffers.diff_buffer) == 1
		and vim.api.nvim_buf_get_lines(buffers.diff_buffer, 0, -1, false)[1] == ""
	then
		require("lnvim.llm").print_user_delimiter()
	end
	M.update_summary()
end

return M
