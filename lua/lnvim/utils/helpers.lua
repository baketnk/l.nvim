local M = {}

local telescope = require("telescope.builtin")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local buffers = require("lnvim.ui.buffers")

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
		return {}
	end
end

function M.select_files_for_prompt()
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
				M.set_prompt_files(selected_paths)
			end)
			return true
		end,
		multi = true,
	}

	telescope.find_files(opts)
end

function M.set_prompt_files(selected_paths)
	if not selected_paths or #selected_paths == 0 then
		vim.notify("Nothing selected", vim.log.levels.INFO)
		return nil
	end
	M.last_selected_files = selected_paths

	-- Just put file paths in the files_buffer
	vim.api.nvim_buf_set_lines(buffers.files_buffer, 0, -1, false, selected_paths)
end

function M.get_files_for_prompt(selected_paths)
	selected_paths = selected_paths or vim.api.nvim_buf_get_lines(buffers.files_buffer, 0, -1, false)
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
	-- Insert all contents into the current work buffer
	all_contents = M.primitive.flatten(all_contents)
	return all_contents
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

return M
