local M = {}
local constants = require("lnvim.constants")
local buffers = require("lnvim.ui.buffers")
local LazyLoad = require("lnvim.utils.lazyload")

local function get_cfg()
	return require("lnvim.cfg")
end

function M.create_layout()
	local width = vim.o.columns
	local height = vim.o.lines

	-- Calculate dimensions
	local col1_width = math.floor(width * 0.4)
	local col2_width = math.floor(width * 0.35)
	local col3_width = math.floor(width * 0.25)

	local row1_height = math.floor(height * 0.3)
	local row2_height = 8
	local row3_height = height - row1_height - row2_height
	local layout = {}

	-- Function to find or create a window for a specific buffer
	layout.main = vim.api.nvim_get_current_win()

	-- Create column layout
	vim.cmd("vsplit")
	vim.cmd("wincmd L")
	layout.diff = vim.api.nvim_get_current_win()

	vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), buffers.diff_buffer)
	vim.cmd("vsplit")
	layout.files = vim.api.nvim_get_current_win()

	-- Set buffers to windows
	vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), buffers.files_buffer)

	-- Create preamble window
	vim.cmd("split")
	layout.preamble = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), buffers.preamble_buffer)

	-- create progress window
	vim.cmd("split")
	layout.progress = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(layout.progress, buffers.progress_buffer)
	vim.api.nvim_win_set_option(layout.progress, "wrap", true)
	vim.api.nvim_win_set_option(layout.progress, "signcolumn", "no")
	vim.api.nvim_win_set_option(layout.progress, "number", false)
	vim.api.nvim_win_set_option(layout.progress, "relativenumber", false)
	-- Initialize progress buffer
	vim.api.nvim_buf_set_name(
		buffers.progress_buffer,
		"~" .. os.date("!%Y-%m-%d_%H-%M-%S_progress") .. "." .. constants.filetype_ext
	)
	vim.api.nvim_buf_set_lines(buffers.progress_buffer, 0, -1, false, { "Chain Execution Progress:" })
	vim.api.nvim_win_set_option(layout.progress, "foldmethod", "manual")
	vim.api.nvim_win_set_option(layout.progress, "foldlevel", 0)

	vim.cmd("wincmd h")
	vim.cmd("wincmd h")
	-- Set window sizes
	vim.cmd("vertical resize " .. col1_width)
	vim.cmd("wincmd l")
	vim.cmd("vertical resize " .. col2_width)
	vim.cmd("wincmd l")
	vim.cmd("vertical resize " .. col3_width)
	vim.cmd("resize " .. row1_height)
	vim.cmd("wincmd j")
	vim.cmd("resize " .. row2_height)
	-- Update layout table with new window IDs
	layout.main = vim.fn.win_findbuf(vim.api.nvim_get_current_buf())[1]
	layout.diff = vim.fn.win_findbuf(buffers.diff_buffer)[1]
	layout.files = vim.fn.win_findbuf(buffers.files_buffer)[1]
	layout.preamble = vim.fn.win_findbuf(buffers.preamble_buffer)[1]
	layout.progress = vim.fn.win_findbuf(buffers.progress_buffer)[1]
	M.layout = layout

	return layout
end

-- Function to log messages to the Progress buffer
function M.log_progress(message)
	local buf = buffers.progress_buffer
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	table.insert(lines, message)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

function M.get_layout()
	return M.layout
end

function M.close_layout()
	pcall(vim.api.nvim_win_close, M.layout.diff, true)
	pcall(vim.api.nvim_win_close, M.layout.files, true)
	pcall(vim.api.nvim_win_close, M.layout.work, true)
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

function M.show_drawer()
	local cfg = get_cfg()
	-- Set up buffers
	buffers.progress_buffer = init_buffer(buffers.progress_buffer)
	buffers.preamble_buffer = init_buffer(buffers.preamble_buffer)
	buffers.diff_buffer = init_buffer(buffers.diff_buffer)
	buffers.files_buffer = init_buffer(buffers.files_buffer)
	buffers.new_version_buffer = init_buffer(buffers.new_version_buffer)
	local layout = M.create_layout()
	-- Mount the layout

	vim.api.nvim_buf_set_name(buffers.preamble_buffer, cfg.project_lnvim_dir .. "/preamble.txt")
	local preamble_file = io.open(cfg.project_lnvim_dir .. "/preamble.txt", "r")
	if preamble_file then
		local preamble_content = preamble_file:read("*a")
		preamble_file:close()
		vim.api.nvim_buf_set_lines(buffers.preamble_buffer, 0, -1, false, vim.split(preamble_content, "\n"))
	end
	vim.api.nvim_win_set_option(layout.preamble, "wrap", true)

	vim.api.nvim_buf_set_name(
		buffers.diff_buffer,
		"~" .. os.date("!%Y-%m-%d_%H-%M-%S_out") .. "." .. constants.filetype_ext
	)
	-- diff buffer opts
	vim.api.nvim_win_set_option(layout.diff, "wrap", true)

	vim.api.nvim_win_set_option(layout.files, "wrap", true)
	-- Focus on the prompt window
	vim.api.nvim_set_current_win(layout.diff)
	if
		vim.api.nvim_buf_line_count(buffers.diff_buffer) == 1
		and vim.api.nvim_buf_get_lines(buffers.diff_buffer, 0, -1, false)[1] == ""
	then
		require("lnvim.llm").print_user_delimiter()
	end
end

return M
