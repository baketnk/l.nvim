local M = {}
local layout = require("lnvim.ui.layout")
local editor = require("lnvim.ui.editor")
local buffers = require("lnvim.ui.buffers")
local constants = require("lnvim.constants")
local helpers = require("lnvim.utils.helpers")
local LLM = require("lnvim.llm")
local Job = require("plenary.job")
local diff_utils = require("lnvim.utils.diff")
local LazyLoad = require("lnvim.utils.lazyload")
local LSP = require("lnvim.lsp")
local telescope = require("telescope")
local telescope_builtin = require("telescope.builtin")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local modal = require("lnvim.ui.modal")
local state = require("lnvim.state")

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

function M.save_diff_buffer_contents()
	if not state.llm_log_path then
		return -- Skip saving if log path is not set
	end

	local diff_contents = vim.api.nvim_buf_get_lines(buffers.diff_buffer, 0, -1, false)
	if #diff_contents == 0 then
		return -- Skip saving if buffer is empty
	end

	local timestamp = os.date("!%Y-%m-%dT%H-%M-%S") -- ISO 8601 format
	local filename = string.format("%s/diff_%s.%s", state.llm_log_path, timestamp, constants.filetype_ext)

	-- Ensure the target directory exists
	local dir = vim.fn.fnamemodify(filename, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end

	local file = io.open(filename, "w")
	if file then
		file:write(table.concat(diff_contents, "\n"))
		file:close()
		vim.notify("Diff buffer contents saved to " .. filename, vim.log.levels.INFO)
	else
		vim.notify("Failed to save diff buffer contents to " .. filename, vim.log.levels.ERROR)
	end
end

function M.select_model()
	local opts = {}
	local models = state.models
	local model_names = {}

	for i, model in ipairs(models) do
		table.insert(model_names, string.format("%d: %s (%s)", i, model.model_id, model.api_url))
	end

	local params = {
		prompt_title = "Select Model",
		finder = finders.new_table({
			results = model_names,
		}),
		sorter = conf.generic_sorter(opts),
		attach_mappings = function(prompt_bufnr, _)
			actions.select_default:replace(function()
				actions.close(prompt_bufnr)
				local selection = action_state.get_selected_entry()
				if selection then
					local index = tonumber(selection[1]:match("^(%d+):"))
					state.current_model = models[index]
					vim.notify("Selected model: " .. state.current_model.model_id, vim.log.levels.INFO)
				end
			end)
			return true
		end,
	}

	local picker = pickers.new(opts, params)
	picker:find()
end

function M.apply_diff_to_buffer()
	vim.notify("Entering apply_diff_to_buffer function", vim.log.levels.INFO)

	-- Check if we're in the diff buffer
	if vim.api.nvim_get_current_buf() ~= buffers.diff_buffer then
		vim.notify("Not in diff buffer. Current buffer: " .. vim.api.nvim_get_current_buf(), vim.log.levels.WARN)
		return
	end

	-- Get the current highlighted codeblock
	local lines = editor.get_current_codeblock_contents(buffers.diff_buffer)
	if #lines == 0 then
		vim.notify("No codeblock selected or empty codeblock", vim.log.levels.WARN)
		return
	end

	-- Create a temporary file for the diff
	local temp_file = vim.fn.tempname()
	vim.fn.writefile(lines, temp_file)

	-- Use git apply to apply the diff
	local result = vim.fn.system("git apply --cached " .. vim.fn.shellescape(temp_file))

	if vim.v.shell_error ~= 0 then
		vim.notify("Error applying diff: " .. result, vim.log.levels.ERROR)
		return
	end

	-- Get the list of changed files
	local changed_files = vim.fn.systemlist("git diff --cached --name-only")

	-- Apply changes to buffers
	for _, file in ipairs(changed_files) do
		local buf = vim.fn.bufnr(file, true)
		if buf ~= -1 then
			-- Read the updated content from git index
			local updated_content = vim.fn.systemlist("git show :" .. vim.fn.shellescape(file))

			-- Update the buffer content
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, updated_content)

			vim.notify("Applied changes to " .. file, vim.log.levels.INFO)
		else
			vim.notify("Buffer not found for " .. file, vim.log.levels.WARN)
		end
	end

	-- Clean up: unstage the changes from git index
	vim.fn.system("git reset")

	-- Remove the temporary file
	vim.fn.delete(temp_file)

	vim.notify("Diff applied successfully", vim.log.levels.INFO)
