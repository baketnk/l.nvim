local M = {}
if M.is_loaded then
	return M
end
local constants = require("lnvim.constants")
local lcmd = require("lnvim.cmd")
local buffers = require("lnvim.ui.buffers")
-- local LLM = require("lnvim.llm")

function M.debug_current_model()
	vim.print(M.current_model)
end

function M.get_project_root()
	local cwd = vim.fn.getcwd()
	local git_dir = vim.fn.finddir(".git", cwd .. ";")
	if git_dir ~= "" then
		return vim.fn.fnamemodify(git_dir, ":h")
	else
		return cwd
	end
end

function M.make_plugKey(name, mode, keys, func, opts)
	local full_name = constants.plugin_name .. name
	vim.keymap.set(mode, "<Plug>" .. full_name .. ";", func, opts)
	if M.keymap_prefix ~= "" then
		vim.keymap.set(mode, M.keymap_prefix .. keys, func, opts)
	end
end

local function validate_model(model)
	local required_fields = { "model_id", "model_type", "api_url", "api_key" }
	for _, field in ipairs(required_fields) do
		if not model[field] then
			if field == "api_key" and not model["api_url"].match("localhost") then
				error("Model configuration missing required field: " .. field)
			end
		end
	end
	if type(model.use_toolcalling) ~= "boolean" then
		model.use_toolcalling = false
	end
	return model
end

M.default_models = {
	{
		model_id = "claude-3-5-sonnet-20240620",
		model_type = "anthropic",
		api_url = "https://api.anthropic.com/v1/messages",
		api_key = "ANTHROPIC_API_KEY",
		use_toolcalling = false,
	},
	{
		model_id = "claude-3-opus-20240229",
		model_type = "anthropic",
		api_url = "https://api.anthropic.com/v1/messages",
		api_key = "ANTHROPIC_API_KEY",
		use_toolcalling = false,
	},
	{
		model_id = "hermes-3-llama-3.1-405b-fp8",
		model_type = "openaicompat",
		api_url = "https://api.lambdalabs.com/v1/chat/completions",
		api_key = "LAMBDA_API_KEY",
		use_toolcalling = false,
	},
	{
		model_id = "hermes3",
		model_type = "openaicompat",
		api_url = "http://localhost:11434/v1/chat/completions",
		api_key = "",
		use_toolcalling = false,
	},
	{
		model_id = "o1-mini",
		model_type = "openaicompat",
		api_url = "https://openrouter.ai/api/v1/chat/completions",
		api_key = "OPENROUTER_API_KEY",
		use_toolcalling = false,
	},
	{
		model_id = "o1-preview",
		model_type = "openaicompat",
		api_url = "https://openrouter.ai/api/v1/chat/completions",
		api_key = "OPENROUTER_API_KEY",
		use_toolcalling = false,
	},
	{
		model_id = "gpt-4o-mini",
		model_type = "openaicompat",
		api_url = "https://openrouter.ai/api/v1/chat/completions",
		api_key = "OPENROUTER_API_KEY",
		use_toolcalling = false,
	},
	{
		model_id = "x-ai/grok-2",
		model_type = "openaicompat",
		api_url = "https://openrouter.ai/api/v1/chat/completions",
		api_key = "OPENROUTER_API_KEY",
		use_toolcalling = false,
	},
}

