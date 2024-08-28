local M = {}
if M.is_loaded then
	return M
end
local constants = require("lnvim.constants")
local lcmd = require("lnvim.cmd")
local LLM = require("lnvim.llm")
function M.make_plugKey(name, mode, keys, func, opts)
	vim.keymap.set(mode, "<Plug>" .. name .. ";", func, opts)
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
	M.make_plugKey(constants.plugin_name .. "YankCodeBlock", "n", "y", lcmd.yank_codeblock, {})
	M.make_plugKey(constants.plugin_name .. "SetSystemPrompt", "n", "s", lcmd.set_system_prompt, {})
	M.make_plugKey(constants.plugin_name .. "PasteFile", "n", "f", lcmd.select_files_for_prompt, {})
	M.make_plugKey(constants.plugin_name .. "Next", "n", "j", lcmd.next_magic, {})
	M.make_plugKey(constants.plugin_name .. "Prev", "n", "k", lcmd.previous_magic, {})
	M.make_plugKey(constants.plugin_name .. "OpenClose", "n", ";", lcmd.open_close, {})
	M.make_plugKey(constants.plugin_name .. "Magic", "n", "l", lcmd.chat_with_magic, {})
	M.make_plugKey(constants.plugin_name .. "CycleProvider", "n", "m", LLM.cycle_provider, opts)
	if opts.open_drawer_on_setup then
		M.show_drawer()
	end
end

return M