end

function M.shell_to_prompt()
	-- Prompt for the shell command
	local command = vim.fn.input("Enter shell command: ")

	if command == "" then
		vim.notify("No command entered", vim.log.levels.WARN)
		return
	end

	-- Run the command using Plenary Job
	Job:new({
		command = "bash",
		args = { "-c", command },
		on_exit = function(j, return_val)
			local output = j:result()
			local stderr = j:stderr_result()

			-- Combine stdout and stderr
			local combined_output = vim.tbl_flatten({ output, stderr })

			-- Create the markdown codeblock
			local codeblock = { "```bash", "$ " .. command }
			vim.list_extend(codeblock, combined_output)
			table.insert(codeblock, "```")

			-- Insert the codeblock into the work buffer
			vim.schedule(function()
				local start_line = vim.api.nvim_buf_line_count(buffers.diff_buffer)
				vim.api.nvim_buf_set_lines(buffers.diff_buffer, start_line, -1, false, codeblock)
				vim.notify("Command output added to diff buffer", vim.log.levels.INFO)
			end)
		end,
	}):start()
end

function M.prompt_macro()
	local telescope = require("telescope.builtin")
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	telescope.find_files({
		prompt_title = "Select Prompt Macro File",
		attach_mappings = function(prompt_bufnr, map)
			actions.select_default:replace(function()
				actions.close(prompt_bufnr)
				local selection = action_state.get_selected_entry()
				if selection then
					-- Execute the selected macro file
					M.execute_prompt_macro(selection.path)
				end
			end)
			return true
		end,
	})
end

function M.execute_prompt_macro(file_path)
	local content = helpers.read_file_contents(file_path)
	if not content then
		vim.notify("Failed to read file: " .. file_path, vim.log.levels.ERROR)
		return
	end

	-- Look for bash code blocks and execute them
	local lines = vim.split(content, "\n")
	local in_bash_block = false
	local bash_command = ""
	local output = {}

	for _, line in ipairs(lines) do
		if line:match("^```bash") then
			in_bash_block = true
			table.insert(output, line)
		elseif line:match("^```$") and in_bash_block then
			in_bash_block = false
			-- Execute the bash command
			local result = vim.fn.system(bash_command)
			table.insert(output, "$ " .. bash_command:gsub("\n", " "))
			for _, res_line in ipairs(vim.split(result, "\n")) do
				if res_line ~= "" then
					table.insert(output, res_line)
				end
			end
			table.insert(output, "```")
			bash_command = ""
		elseif in_bash_block then
			bash_command = bash_command .. line .. "\n"
		else
			table.insert(output, line)
		end
	end

	-- Add the processed content to the work buffer
	vim.api.nvim_buf_set_lines(buffers.diff_buffer, -1, -1, false, output)
	vim.notify("Macro content added to diff buffer", vim.log.levels.INFO)
end

function M.select_files_for_prompt()
	local function on_select(selected_files)
		state.update_files(selected_files)
		layout.update_summary()
	end

	return helpers.select_files_for_prompt(false, false, on_select)
end

function M.yank_codeblock()
	return editor.yank_codeblock()
end

function M.paste_codeblock(buf)
	local lines = editor.get_current_codeblock_contents(buf)
	editor.paste_to_mark(state.paste_mark, lines)
end

function M.chat_with_magic()
	return LLM.chat_with_buffer()
end

function M.chat_with_magic_and_diff()
	return LLM.chat_with_buffer_and_diff()
end

-- Enhanced stream_selected_text function
M.stream_selected_text = vim.schedule_wrap(function()
	-- First, ensure the required command exists
	local _, err = pcall(require("lnvim.wtf").visual_quick_ask)
	if err then
		vim.print(vim.inspect(err))
	end
end)

