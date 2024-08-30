local M = {}
local layout = require("lnvim.ui.layout")
local editor = require("lnvim.ui.editor")
local buffers = require("lnvim.ui.buffers")
local constants = require("lnvim.constants")
local helpers = require("lnvim.utils.helpers")
local LLM = require("lnvim.llm")

function M.setup_filetype_ac()
	local group = vim.api.nvim_create_augroup("LCodeBlocks", { clear = true })

	-- Set up autocmd for our custom filetype
	vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI" }, {
		group = group,
		pattern = "*." .. constants.filetype_ext,
		callback = function(ev)
			editor.mark_codeblocks(ev.buf)
			--M.editor.highlight_extmarks(ev.buf)
			--M.editor.print_extmarks(ev.buf)
		end,
	})
end

function M.select_files_for_prompt()
	return helpers.select_files_for_prompt()
end

function M.yank_codeblock()
	return editor.yank_codeblock()
end

function M.paste_codeblock(buf)
	local lines = editor.get_current_codeblock_contents(buf)
	editor.paste_to_mark(M.cfg.mark, lines)
end

function M.chat_with_magic()
	return LLM.chat_with_buffer(LLM.system_prompt)
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
	LLM.system_prompt = sp
end

function M.next_magic()
	M.editor.goto_next_codeblock()
end

function M.previous_magic()
	M.editor.goto_prev_codeblock()
end

function M.open_close()
	local l = layout.get_layout()
	if l and vim.api.nvim_win_is_valid(l.work) then
		layout.close_layout()
	else
		layout.show_drawer()
	end
end

function M.replace_file_with_codeblock()
	return editor.replace_file_with_codeblock()
end

function M.clear_buffers(which)
	local buffers_to_clear = {}

	if which == "all" or which == "d" then
		table.insert(buffers_to_clear, buffers.diff_buffer)
	end
	if which == "all" or which == "f" then
		table.insert(buffers_to_clear, buffers.files_buffer)
	end
	if which == "all" or which == "p" then
		table.insert(buffers_to_clear, buffers.work_buffer)
	end

	for _, buf in ipairs(buffers_to_clear) do
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
	end

	local message
	if which == "all" then
		message = "All buffers cleared"
	elseif which == "d" then
		message = "Diff buffer cleared"
	elseif which == "f" then
		message = "Files buffer cleared"
	elseif which == "p" then
		message = "Work buffer cleared"
	else
		message = "No buffers cleared"
	end
	vim.notify(message, vim.log.levels.INFO)
end

function M.focus_main_window()
	local l = layout.get_layout()
	if l and vim.api.nvim_win_is_valid(l.main) then
		vim.api.nvim_set_current_win(l.main)
	else
		vim.notify("Main window not found or invalid", vim.log.levels.WARN)
	end
end

function M.decide_with_magic()
	if vim.api.nvim_get_current_buf() == buffers.work_buffer then
		-- if cursor is in a CodeBlock highlight, paste the highlight to the edit point
		return LLM.chat_with_buffer(LLM.system_prompt)
	end

	-- M.save_edit_point()
	if layout.layout then
		layout.focus_drawer()
	else
		layout.show_drawer()
	end
end
return M
