M = {}
local api = vim.api
local Job = require("plenary.job")
local stream_insert_ns = api.nvim_create_namespace("lnvim_model_stream")
local stream_insert_extmark = 0
local stream_buf = 0

local function make_anthropic_args(system_prompt, prompt, model)
	local url = "https://api.anthropic.com/v1/messages"
	local api_key = os.getenv("ANTHROPIC_API_KEY")

	if not api_key then
		vim.notify("ANTHROPIC_API_KEY environment variable not set", vim.log.levels.ERROR)
		return
	end

	local data = {
		model = "claude-3-5-sonnet-20240620",
		max_tokens = 1024,
		messages = {
			{ role = "user", content = prompt },
		},
		system = system_prompt,
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

local function make_lambda_args(system_prompt, prompt, model)
	model = model or "hermes-3-llama-3.1-405b-fp8"
	local url = "https://api.lambdalabs.com/v1/chat/completions"
	local api_key = os.getenv("LL_API_KEY") or os.getenv("LAMBDA_API_KEY")
	return make_openai_like_args(system_prompt, prompt, model, url, api_key)
end

local function get_prompt()
	local current_buffer = api.nvim_get_current_buf()
	stream_buf = current_buffer
	local current_window = api.nvim_get_current_win()
	local cursor_position = api.nvim_win_get_cursor(current_window)
	local row = cursor_position[1]
	local col = cursor_position[2]
	-- set dest for what we want to do
	stream_insert_extmark = api.nvim_buf_set_extmark(current_buffer, stream_insert_ns, row, col, {
		hl_group = "LLMStream",
	})

	local lines = vim.api.nvim_buf_get_lines(current_buffer, 0, row, true)

	return table.concat(lines, "\n")
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
		local extmark =
			api.nvim_buf_get_extmark_by_id(stream_buf, stream_insert_ns, stream_insert_extmark, { details = true })
		local row, col = extmark[3].end_row or -1, extmark[3].end_col or -1
		local lines = vim.split(str, "\n", {})
		vim.cmd("undojoin")
		api.nvim_buf_set_text(0, row, col, row, col, lines)
	end)
end

function M.handle_anthropic_data(data_stream)
	vim.print(data_stream)
	local json_ok, json = pcall(function()
		return vim.json.decode(data_stream)
	end)
	vim.print(vim.inspect(json))
	-- if we want, handle message_start, content_block_start/stop, ping events
	if json_ok and json.type == "content_block_delta" then
		local content = json.delta.text
		if content then
			M.write_string_at_llmstream(content)
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

function M.chat()
	return nil
end

function M.chat_with_buffer(system_prompt)
	-- vim.notify("build prompt")
	local prompt = get_prompt()
	-- limit prompt size if needed, to the last X characters
	prompt = vim.fn.strpart(prompt, -16386)
	-- build curl args
	if not M.default_provider then
		vim.notify("Couldn't auto config providers, better UI is coming soon!")
		return nil
	end

	local handler = M.provider_parse_map[M.default_provider]
	local args = M.provider_args_map[M.default_provider](system_prompt, prompt)
	local curr_event_state = nil
	-- vim.notify("define locals")
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
			-- if handler ~= M.handle_openai_data then
			--	handler(out)
			-- else
			parse_and_call(out)
			-- end
		end,
		on_stderr = function(_, err)
			M.write_string_at_cursor(err)
		end,
	})
	-- vim.notify("start job")
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
	-- vim.notify("autocmd and return")
	vim.api.nvim_set_keymap("n", "<Esc>", ":doautocmd User FLATVIBE_Escape<CR>", { noremap = true, silent = true })
	return active_job
end
-- vim.notify("llm loaded!")
return M
