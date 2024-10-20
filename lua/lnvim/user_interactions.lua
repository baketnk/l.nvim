-- File: lua/lnvim/user_interactions.lua

local M = {}
local telescope = require("telescope.builtin")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local vim = vim

-- Handler for list selection
function M.select_from_list(prompt_title, items, callback, error_callback)
	telescope.pickers
		.new({}, {
			prompt_title = prompt_title,
			finder = require("telescope.finders").new_table({ results = items }),
			sorter = require("telescope.config").values.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection then
						callback(selection[1])
					else
						error_callback("No selection made.")
					end
				end)
				return true
			end,
		})
		:find()
end

function M.multiple_choice(prompt_title, choices, callback, error_callback)
	telescope.pickers
		.new({}, {
			prompt_title = prompt_title,
			finder = require("telescope.finders").new_table({ results = choices }),
			sorter = require("telescope.config").values.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selections = action_state.get_selected_entry()
					if selections then
						callback(selections[1])
					else
						error_callback("No selection made.")
					end
				end)
				return true
			end,
		})
		:find()
end

-- Handler for approval confirmations
function M.confirm(prompt_message, callback, error_callback)
	vim.ui.input({ prompt = prompt_message .. " (yes/no): " }, function(input)
		if input == nil then
			error_callback("User canceled the confirmation.")
			return
		end
		local approval = input:lower() == "yes" or input:lower() == "y"
		callback(approval)
	end)
end

return M
