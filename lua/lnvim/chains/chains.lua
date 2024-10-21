-- File: lua/lnvim/chains.lua

local M = {}
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local user_interactions = require("lnvim.user_interactions")

local conf = require("telescope.config").values

local user_config_path = vim.fn.stdpath("config") .. "/lua/lnvim/user_chains.lua"

-- Define the chain configurations
local example_chains = {
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
	local chain_executor = require("lnvim.chains.chain_executor")
	local chain_names = {}
	for key, chain in pairs(M.chains) do
		table.insert(chain_names, { key = key, name = chain.name, description = chain.description })
	end

	local opts = {}
	pickers
		.new(opts, {
			prompt_title = "Select a Chain to Execute",
			finder = finders.new_table({
				results = chain_names,
				entry_maker = function(entry)
					return {
						value = entry.key,
						display = entry.name .. " - " .. entry.description,
						ordinal = entry.name,
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
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

-- Function to load user's chain configurations
local function load_user_chains()
	local f = io.open(user_config_path, "r")
	if f then
		local content = f:read("*all")
		f:close()
		if content and #content > 0 then
			local user_chains = loadstring(content)()
			if user_chains then
				return user_chains
			end
		end
	end
	return nil
end

local function save_example_chain()
	-- Ensure the directory exists
	local dir = vim.fn.fnamemodify(user_config_path, ":h")
	vim.fn.mkdir(dir, "p")
	local f, err = io.open(user_config_path, "w")
	if f then
		f:write("return " .. vim.inspect(example_chains))
		f:close()
		vim.notify("Example chain configuration saved to " .. user_config_path, vim.log.levels.INFO)
		return true
	else
		vim.print(vim.inspect(err))
		vim.notify("Failed to save example chain configuration", vim.log.levels.ERROR)
		return false
	end
end

M.chains = load_user_chains() or {}
if not next(M.chains) then
	if save_example_chain() then
		M.chains = example_chains
	end
end

function M.edit_chain_config()
	if not vim.uv.fs_stat(user_config_path) then
		-- File doesn't exist, create it with example chains
		save_example_chain()
	end
	vim.cmd("edit " .. user_config_path)
end

-- Function to reload the chain configurations
function M.reload_chains()
	M.chains = load_user_chains() or {}
	if not next(M.chains) then
		if save_example_chain() then
			M.chains = example_chains
		end
	end
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
