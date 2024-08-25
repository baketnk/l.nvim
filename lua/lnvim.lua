local M = {}

-- local telescope = require('telescope')

local LLM = require("lnvim.llm")
M.LLM = LLM
M.primitive = require("lnvim.primitive")
M.editor = require("lnvim.editor")
M.filetype_ext = "lslop"
local plugin_name = "Lnvim"

function M.show_drawer()
	-- ?v=G9WenqyPVJE

	local default_prompt_path = M.opts.default_prompt_path
	if M.work_buffer == nil or not vim.api.nvim_buf_is_valid(M.work_buffer) then
		M.work_buffer = vim.api.nvim_create_buf(false, false)
		vim.api.nvim_set_option_value("filetype", M.filetype_ext, { buf = M.work_buffer })

		vim.api.nvim_buf_set_name(M.work_buffer, default_prompt_path .. os.date("!%Y-%m-%d_%H-%M-%S") .. M.filetype_ext)
	end
	if M.work_window == nil or not vim.api.nvim_win_is_valid(M.work_window) then
		M.work_window = vim.api.nvim_open_win(M.work_buffer, true, {
			split = "right",
			win = -1,
			-- width = 80,
			-- height = 40,
			-- style = "minimal",
			-- border = "single",
		})
	else
		vim.api.nvim_set_current_win(M.work_window)
	end
	vim.api.nvim_set_current_buf(M.work_buffer)
	vim.cmd(":set wrap")
	M.load_prompt_file(M.work_buffer, default_prompt_path .. "default." .. M.filetype_ext)
end

function M.load_prompt_file(buf, prompt_file_path)
	local file, err = io.open(prompt_file_path, "r")
	if file then
		local prompt_lines = {}
		for line in file:lines() do
			prompt_lines[#prompt_lines + 1] = line
		end
		file:close()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, prompt_lines)
	else
		vim.api.nvim_err_writeln("cant open: " .. prompt_file_path)
		vim.api.nvim_err_writeln(err or "err nil")
	end
end

function M.replace_phrase_in_buffer(buf, needle, stick)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local new_lines = {}

	for _, line in ipairs(lines) do
		local new_line = line:gsub(needle, stick)
		table.insert(new_lines, new_line)
	end

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
end

-- function M.

function M.chat_with_buffer_default_system()
	local file = io.open(M.opts.default_prompt_path .. "system.txt")
	local system_prompt = "im a teapot"
	if file then
		system_prompt = file:read("*a")
		file:close()
	end

	vim.cmd("o")
	return LLM.chat_with_buffer(system_prompt)
end

function M.save_edit_point()
	if not M.opts.mark then
		return nil -- assume we just use "'"
	end
	local cursor = vim.api.nvim_win_get_cursor(0)
	-- vim.print(cursor)
	local row, col = unpack(cursor)
	M.shortcut_mark = vim.api.nvim_buf_set_mark(0, M.opts.mark, row, col, {})
end

function M.send_to_edit_point(ask_mark)
	local mark = M.opts.mark or "'"
	if ask_mark then
		mark = vim.fn.input({
			completion = "mark",
		})
	end
	-- if mark ~= "" then

	-- end
	-- get the text of the codeblock under cursor, if any
	-- if text is not falsy, then proceed to insert it at the mark
end

local ns_id = vim.api.nvim_create_namespace("Lnvim")

function M.paste_contents()
	if not M.telescope then
		local file_path = vim.fn.input({
			completion = "file",
		})

		local file, err = io.open(file_path, "r")
		if file then
			local prompt_lines = { "```" .. file_path }
			for line in file:lines() do
				prompt_lines[#prompt_lines + 1] = line
			end
			prompt_lines[#prompt_lines + 1] = "```"
			file:close()
			vim.api.nvim_buf_set_lines(0, -1, -1, false, prompt_lines)
		else
			vim.api.nvim_err_writeln("cant open: " .. file_path)
			vim.api.nvim_err_writeln(err or "err nil")
		end
	else
		M.telescope.builtin.find_files({})
	end
end

function M.paste_codeblock(buf)
	local lines = M.editor.get_current_codeblock_contents(buf)
	M.editor.paste_to_mark(M.opts.mark, lines)
end

function M.chat_with_magic()
	-- M.replace_magic_words()
	M.LLM.chat_with_buffer()
end

function M.set_system_prompt(prompt_text)
	local sp = prompt_text
	if not sp then
		local file_path = vim.fn.input({
			prompt = "system prompt file",
			completion = "file",
		})
		local f, err = io.open(file_path)
		if err then
			vim.notify(err, vim.log.levels.ERROR)
			return nil
		end
		if not f then
			return nil
		end
		sp = f:read("*a")
	end
	M.LLM.system_prompt = sp
end

function M.next_magic()
	M.editor.goto_next_codeblock()
end

function M.previous_magic()
	M.editor.goto_prev_codeblock()
end

function M.decide_with_magic()
	if vim.api.nvim_get_current_buf() == M.work_buffer then
		-- if cursor is in a CodeBlock highlight, paste the highlight to the edit point
		return M.chat_with_magic()
	end

	M.save_edit_point()
	M.show_drawer()
end

local function setup_filetype_ac()
	local group = vim.api.nvim_create_augroup("LCodeBlocks", { clear = true })

	-- Set up autocmd for our custom filetype
	vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI" }, {
		group = group,
		pattern = "*." .. M.filetype_ext,
		callback = function(ev)
			M.editor.mark_codeblocks(ev.buf)
			--M.editor.highlight_extmarks(ev.buf)
			--M.editor.print_extmarks(ev.buf)
		end,
	})
end

local function make_plugKey(name, mode, keys, func, opts)
	vim.keymap.set(mode, "<Plug>" .. plugin_name .. name .. ";", func, opts)
	if M.opts.keymap_prefix ~= "" then
		vim.keymap.set(mode, M.opts.keymap_prefix .. keys, func, opts)
	end
end

-- TODO: fix mode mapping to support multiple
function M.setup(_opts)
	local opts = _opts or {}
	opts.default_prompt_path = opts.default_prompt_path or os.getenv("HOME") .. "/.local/share/lnvim/"
	opts.keymap_prefix = opts.keymap_prefix or "<Leader>;"
	opts.mark = "T"
	opts.use_openai_compat = opts.use_openai_compat or nil
	if opts.use_openai_compat and not opts.api_key_name then
		vim.notify("please pass in setup opts: api_key_name")
	end
	M.opts = opts
	vim.g.lnvim_opts = opts
	vim.g.lnvim_debug = opts.debug
	if opts.debug then
		vim.cmd("nmap <leader>t <Plug>PlenaryTestFile")
	end
	vim.g.markdown_fenced_languages = {
		"html",
		"css",
		"javascript",
		"ruby",
		"python",
		"lua",
		"c",
	}

	setup_filetype_ac()
	make_plugKey(plugin_name .. "SetSystem", "n", "y", M.set_system_prompt, {})
	make_plugKey(plugin_name .. "PasteFile", "n", "f", M.paste_contents, {})
	make_plugKey(plugin_name .. "Next", "n", "j", M.next_magic, {})
	make_plugKey(plugin_name .. "Prev", "n", "k", M.previous_magic, {})
	make_plugKey(plugin_name .. "Magic", "n", ";", M.decide_with_magic, {})
	make_plugKey(plugin_name .. "SendCodeToPlace", "n", "p", M.paste_codeblock, {})
	if opts.open_drawer_on_setup then
		M.show_drawer()
	end
end

return M
