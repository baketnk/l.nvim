local M = {}

local telescope = require("telescope.builtin")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local buffers = require("lnvim.ui.buffers")
local state = require("lnvim.state")

function M.read_file_contents_into_markdown(file_path)
	if file_path:match("^%s*$") then
		return {} -- Return an empty table for blank lines
	end

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
		return {}
	end
end
function M.read_file_contents(file_path)
	local file, err = io.open(file_path, "r")
	if not file then
		return nil, "Failed to open file: " .. (err or "")
	end

	local content = file:read("*all")
	file:close()
	return content
end

function M.select_files_for_prompt(hidden, no_ignore)
	local existing_paths = state.files
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
				M.add_prompt_files(selected_paths, existing_paths)
			end)
			return true
		end,
		multi = true,
		hidden = hidden,
		no_ignore = no_ignore,
	}
	if hidden then
		opts.find_command = { "rg", "--files", "--hidden", "-g", "!.git" }
	end

	telescope.find_files(opts)
end

function M.add_prompt_files(new_paths, existing_paths)
	if not new_paths or #new_paths == 0 then
		vim.notify("Nothing selected", vim.log.levels.INFO)
		return nil
	end

	local updated_paths = {}
	local path_set = {}

	-- Add existing paths to the set and updated list
	for _, path in ipairs(existing_paths) do
		if not path_set[path] then
			path_set[path] = true
			table.insert(updated_paths, path)
		end
	end

	-- Add new paths if they don't already exist
	local new_count = 0
	for _, path in ipairs(new_paths) do
		if not path_set[path] then
			new_count = new_count + 1
			path_set[path] = true
			table.insert(updated_paths, path)
		end
	end

	state.files = updated_paths
	vim.notify("" .. new_count .. " files added to prompt list", vim.log.levels.INFO)
end

function M.set_prompt_files(selected_paths)
	local existing_paths = state.files
	M.add_prompt_files(selected_paths, existing_paths)
end

function M.get_files_for_prompt(selected_paths)
	selected_paths = selected_paths or state.files
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
			if vim.fn.filereadable(path) then
				table.insert(all_contents, M.read_file_contents_into_markdown(path))
			end
		end
	end
	table.insert(all_contents, "")
	all_contents = M.primitive.flatten(all_contents)
	return all_contents
end

function M.select_files_or_folders()
	if not M.diff_buffer then
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

return M
