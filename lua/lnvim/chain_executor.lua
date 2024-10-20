-- File: lua/lnvim/chain_executor.lua

local M = {}
local chains = require("lnvim.chains")
local llm = require("lnvim.llm")
local Job = require("plenary.job")
local telescope = require("telescope.builtin")
local vim = vim

-- Utility function for variable substitution
local function substitute_variables(template, variables)
	for key, value in pairs(variables) do
		template = template:gsub("{{%s*" .. key .. "%s*}}", value)
	end
	return template
end

-- Handler for user input steps
local function handle_user_input(step, state, callback, error_callback)
	vim.ui.input({ prompt = step.prompt }, function(input)
		if input == nil then
			error_callback("User canceled the input.")
			return
		end
		state[step.variable] = input
		callback()
	end)
end

-- Handler for LLM steps
local function handle_llm(step, state, callback, error_callback)
	-- Ensure required variables are present
	for _, var in ipairs(step.variables) do
		if not state[var] then
			error_callback("Missing variable: " .. var)
			return
		end
	end

	-- Substitute variables in the prompt
	local prompt = substitute_variables(step.prompt_template, state)

	-- Call the LLM
	llm.call_model(step.name, prompt, function(response)
		if not response then
			error_callback("LLM call failed.")
			return
		end
		state[step.output_variable] = response
		callback()
	end, function(err)
		error_callback("LLM Error: " .. err)
	end)
end

-- Handler for user confirmation steps
local function handle_user_confirmation(step, state, callback, error_callback)
	vim.ui.input({ prompt = step.message .. " (yes/no): " }, function(input)
		if input == nil then
			error_callback("User canceled the confirmation.")
			return
		end
		local approval = input:lower() == "yes" or input:lower() == "y"
		state[step.variable] = approval
		callback()
	end)
end

-- Handler for bash command steps
local function handle_bash(step, state, callback, error_callback)
	-- Check condition if present
	if step.condition then
		local condition = step.condition:gsub("{{%s*(%w+)%s*}}", function(var)
			return tostring(state[var])
		end)
		-- Simple evaluation (be cautious with eval in real scenarios)
		local func, err = load("return " .. condition)
		if not func then
			error_callback("Condition parsing error: " .. err)
			return
		end
		local success, result = pcall(func)
		if not success then
			error_callback("Condition evaluation error: " .. result)
			return
		end
		if not result then
			callback() -- Skip this step
			return
		end
	end

	-- Substitute variables in the command
	local command = substitute_variables(step.command_template, state)

	-- Execute the bash command
	Job:new({
		command = "/bin/bash",
		args = { "-c", command },
		on_exit = function(j, return_val)
			if return_val ~= 0 then
				error_callback("Bash command failed with exit code: " .. return_val)
				return
			end
			callback()
		end,
		on_stderr = function(_, stderr)
			vim.schedule(function()
				vim.notify("Bash Error: " .. stderr, vim.log.levels.ERROR)
			end)
		end,
	}):start()
end

-- Handler for branching steps
local function handle_branch(step, state, callback, error_callback)
	local condition = step.condition:gsub("{{%s*(%w+)%s*}}", function(var)
		return tostring(state[var])
	end)
	-- Simple evaluation (be cautious with eval in real scenarios)
	local func, err = load("return " .. condition)
	if not func then
		error_callback("Branch condition parsing error: " .. err)
		return
	end
	local success, result = pcall(func)
	if not success then
		error_callback("Branch condition evaluation error: " .. result)
		return
	end

	local steps_to_execute = result and step.steps_if_true or step.steps_if_false
	if not steps_to_execute then
		error_callback("Branch has no steps to execute.")
		return
	end

	-- Execute the branch steps sequentially
	M.execute_steps(steps_to_execute, state, callback, error_callback)
end

-- Mapping of step types to their handlers
local step_handlers = {
	user_input = handle_user_input,
	llm = handle_llm,
	user_confirmation = handle_user_confirmation,
	bash = handle_bash,
	branch = handle_branch,
}

-- Recursive function to execute a list of steps
function M.execute_steps(steps, state, callback, error_callback)
	local index = 1

	local function next_step()
		if index > #steps then
			callback()
			return
		end

		local step = steps[index]
		index = index + 1

		local handler = step_handlers[step.type]
		if not handler then
			error_callback("Unknown step type: " .. step.type)
			return
		end

		handler(step, state, next_step, error_callback)
	end

	next_step()
end

-- Function to start executing a chain by name
function M.execute_chain(chain_name, callback, error_callback)
	local chain = chains.get_chain(chain_name)
	if not chain then
		error_callback("Chain not found: " .. chain_name)
		return
	end

	local state = {}
	M.execute_steps(chain.steps, state, function()
		callback(state)
	end, error_callback)
end

return M
