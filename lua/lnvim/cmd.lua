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
