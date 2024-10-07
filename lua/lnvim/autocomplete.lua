-- autocomplete.lua
local M = {}
local Job = require("plenary.job")

local function get_context(lines_before, lines_after)
	local current_line = vim.fn.line(".")
	local start_line = math.max(1, current_line - lines_before)
	local end_line = math.min(vim.fn.line("$"), current_line + lines_after)

	return vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
end

local function generate_autocomplete_args(model, prompt, suffix)
	local cfg = require("lnvim.cfg")
	local args = {
		"-N",
		"-s",
		"-X",
		"POST",
		"-H",
		"Content-Type: application/json",
	}

	if model.api_key then
		table.insert(args, "-H")
		table.insert(args, "Authorization: Bearer " .. os.getenv(model.api_key))
	end

	local data = {
		model = model.model_id,
		prompt = prompt,
		suffix = suffix,
		max_tokens = cfg.autocomplete.max_tokens,
		temperature = cfg.autocomplete.temperature,
		stop = [[\n]], -- Stop at newline
		stream = true,
	}

	table.insert(args, "-d")
	table.insert(args, vim.json.encode(data))
	table.insert(args, model.api_url)

	return args
end

function M.trigger_autocomplete()
	local cfg = require("lnvim.cfg")
	local context = get_context(5, 0)
	local post_context = get_context(0, 5)
	local current_line = vim.api.nvim_get_current_line()
	local cursor_pos = vim.api.nvim_win_get_cursor(0)[2]
	local code_before_cursor = current_line:sub(1, cursor_pos)
	local code_after_cursor = current_line:sub(cursor_pos + 1)

	local prompt = table.concat(context, "\n") .. "\n" .. code_before_cursor
	local suffix = code_after_cursor .. "\n" .. table.concat(post_context, "\n")

	M.autocomplete(prompt, suffix, cfg.autocomplete_model, function(completion)
		vim.schedule(function()
			local lines = vim.split(completion, "\n")
			-- Insert the lines at the cursor position
			vim.api.nvim_put(lines, "c", true, true)
		end)
	end)
end

function M.autocomplete(prompt, suffix, model, callback)
	local args = generate_autocomplete_args(model, prompt, suffix)

	local completion = ""
	local function handle_data(data)
		local json_string = data:match("^data: (.+)$")
		if not json_string then
			return
		end

		local json_ok, json = pcall(vim.json.decode, json_string)
		if json_ok and json.choices and json.choices[1] and json.choices[1].text then
			-- vim.print(json)
			local content = json.choices[1].text
			if content then
				completion = completion .. content
			end
		elseif data:match("%[DONE%]") then
			-- vim.print("completion=" .. completion)
			callback(completion)
		end
	end

	Job:new({
		command = "curl",
		args = args,
		on_stdout = function(_, out)
			-- vim.print(out)
			handle_data(out)
		end,
		on_stderr = function(_, err)
			vim.notify("Error in autocomplete LLM call: " .. err, vim.log.levels.ERROR)
		end,
	}):start()
end

return M
