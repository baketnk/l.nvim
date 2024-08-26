local M = {}

-- local telescope = require('telescope')

-- module references
local LLM = require("lnvim.llm")
M.LLM = LLM
M.primitive = require("lnvim.primitive")
M.editor = require("lnvim.editor")

-- ephemeral module variables
M.last_selected_files = {}
M.filetype_ext = "lslop"

local plugin_name = "Lnvim"
local display_name = "l.nvim"

local telescope = require("telescope.builtin")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

--- Display the l.nvim work drawer, creating the window and/or buffer if it's not available
function M.show_drawer()
	-- ?v=G9WenqyPVJE

	local default_prompt_path = M.opts.default_prompt_path
	if M.work_buffer == nil or not vim.api.nvim_buf_is_valid(M.work_buffer) then
		M.work_buffer = vim.api.nvim_create_buf(false, false)
		vim.api.nvim_set_option_value("filetype", M.filetype_ext, { buf = M.work_buffer })

		vim.api.nvim_buf_set_name(
			M.work_buffer,
			default_prompt_path .. os.date("!%Y-%m-%d_%H-%M-%S") .. "." .. M.filetype_ext
		)
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
	--	M.load_prompt_file(M.work_buffer, default_prompt_path .. "default." .. M.filetype_ext)
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

function M.read_file_contents_into_markdown(file_path)
	local file, err = io.open(file_path, "r")
	if file then
		local contents = { "", "```" .. file_path }
		for line in file:lines() do
			table.insert(contents, line)
		end
		table.insert(contents, "```")
		table.insert(contents, "")
		file:close()
		return contents
	else
		vim.api.nvim_err_writeln("Can't open: " .. file_path)
		vim.api.nvim_err_writeln(err or "err nil")
		return {}
	end
end

function M.select_files_for_paste_to_prompt()
	local selected_paths = {}

	local opts = {
		prompt_title = "Select files for prompting",
		attach_mappings = function(prompt_bufnr, map)
			actions.select_default:replace(function()
				local current_picker = action_state.get_current_picker(prompt_bufnr)
				local multi_selections = current_picker:get_multi_selection()
				if #multi_selections > 0 then
					for _, select in ipairs(multi_selections) do
						table.insert(selected_paths, select.path)
					end
				else
					local selection = action_state.get_selected_entry()
					if selection then
						table.insert(selected_paths, selection.path)
					end
				end

				actions.close(prompt_bufnr)
				M.paste_files_to_prompt(selected_paths)
			end)
			return true
		end,
		multi = true,
	}

	telescope.find_files(opts)
end

function M.paste_files_to_prompt(selected_paths)
	if not selected_paths or #selected_paths == 0 then
		vim.notify("nothing selected", vim.log.levels.INFO)
		return nil
	end
	M.last_selected_files = selected_paths

	local all_contents = {}
	for _, path in ipairs(selected_paths) do
		if vim.fn.isdirectory(path) == 1 then
			-- If it's a directory, read all files in it
			local files = vim.fn.globpath(path, "*", false, true)
			for _, file in ipairs(files) do
				if vim.fn.filereadable(file) == 1 then
					table.insert(all_contents, M.read_file_contents_into_markdown(file))
				end
			end
		else
			-- If it's a file, read its contents
			table.insert(all_contents, M.read_file_contents_into_markdown(path))
		end
	end
	table.insert(all_contents, "")
	-- Insert all contents into the current work buffer
	all_contents = M.primitive.flatten(all_contents)
	vim.api.nvim_buf_set_lines(M.work_buffer, -1, -1, false, all_contents)
	vim.api.nvim_win_set_cursor(M.work_window, { #all_contents, 0 })
end

function M.select_files_or_folders()
	if not M.work_buffer then
		M.show_drawer()
	end
	local selected_paths = {}

	local opts = {
		attach_mappings = function(prompt_bufnr, map)
			actions.select_default:replace(function()
				actions.close(prompt_bufnr)
				local selection = action_state.get_selected_entry()
				table.insert(selected_paths, selection.path)
			end)
			return true
		end,
		multi = true,
	}

	telescope.find_files(opts)

	return selected_paths
end

function M.reimport_files()
	-- Clear the work buffer
	vim.api.nvim_buf_set_lines(M.work_buffer, 0, -1, false, {})

	-- Reimport the contents of the last selected files
	M.paste_files_to_prompt(M.last_selected_filess)
	-- Move cursor to the end of the buffer
	local last_line = vim.api.nvim_buf_line_count(M.work_buffer)
	vim.api.nvim_win_set_cursor(M.work_window, { last_line, 0 })
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
		return M.LLM.chat_with_buffer(M.LLM.system_prompt)
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
	vim.keymap.set(mode, "<Plug>" .. name .. ";", func, opts)
	if M.opts.keymap_prefix ~= "" then
		vim.keymap.set(mode, M.opts.keymap_prefix .. keys, func, opts)
	end
end

-- TODO: fix mode mapping to support multiple

--- Set up l.nvim with the options table given.
--- @param _opts table
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
	make_plugKey(plugin_name .. "YankCodeBlock", "n", "y", M.editor.yank_codeblock, {})
	make_plugKey(plugin_name .. "SetSystemPrompt", "n", "s", M.set_system_prompt, {})
	make_plugKey(plugin_name .. "PasteFile", "n", "f", M.select_files_for_paste_to_prompt, {})
	make_plugKey(plugin_name .. "LastPasteFile", "n", "r", M.reimport_files, {})
	make_plugKey(plugin_name .. "Next", "n", "j", M.next_magic, {})
	make_plugKey(plugin_name .. "Prev", "n", "k", M.previous_magic, {})
	make_plugKey(plugin_name .. "Magic", "n", ";", M.decide_with_magic, {})
	-- make_plugKey(plugin_name .. "SendCodeToPlace", "n", "p", M.paste_codeblock, {})
	if opts.open_drawer_on_setup then
		M.show_drawer()
	end
end

return M