function M.set_system_prompt()
	modal.modal_input({ prompt = "Edit System Prompt:", default = state.system_prompt }, function(input)
		if type(input) ~= "table" then
			input = { input }
		end
		state.system_prompt = input
		vim.fn.writefile(input, state.project_system_prompt_filepath)
	end)
end

function M.selection_to_prompt()
	local _, start_line, _, _ = unpack(vim.fn.getpos("'<"))
	local _, end_line, _, _ = unpack(vim.fn.getpos("'>"))
	local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

	-- Get the current contents of the diff buffer
	local diff_buffer_lines = vim.api.nvim_buf_get_lines(buffers.diff_buffer, 0, -1, false)

	-- Append the selected lines to the diff buffer, adding a newline if necessary
	if #diff_buffer_lines > 0 and diff_buffer_lines[#diff_buffer_lines] ~= "" then
		table.insert(diff_buffer_lines, "")
	end
	vim.list_extend(diff_buffer_lines, lines)

	-- Update the diff buffer with the new contents
	vim.api.nvim_buf_set_lines(buffers.diff_buffer, 0, -1, false, diff_buffer_lines)
end

function M.selection_to_prompt_wrapped()
	local _, start_line, _, _ = vim.fn.getpos("'<")
	local _, end_line, _, _ = vim.fn.getpos("'>")
	local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

	-- Get the current contents of the diff buffer
	local diff_buffer_lines = vim.api.nvim_buf_get_lines(buffers.diff_buffer, 0, -1, false)

	-- Append the selected lines to the diff buffer, wrapping them in a markdown codeblock
	if #diff_buffer_lines > 0 and diff_buffer_lines[#diff_buffer_lines] ~= "" then
		table.insert(diff_buffer_lines, "")
	end
	table.insert(diff_buffer_lines, "```")
	vim.list_extend(diff_buffer_lines, lines)
	table.insert(diff_buffer_lines, "```")

	-- Update the diff buffer with the new contents
	vim.api.nvim_buf_set_lines(buffers.diff_buffer, 0, -1, false, diff_buffer_lines)
end

function M.next_magic()
	editor.goto_next_codeblock()
end

function M.previous_magic()
	editor.goto_prev_codeblock()
end

function M.open_close()
	local l = layout.get_layout()
	if l and vim.api.nvim_win_is_valid(l.diff) then
		layout.close_layout()
	else
		layout.show_drawer()
	end
end

function M.trigger_autocomplete()
	require("lnvim.autocomplete").trigger_autocomplete()
end

-- DO NOT REMOVE THIS COMMENT, IMPORTANT DEFINITION OF INTERNAL SYNTAX
-- LSP file list syntax: @lsp:<type>:<name>:<file>:<line>:<column>
function M.lsp_introspect()
	local l = layout.get_layout()
	if not l or not vim.api.nvim_win_is_valid(l.main) then
		vim.notify("Main window not found or invalid", vim.log.levels.WARN)
		return
	end

	telescope_builtin.lsp_dynamic_workspace_symbols({
		attach_mappings = function(prompt_bufnr, map)
			actions.select_default:replace(function()
				actions.close(prompt_bufnr)
				local selections = action_state.get_selected_entries()
				if selections then
					for _, selection in ipairs(selections) do
						LSP.handle_lsp_selection(selection)
					end
				end
			end)
			return true
		end,
		multi = true, -- Enable multi-select
	})
end

function M.replace_file_with_codeblock()
	return editor.replace_file_with_codeblock()
end

function M.clear_buffers(which)
	local buffers_to_clear = {}

	if which == "all" or which == "d" then
		table.insert(buffers_to_clear, buffers.diff_buffer)
		M.save_diff_buffer_contents()
	end
	if which == "all" or which == "f" then
		state.files = {}
	end

	for _, buf in ipairs(buffers_to_clear) do
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
	end

	local message
	if which == "all" then
		message = "All buffers cleared"
		require("lnvim.llm").print_user_delimiter()
	elseif which == "d" then
		message = "Diff buffer cleared"
		require("lnvim.llm").print_user_delimiter()
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
	if vim.api.nvim_get_current_buf() == buffers.diff_buffer then
		-- if cursor is in a CodeBlock highlight, paste the highlight to the edit point
		return LLM.chat_with_buffer()
	end

	-- M.save_edit_point()
	if layout.layout then
		layout.focus_drawer()
	else
		layout.show_drawer()
	end
