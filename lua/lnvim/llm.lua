local buffers = require("lnvim.ui.buffers")
local helpers = require("lnvim.utils.helpers")
local primitive = require("lnvim.utils.primitive")
local toolcall = require("lnvim.toolcall")
-- local cfg = require("lnvim.cfg")

M = {}
local api = vim.api
local Job = require("plenary.job")
local stream_insert_ns = api.nvim_create_namespace("lnvim_model_stream")
local stream_insert_extmark = 0
local stream_buf = 0

local function make_anthropic_args(system_prompt, prompt, model, messages)
	local url = "https://api.anthropic.com/v1/messages"
	local api_key = os.getenv("ANTHROPIC_API_KEY")

	if not api_key then
		vim.notify("ANTHROPIC_API_KEY environment variable not set", vim.log.levels.ERROR)
		return
	end

	local data = {
		model = "claude-3-5-sonnet-20240620",
		max_tokens = 1024,
		messages = messages or {
			{ role = "user", content = prompt },
		},
		system = system_prompt,
		stream = true,
	}

	if toolcall.tools_enabled then
		data.tools = toolcall.tools_available
	end

	local args = {
		"-N",
		"-s",
		"-X",
		"POST",
		"-H",
		"Content-Type: application/json",
		"-H",
		"x-api-key: " .. api_key,
		"-H",
		"anthropic-version: 2023-06-01",
		"-d",
		vim.json.encode(data),
		url,
	}
	return args
end

local function make_openai_like_args(system_prompt, prompt, model, url, api_key)
	if not api_key then
		vim.notify("api key in environment variable not set", vim.log.levels.ERROR)
		return
	end

	local data = {
		model = model,
		max_tokens = M.max_tokens or 1024,
		messages = {
			{ role = "system", content = system_prompt },
			{ role = "user", content = prompt },
		},
		stream = true,
	}

	local args = {
		"-N",
		"-s",
		"-X",
		"POST",
		"-H",
		"Content-Type: application/json",
		"-H",
		"Authorization: Bearer " .. api_key,
		"-d",
		vim.json.encode(data),
		url,
	}
	return args
end

local function make_lambda_args(system_prompt, prompt, model, messages)
	model = model or "hermes-3-llama-3.1-405b-fp8"
	local url = "https://api.lambdalabs.com/v1/chat/completions"
	local api_key = os.getenv("LL_API_KEY") or os.getenv("LAMBDA_API_KEY")
	return make_openai_like_args(system_prompt, prompt, model, url, api_key)
end

function M.generate_prompt()
	local file_contents = {}
	local file_paths = vim.api.nvim_buf_get_lines(buffers.files_buffer, 0, -1, false)

	for _, path in ipairs(file_paths) do
		local contents = helpers.read_file_contents_into_markdown(path)
		table.insert(file_contents, contents)
	end

	local user_text = vim.api.nvim_buf_get_lines(buffers.work_buffer, 0, -1, false)

	local file_contents_text = ""
	if #file_contents > 0 then
		file_contents_text = table.concat(primitive.flatten(file_contents), "\n\n") .. "\n\n"
	end
	local prompt = file_contents_text .. table.concat(user_text, "\n")
	return prompt
end

function M.write_string_at_cursor(str)
	vim.schedule(function()
		local current_window = vim.api.nvim_get_current_win()
		local cursor_position = vim.api.nvim_win_get_cursor(current_window)
		local row, col = cursor_position[1], cursor_position[2]

		local lines = vim.split(str, "\n")

		vim.cmd("undojoin")
		vim.api.nvim_put(lines, "c", true, true)

		local num_lines = #lines
		local last_line_length = #lines[num_lines]
		vim.api.nvim_win_set_cursor(current_window, { row + num_lines - 1, col + last_line_length })
	end)
end

function M.write_string_at_llmstream(str)
	vim.schedule(function()
		local extmark = api.nvim_buf_get_extmark_by_id(
			buffers.diff_buffer,
			stream_insert_ns,
			stream_insert_extmark,
			{ details = true }
		)
		local row, col = extmark[3].end_row or -1, extmark[3].end_col or -1
		local lines = vim.split(str, "\n", {})
		vim.cmd("undojoin")
		api.nvim_buf_set_text(buffers.diff_buffer, row, col, row, col, lines)
	end)
end

local llm_messages = {}