function M.setup(_opts)
	local opts = _opts or {}
	M.is_loaded = true

	M.models = {}
	for _, model in ipairs(opts.models or M.default_models) do
		table.insert(M.models, validate_model(model))
	end
	-- Add these new tables to the M table in cfg.lua

	M.autocomplete = opts.autocomplete or {
		max_tokens = 300,
		temperature = 0.5,
	}

	M.autocomplete_model = opts.autocomplete_model
		or {
			model_id = "deepseek-coder-v2:16b",
			model_type = "openai",
			api_url = "http://localhost:11434/v1/completions",
			-- api_key = "",
		}

	M.current_model = M.models[1]
	M.max_prompt_length = opts.max_prompt_length or 16000

	M.default_prompt_path = opts.default_prompt_path or os.getenv("HOME") .. "/.local/share/lnvim/"
	M.project_root = M.get_project_root()
	M.project_lnvim_dir = M.project_root .. "/.lnvim"
	if vim.fn.isdirectory(M.project_lnvim_dir) == 0 then
		vim.fn.mkdir(M.project_lnvim_dir, "p")
	end
	-- Copy the preamble file to the .lnvim folder
	local global_preamble_path = M.default_prompt_path .. "/preamble.txt"
	local project_preamble_path = M.project_lnvim_dir .. "/preamble.txt"
	if vim.fn.filereadable(global_preamble_path) == 1 and vim.fn.filereadable(project_preamble_path) == 0 then
		vim.fn.system("cp " .. global_preamble_path .. " " .. project_preamble_path)
	end

	M.llm_log_path = M.project_lnvim_dir .. "/logs"

	-- Check for .gitignore file and add .lnvim directory to it
	local gitignore_path = M.project_root .. "/.gitignore"
	if vim.fn.filereadable(gitignore_path) == 1 then
		local gitignore_content = vim.fn.readfile(gitignore_path)
		local lnvim_entry = ".lnvim/"
		if not vim.tbl_contains(gitignore_content, lnvim_entry) then
			table.insert(gitignore_content, lnvim_entry)
			vim.fn.writefile(gitignore_content, gitignore_path)
		end
	end

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
	if opts.llm_log_path ~= nil then
		vim.api.nvim_create_autocmd({ "BufUnload", "VimLeavePre" }, {
			pattern = "*",
			callback = function(ev)
				if ev.buf == buffers.diff_buffer then
					require("lnvim.cmd").clear_buffers("diff")
				end
			end,
		})
	end
	M.make_plugKey("YankCodeBlock", "n", "y", lcmd.yank_codeblock, { desc = "Yank code block" })
	M.make_plugKey("SetSystemPrompt", "n", "s", lcmd.set_system_prompt, { desc = "Set system prompt" })
	M.make_plugKey("SetPromptFile", "n", "f", lcmd.select_files_for_prompt, { desc = "Select prompt files" })
	M.make_plugKey(
		"EnumerateProjectFiles",
		"n",
		"F",
		lcmd.enumerate_project_files,
		{ desc = "Enumerate project files" }
	)
	M.make_plugKey("LspIntrospect", "n", "/", lcmd.lsp_introspect, { desc = "LSP Introspection" })
	M.make_plugKey("Next", "n", "j", lcmd.next_magic, { desc = "Next code block" })
	M.make_plugKey("Prev", "n", "k", lcmd.previous_magic, { desc = "Previous code block" })
	M.make_plugKey("OpenClose", "n", ";", lcmd.open_close, { desc = "Toggle drawer" })
	M.make_plugKey("Magic", "n", "l", lcmd.chat_with_magic, { desc = "Chat with LLM" })
	M.make_plugKey("ReplaceFile", "n", "r", lcmd.replace_file_with_codeblock, { desc = "Replace file with code" })
	M.make_plugKey("SelectModel", "n", "m", lcmd.select_model, { desc = "Select LLM model" })
	M.make_plugKey("ClearAllBuffers", "n", "dg", function()
		lcmd.clear_buffers("all")
	end, { desc = "Clear all buffers" })
	M.make_plugKey("ClearDiffBuffer", "n", "dd", function()
		lcmd.clear_buffers("d")
	end, { desc = "Clear diff buffer" })
	M.make_plugKey("ClearFilesBuffer", "n", "df", function()
		lcmd.clear_buffers("f")
	end, { desc = "Clear files buffer" })
	M.make_plugKey("FocusMain", "n", "i", lcmd.focus_main_window, { desc = "Focus main window" })
	M.make_plugKey("ToggleToolUsage", "n", "t", require("lnvim.toolcall").tools_toggle, { desc = "Toggle tool usage" })
	M.make_plugKey(
		"ShellToPrompt",
		"n",
		"p",
		lcmd.shell_to_prompt,
		{ desc = "Run shell command and add output to prompt" }
	)
	M.make_plugKey("TriggerAutocomplete", "n", "c", function()
		vim.schedule(lcmd.trigger_autocomplete)
	end, { desc = "Trigger autocompletion" })
	M.make_plugKey("ApplyDiff", "n", "a", lcmd.apply_diff_to_buffer, { desc = "Apply diff to buffer" })
	M.make_plugKey(
		"ShellToPrompt",
		"n",
		"p",
		lcmd.shell_to_prompt,
		{ desc = "Run shell command and add output to prompt" }
	)
	M.make_plugKey("GenerateReadme", "n", "R", lcmd.generate_readme, { desc = "Generate README.md" })
	if opts.open_drawer_on_setup then
		M.show_drawer()
	end

	require("lnvim.chains.chains")
end

return M