end

function M.enumerate_project_files()
	local project_file_list = "@project-file-list"
	local files = state.files

	-- Check if the project file list is already in the state
	-- tbl_contains returns true
	local has_list_special = vim.tbl_contains(files, project_file_list)

	if has_list_special then
		-- If it's present, remove it
	else
		-- If it's not present, add it
		table.insert(files, project_file_list)
		vim.notify("Project file list placeholder added to the files buffer", vim.log.levels.INFO)
	end

	-- Update the state and refresh the summary
	state.files = files
	layout.update_summary()
end

function M.generate_readme()
	local lcfg = require("lnvim.cfg")
	local cfg = lcfg
	local keymaps = {}
	-- Iterate through the M.make_plugKey calls in cfg.lua
	for _, v in pairs(lcfg) do
		if type(v) == "function" then
			local info = debug.getinfo(v)
			if info.nparams == 5 then -- M.make_plugKey takes 5 parameters
				local src = info.source:sub(2) -- Remove the '@' at the beginning
				local lines = vim.fn.readfile(src)
				for _, line in ipairs(lines) do
					local name, mode, keys, func, opts =
						line:match('M%.make_plugKey%("([^"]+)", "([^"]+)", "([^"]+)", ([^,]+), ({.+})%)')
					if name and keys and opts then
						local desc = opts:match('desc = "([^"]+)"')
						if desc then
							table.insert(keymaps, {
								key = cfg.keymap_prefix .. keys,
								desc = desc,
							})
						end
					end
				end
			end
		end
	end

	-- Extract configuration variables from cfg.setup()
	local config_vars = {}
	local cfg_setup_func = vim.fn.readfile(debug.getinfo(cfg.setup).source:sub(2))

	for _, line in ipairs(cfg_setup_func) do
		vim.print(line)
		local var, _, default = line:match("M%.([%w_]+)%s*=%s*opts%.([%w_]+)%s*or%s*(.+)$")
		if var then
			table.insert(config_vars, { name = var, default = default })
		end
	end
	vim.print(#config_vars)

	-- Extract model configuration from cfg.default_models
	local model_config = {}
	for _, model in ipairs(cfg.default_models) do
		local model_info = {
			model_id = model.model_id,
			model_type = model.model_type,
			api_url = model.api_url,
			api_key = model.api_key,
			use_toolcalling = model.use_toolcalling,
		}
		table.insert(model_config, model_info)
	end

	local readme_content = [[
# ]] .. constants.display_name .. [[

]] .. constants.display_name .. [[ is a Neovim plugin that integrates large language models (LLMs) into your editing workflow.

N.B.: The plugin interface will change randomly whenever I feel like updating. Lock your commit hash or be prepared for trouble!

## Features

- Interact with LLMs directly from your editor
- Apply AI-generated changes to your code
- Execute shell commands and add their output to the prompt
- Use prompt macros for quick and consistent interactions

## Installation

I use lazy.nvim. It's pretty straightforward if you want defaults, see customization if you want overrides.

```
  {
    "baketnk/l.nvim"
  }
```

## Configuration

You can configure ]] .. constants.display_name .. [[ by passing options to the setup function:

```lua
require('lnvim').setup({
	keymap_prefix = "<Leader>;",
	open_drawer_on_setup = true,
})
```

## Keymappings

]]

	for _, keymap in ipairs(keymaps) do
		readme_content = readme_content .. "- `" .. keymap.key .. "`: " .. keymap.desc .. "\n"
	end

	readme_content = readme_content .. [[

## License

MIT

]]

	-- Write the README.md file
	local readme_path = vim.fn.getcwd() .. "/README.md"
	local file = io.open(readme_path, "w")
	if file then
		file:write(readme_content)
		file:close()
		vim.notify("README.md generated successfully", vim.log.levels.INFO)
	else
		vim.notify("Failed to write README.md", vim.log.levels.ERROR)
	end
end

return M