function M.handle_anthropic_data(data_stream)
	local json_ok, json = pcall(function()
		return vim.json.decode(data_stream)
	end)
	if json_ok then
		if json.type == "content_block_delta" then
			local content = json.delta.text
			if content then
				M.write_string_at_llmstream(content)
			end
		elseif json.type == "tool_call" then
			local tool_name = json.tool_call["function"].name
			local tool_args = json.tool_call["function"].arguments

			-- Print friendly format to buffer
			M.write_string_at_llmstream("\n\nTool Call: " .. tool_name .. "\nArguments: " .. tool_args .. "\n")

			-- Save tool call in proper JSON format for LLM consumption
			local tool_call_message = {
				finish_reason = "tool_calls",
				index = 0,
				logprobs = vim.NIL,
				message = {
					content = vim.NIL,
					role = "assistant",
					function_call = vim.NIL,
					tool_calls = {
						{
							id = "call_" .. tostring(os.time()),
							["function"] = {
								arguments = tool_args,
								name = tool_name,
							},
							type = "function",
						},
					},
				},
			}

			-- Append tool call message to llm_messages
			table.insert(llm_messages, tool_call_message)

			-- Execute tool and get result
			local tool = toolcall.tools_available[tool_name]
			local result = tool.func(tool_args)

			-- Print tool result
			M.write_string_at_llmstream("Result: " .. result .. "\n\n")

			-- Append tool result to messages
			table.insert(llm_messages, { role = "function", name = tool_name, content = result })

			-- Call LLM again with updated messages
			M.call_llm_with_messages()
		end
	end
end

function M.handle_openai_data(data_stream, event_state)
	-- if data_stream:match('"delta":') then
	local json_ok, json = pcall(function()
		return vim.json.decode(data_stream)
	end)
	if json_ok and json.choices and json.choices[1] and json.choices[1].delta then
		local content = json.choices[1].delta.content
		if content then
			M.write_string_at_llmstream(content)
		end
	end
	-- end
end

local group = vim.api.nvim_create_augroup("FLATVIBE_AutoGroup", { clear = true })
local active_job = nil

M.provider_args_map = {
	anthropic = make_anthropic_args,
	lambdalabs = make_lambda_args,
}
M.provider_parse_map = {
	anthropic = M.handle_anthropic_data,
	lambdalabs = M.handle_openai_data,
}
M.providers_available = {}
-- default provider if not set explicitly
if os.getenv("ANTHROPIC_API_KEY") then
	M.providers_available[#M.providers_available + 1] = "anthropic"
end
if os.getenv("LAMBDA_API_KEY") then
	M.providers_available[#M.providers_available + 1] = "lambdalabs"
end

M.default_provider = M.providers_available[1] or nil

function M.cycle_provider()
	if M.default_provider == M.providers_available[#M.providers_available] then
		M.default_provider = M.providers_available[1]
		vim.notify("switched to " .. M.default_provider)
		return
	end
	for i, p in ipairs(M.providers_available) do
		if M.default_provider == p then
			M.default_provider = M.providers_available[i + 1]
			vim.notify("switched to " .. M.default_provider)
			return
		end
	end
end

local max_prompt_length = 8192

function M.call_llm_with_messages()
	local system_prompt = M.system_prompt or ""
	local args = M.provider_args_map[M.default_provider](system_prompt, nil, nil, llm_messages)
	local handler = M.provider_parse_map[M.default_provider]

	return M.call_llm(args, handler)
end

function M.chat_with_buffer(system_prompt)
	local prompt = M.generate_prompt()
	prompt = vim.fn.strpart(prompt, -max_prompt_length)

	if not M.default_provider then
		vim.notify("Couldn't auto config providers, better UI is coming soon!")
		return nil
	end

	stream_insert_extmark = vim.api.nvim_buf_set_extmark(buffers.diff_buffer, stream_insert_ns, 0, 0, {})

	local handler = M.provider_parse_map[M.default_provider]
	local args = M.provider_args_map[M.default_provider](system_prompt, prompt)

	return M.call_llm(args, handler)
end

function M.call_llm(args, handler)
	local curr_event_state = nil

	local function parse_and_call(line)
		local event = line:match("^event: (.+)$")
		if event then
			curr_event_state = event
			return
		end
		local data_match = line:match("^data: (.+)$")
		if data_match then
			handler(data_match, curr_event_state)
		end
	end

	if active_job then
		active_job:shutdown()
		active_job = nil
	end

	active_job = Job:new({
		command = "curl",
		args = args,
		on_stdout = function(_, out)
			parse_and_call(out)
		end,
		on_stderr = function(_, err)
			M.write_string_at_cursor(err)
		end,
	})

	active_job:start()

	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "FLATVIBE_Escape",
		callback = function()
			if active_job then
				active_job:shutdown()
				active_job = nil
			end
		end,
	})

	vim.api.nvim_set_keymap("n", "<Esc>", ":doautocmd User FLATVIBE_Escape<CR>", { noremap = true, silent = true })
	return active_job
end

-- vim.notify("llm loaded!")
return M
