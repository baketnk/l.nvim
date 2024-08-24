M = {}
local Job = require("plenary.job")

local function get_prompt()
	local current_buffer = vim.api.nvim_get_current_buf()
	local current_window = vim.api.nvim_get_current_win()
	local cursor_position = vim.api.nvim_win_get_cursor(current_window)
	local row = cursor_position[1]

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

function M.handle_openai_data(data_stream, event_state)
	-- if data_stream:match('"delta":') then
	local json = vim.json.decode(data_stream)
	if json.choices and json.choices[1] and json.choices[1].delta then
		local content = json.choices[1].delta.content
		if content then
			M.write_string_at_cursor(content)
		end
	end
	-- end
end

local group = vim.api.nvim_create_augroup("FLATVIBE_AutoGroup", { clear = true })
local active_job = nil

function M.chat_with_buffer(system_prompt)
	-- vim.notify("build prompt")
	local prompt = get_prompt()
	-- limit prompt size if needed, to the last X characters
	prompt = vim.fn.strpart(prompt, -1024)
	-- build curl args
	if vim.g.lnvim_opts.use_llm_cli then
		return M.chat_via_llm_cli(system_prompt, prompt)
	end
	local url = os.getenv(vim.g.lnvim_opts.api_url or "LAMBDA_API_URL")
		or "https://api.lambdalabs.com/v1/chat/completions"
	local api_key = os.getenv(vim.g.lnvim_opts.api_key_name or "LL_API_KEY")
	local data = {
		messages = { { role = "system", content = system_prompt }, { role = "user", content = prompt } },
		model = vim.g.lnvim_opts.model_name or "hermes-3-llama-3.1-405b-fp8",
		-- temperature = 0.7,
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
			M.handle_openai_data(data_match, curr_event_state)
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
		on_exit = function()
			active_job = nil
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
				print("LLM streaming cancelled")
			end
		end,
	})
	-- vim.notify("autocmd and return")
	vim.api.nvim_set_keymap("n", "<Esc>", ":doautocmd User FLATVIBE_Escape<CR>", { noremap = true, silent = true })
	return active_job
end
-- vim.notify("llm loaded!")
return M
