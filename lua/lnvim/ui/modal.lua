local api = vim.api

local M = {}

-- Function to create a centered floating window
local function create_centered_float(width, height, vertical_offset)
	vertical_offset = vertical_offset or 0
	local vim_width = api.nvim_get_option("columns")
	local vim_height = api.nvim_get_option("lines")

	local row = math.floor((vim_height - height) * 0.5) + vertical_offset
	local col = math.floor((vim_width - width) * 0.5)

	local opts = {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
	}

	return api.nvim_create_buf(false, true), opts
end

-- Function to wrap text
local function wrap_text(text, width)
	local wrapped = {}
	for _, line in ipairs(text) do
		while #line > width do
			local breakpoint = width
			while breakpoint > 0 and line:sub(breakpoint, breakpoint) ~= " " do
				breakpoint = breakpoint - 1
			end
			if breakpoint == 0 then
				breakpoint = width
			end
			table.insert(wrapped, line:sub(1, breakpoint))
			line = line:sub(breakpoint + 1)
		end
		table.insert(wrapped, line)
	end
	return wrapped
end

-- Function to create the modal input window
function M.modal_input(opts, on_confirm, on_cancel)
	opts = opts or {}
	local prompt = opts.prompt or "Enter input:"
	local default = opts.default or { "" }
	if type(default) == "string" then
		default = { default }
	end
	local input_height = opts.input_height or 5

	local width = math.min(80, vim.api.nvim_get_option("columns"))
	local instruction_text = { prompt, "", "Press <Enter> to confirm, or close the window to cancel" }
	local wrapped_instructions = wrap_text(instruction_text, width - 2)
	local instruction_height = #wrapped_instructions

	-- Create instruction buffer and window
	local instruction_buf, instruction_win_opts = create_centered_float(width, instruction_height, -2)
	local instruction_win = api.nvim_open_win(instruction_buf, false, instruction_win_opts)

	-- Set instruction buffer content and options
	api.nvim_buf_set_lines(instruction_buf, 0, -1, false, wrapped_instructions)
	api.nvim_buf_set_option(instruction_buf, "modifiable", false)
	api.nvim_buf_set_option(instruction_buf, "buftype", "nofile")

	-- Set instruction window options for different styling
	api.nvim_win_set_option(instruction_win, "winhl", "Normal:Comment")

	-- Create input buffer and window
	local input_buf, input_win_opts = create_centered_float(width, input_height)
	input_win_opts.row = input_win_opts.row + instruction_height + 1
	local input_win = api.nvim_open_win(input_buf, true, input_win_opts)

	-- Set input buffer options
	api.nvim_buf_set_option(input_buf, "buftype", "nofile")
	api.nvim_buf_set_option(input_buf, "bufhidden", "wipe")
	api.nvim_buf_set_option(input_buf, "swapfile", false)
	api.nvim_buf_set_option(input_buf, "modifiable", true)

	-- Set input window options
	api.nvim_win_set_option(input_win, "winblend", 10)
	api.nvim_win_set_option(input_win, "cursorline", true)

	-- Add default text to input buffer
	api.nvim_buf_set_lines(input_buf, 0, -1, false, default)

	-- Set cursor position
	api.nvim_win_set_cursor(input_win, { 1, #default })

	-- Function to get input
	local function get_input()
		return api.nvim_buf_get_lines(input_buf, 0, -1, false)[1]
	end

	-- Function to close windows
	local function close_windows()
		api.nvim_win_close(input_win, true)
		api.nvim_win_close(instruction_win, true)
	end

	-- Set up autocommands for window close and buffer leave
	local augroup = api.nvim_create_augroup("ModalInputAugroup", { clear = true })

	api.nvim_create_autocmd({ "BufLeave", "WinClosed" }, {
		buffer = input_buf,
		group = augroup,
		callback = function()
			pcall(close_windows)
			if on_cancel then
				on_cancel()
			end
		end,
	})

	-- Set up Enter keymap for confirmation
	api.nvim_buf_set_keymap(input_buf, "n", "<CR>", "", {
		callback = function()
			local input = get_input()
			pcall(close_windows)
			if on_confirm then
				on_confirm(input)
			end
		end,
		noremap = true,
		silent = true,
	})

	-- Enter insert mode
	vim.cmd("startinsert!")
end

function M.stream_window(opts)
	opts = opts or {}
	local width = opts.width or math.min(120, vim.api.nvim_get_option("columns"))
	local height = opts.height or math.floor(vim.api.nvim_get_option("lines") * 0.8)

	-- Create buffer and window
	local buf, win_opts = create_centered_float(width, height)
	local win = api.nvim_open_win(buf, true, win_opts)

	-- Set buffer options
	api.nvim_buf_set_option(buf, "buftype", "nofile")
	api.nvim_buf_set_option(buf, "bufhidden", "wipe")
	api.nvim_buf_set_option(buf, "swapfile", false)
	api.nvim_buf_set_option(buf, "modifiable", true)

	-- Set window options
	api.nvim_win_set_option(win, "wrap", true)
	api.nvim_win_set_option(win, "cursorline", true)

	-- Close window on q or <Esc>
	api.nvim_buf_set_keymap(buf, "n", "q", "", {
		callback = function()
			api.nvim_win_close(win, true)
		end,
		noremap = true,
		silent = true,
	})
	api.nvim_buf_set_keymap(buf, "n", "<Esc>", "", {
		callback = function()
			api.nvim_win_close(win, true)
		end,
		noremap = true,
		silent = true,
	})

	return {
		buf = buf,
		win = win,
		append = vim.schedule_wrap(function(text)
			-- Check if buffer still exists
			if not vim.api.nvim_buf_is_valid(buf) then
				return
			end

			local lines = type(text) == "table" and text or { text }

			-- Safely modify buffer
			pcall(function()
				vim.api.nvim_buf_set_option(buf, "modifiable", true)
				vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
				vim.api.nvim_buf_set_option(buf, "modifiable", false)

				-- Auto-scroll if window is still valid
				if vim.api.nvim_win_is_valid(win) then
					vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
				end
			end)
		end),
	}
end

return M
