local M = {}
if M.is_loaded then
	return M
end
local constants = require("lnvim.constants")
local lcmd = require("lnvim.cmd")
local LLM = require("lnvim.llm")

function M.make_plugKey(name, mode, keys, func, opts)
	local full_name = constants.plugin_name .. name
	vim.keymap.set(mode, "<Plug>" .. full_name .. ";", func, opts)
	if M.keymap_prefix ~= "" then
		vim.keymap.set(mode, M.keymap_prefix .. keys, func, opts)
	end
end

function M.setup(_opts)
	local opts = _opts or {}
	M.is_loaded = true
	M.default_prompt_path = opts.default_prompt_path or os.getenv("HOME") .. "/.local/share/lnvim/"
	M.keymap_prefix = opts.keymap_prefix or "<Leader>;"
	M.mark = "T"

	vim.g.markdown_fenced_languages = {
		"html",
		"css",
		"javascript",
		"ruby",
		"python",
		"lua",
		"c",
	}

	lcmd.setup_filetype_ac()
	M.make_plugKey("YankCodeBlock", "n", "y", lcmd.yank_codeblock, { desc = "Yank code block" })
	M.make_plugKey("SetSystemPrompt", "n", "s", lcmd.set_system_prompt, { desc = "Set system prompt" })
	M.make_plugKey("SetPromptFile", "n", "f", lcmd.select_files_for_prompt, { desc = "Select prompt files" })
	M.make_plugKey("Next", "n", "j", lcmd.next_magic, { desc = "Next code block" })
	M.make_plugKey("Prev", "n", "k", lcmd.previous_magic, { desc = "Previous code block" })
	M.make_plugKey("OpenClose", "n", ";", lcmd.open_close, { desc = "Toggle drawer" })
	M.make_plugKey("Magic", "n", "l", lcmd.chat_with_magic, { desc = "Chat with LLM" })
	M.make_plugKey("CycleProvider", "n", "m", LLM.cycle_provider, { desc = "Cycle LLM provider" })
	M.make_plugKey("ReplaceFile", "n", "r", lcmd.replace_file_with_codeblock, { desc = "Replace file with code" })
	M.make_plugKey("ClearAllBuffers", "n", "dg", function()
		lcmd.clear_buffers("all")
	end, { desc = "Clear all buffers" })
	M.make_plugKey("ClearDiffBuffer", "n", "dd", function()
		lcmd.clear_buffers("d")
	end, { desc = "Clear diff buffer" })
	M.make_plugKey("ClearFilesBuffer", "n", "df", function()
		lcmd.clear_buffers("f")
	end, { desc = "Clear files buffer" })
	M.make_plugKey("ClearWorkBuffer", "n", "dp", function()
		lcmd.clear_buffers("p")
	end, { desc = "Clear work buffer" })
	M.make_plugKey("FocusMain", "n", "i", lcmd.focus_main_window, { desc = "Focus main window" })

	if opts.open_drawer_on_setup then
		M.show_drawer()
	end
end

return M
