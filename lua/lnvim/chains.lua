-- File: lua/lnvim/chains.lua

local M = {}
local telescope = require("telescope.builtin")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local user_interactions = require("lnvim.user_interactions")

-- Define the chain configurations
M.chains = {
	-- Example: Default Chain
	default_chain = {
		name = "Default Workflow",
		description = "A basic chain to guide coding tasks.",
		steps = {
			{
				id = "user_input_task",
				type = "user_input",
				prompt = "Enter your coding task:",
				variable = "coding_task",
			},
			{
				id = "llm_design",
				type = "llm",
				prompt_template = [[
          You are an expert system architect. Given the following coding task, design the system architecture and generate a list of concrete coding tasks.

          Task: {{coding_task}}
        ]],
				variables = { "coding_task" },
				output_variable = "design_tasks",
			},
			{
				id = "llm_code_generation",
				type = "llm",
				prompt_template = [[
          You are an advanced code generator. Given the list of design tasks and the context documents, generate the necessary code.

          Design Tasks: {{design_tasks}}
          Context Documents: {{context_documents}}
        ]],
				variables = { "design_tasks", "context_documents" },
				output_variable = "generated_code",
			},
			{
				id = "llm_diff_generation",
				type = "llm",
				prompt_template = [[
          Generate a unified diff for the following code changes based on the context documents.

          Context Documents: {{context_documents}}
          Generated Code: {{generated_code}}
        ]],
				variables = { "context_documents", "generated_code" },
				output_variable = "unified_diff",
			},
			{
				id = "user_approval",
				type = "user_confirmation",
				message = "Do you approve the generated diff?",
				variable = "approval",
			},
			{
				id = "branch_based_on_approval",
				type = "branch",
				condition = "approval == true",
				steps_if_true = {
					{
						id = "bash_apply_diff",
						type = "bash",
						command_template = "patch -p1 <<EOF\n{{unified_diff}}\nEOF",
					},
				},
				steps_if_false = {
					{
						id = "llm_feedback",
						type = "llm",
						prompt_template = [[
              You are an assistant that refines code diffs based on user feedback.

              Feedback: {{user_feedback}}
            ]],
						variables = { "user_feedback" },
						output_variable = "refined_diff",
					},
					{
						id = "llm_regenerate_code",
						type = "llm",
						prompt_template = [[
              Using the refined diff, regenerate the necessary code.

              Refined Diff: {{refined_diff}}
              Context Documents: {{context_documents}}
            ]],
						variables = { "refined_diff", "context_documents" },
						output_variable = "regenerated_code",
					},
				},
			},
		},
	},
}

-- Function to retrieve a chain by name
function M.get_chain(chain_name)
	return M.chains[chain_name]
end

-- Function to list and select a chain
function M.select_and_execute_chain()
	local chain_executor = require("lnvim.chain_executor")
	local chain_names = {}
	for key, chain in pairs(M.chains) do
		table.insert(chain_names, { key = key, name = chain.name, description = chain.description })
	end

	telescope.pickers
		.new({}, {
			prompt_title = "Select a Chain to Execute",
			finder = require("telescope.finders").new_table({
				results = chain_names,
				entry_maker = function(entry)
					return {
						value = entry.key,
						display = entry.name .. " - " .. entry.description,
						ordinal = entry.name,
					}
				end,
			}),
			sorter = require("telescope.config").values.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection then
						chain_executor.execute_chain(selection.value, function(state)
							vim.notify("Chain '" .. selection.value .. "' executed successfully.", vim.log.levels.INFO)
						end, function(err)
							vim.notify("Error executing chain: " .. err, vim.log.levels.ERROR)
						end)
					else
						vim.notify("No chain selected.", vim.log.levels.WARN)
					end
				end)
				return true
			end,
		})
		:find()
end

function M.edit_chain_config()
	local config_path = vim.fn.stdpath("config") .. "/lua/lnvim/chains.lua"
	vim.cmd("edit " .. config_path)
end

-- Function to reload the chain configurations
function M.reload_chains()
	package.loaded["lnvim.chains"] = nil
	chains = require("lnvim.chains")
	vim.notify("Chain configurations reloaded.", vim.log.levels.INFO)
end

-- Setup commands
local function setup_commands()
	vim.api.nvim_create_user_command("LChainExecute", M.select_and_execute_chain, {})
	vim.api.nvim_create_user_command("LChainEdit", M.edit_chain_config, {})
	vim.api.nvim_create_user_command("LChainReload", M.reload_chains, {})
end

setup_commands()

return M
