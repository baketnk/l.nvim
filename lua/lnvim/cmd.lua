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
local cfg = LazyLoad("lnvim.cfg")

local telescope = require("telescope")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

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
	if not cfg.llm_log_path then
		return -- Skip saving if log path is not set
	end

	local diff_contents = vim.api.nvim_buf_get_lines(buffers.diff_buffer, 0, -1, false)
	if #diff_contents == 0 then
		return -- Skip saving if buffer is empty
	end

	local timestamp = os.date("!%Y-%m-%dT%H-%M-%S") -- ISO 8601 format
	local filename = string.format("%s/diff_%s.%s", cfg.llm_log_path, timestamp, constants.filetype_ext)

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
	local models = cfg.models
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
					cfg.current_model = models[index]
					vim.notify("Selected model: " .. cfg.current_model.model_id, vim.log.levels.INFO)
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

	-- Get the entire diff buffer content
	-- Log the content of the diff buffer
	local diff_content = table.concat(vim.api.nvim_buf_get_lines(buffers.diff_buffer, 0, -1, false), "\n")
	vim.notify("Diff content:\n" .. diff_content, vim.log.levels.INFO)

	-- Split the diff content into separate file diffs
	local file_diffs = {}
	local current_file = nil
	for line in diff_content:gmatch("[^\r\n]+") do
		if line:match("^diff %-%-git") then
			if current_file then
				table.insert(file_diffs, current_file)
			end
			current_file = { header = line, content = {} }
		elseif current_file then
			table.insert(current_file.content, line)
		end
	end
	if current_file then
		table.insert(file_diffs, current_file)
	end

	-- Apply diffs to each file
	for _, file_diff in ipairs(file_diffs) do
		local file_path = file_diff.header:match("b/(.+)$")
		if file_path then
			-- Open or focus the buffer for this file
			local buf = vim.fn.bufnr(file_path, true)
			if buf == -1 then
				buf = vim.fn.bufadd(file_path)
			end
			vim.api.nvim_set_current_buf(buf)

			-- Get the original content of the buffer
			local original_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

			-- Apply the diff
			local new_lines = diff_utils.applyDiff(original_lines, table.concat(file_diff.content, "\n"))

			-- Replace the contents of the buffer
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)

			vim.notify("Diff applied to " .. file_path, vim.log.levels.INFO)
		end
	end
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
				local start_line = vim.api.nvim_buf_line_count(buffers.work_buffer)
				vim.api.nvim_buf_set_lines(buffers.work_buffer, start_line, -1, false, codeblock)
				vim.notify("Command output added to work buffer", vim.log.levels.INFO)
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
	vim.api.nvim_buf_set_lines(buffers.work_buffer, -1, -1, false, output)
	vim.notify("Macro content added to work buffer", vim.log.levels.INFO)
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
	return LLM.chat_with_buffer()
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
	editor.goto_next_codeblock()
end

function M.previous_magic()
	editor.goto_prev_codeblock()
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
		M.save_diff_buffer_contents()
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
		return LLM.chat_with_buffer()
	end

	-- M.save_edit_point()
	if layout.layout then
		layout.focus_drawer()
	else
		layout.show_drawer()
	end
end

function M.generate_readme()
	local lcfg = require("lnvim.cfg")
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

### Configuration Variables



| Variable | Default Value |
|----------|---------------|

]]

	for _, var in ipairs(config_vars) do
		readme_content = readme_content .. "| " .. var.name .. " | " .. var.default .. "|" .. " |\n"
	end

	readme_content = readme_content
		.. [[



### Default Model Configuration



| Model ID | Model Type | API URL | API Key | Use Toolcalling |
|----------|------------|---------|---------|-----------------|

]]

	for _, model in ipairs(model_config) do
		readme_content = readme_content
			.. "| "
			.. model.model_id
			.. " | "
			.. model.model_type
			.. " | "
			.. model.api_url
			.. " | "
			.. model.api_key
			.. " | "
			.. tostring(model.use_toolcalling)
			.. " |\n"
	end

	readme_content = readme_content .. [[



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
