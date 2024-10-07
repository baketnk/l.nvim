local buffers = require("lnvim.ui.buffers")
local helpers = require("lnvim.utils.helpers")
local primitive = require("lnvim.utils.primitive")
local toolcall = require("lnvim.toolcall")
-- local cfg = require("lnvim.cfg") -- CYCLIC DO NOT UNCOMMENT
local LazyLoad = require("lnvim.utils.lazyload")
local cfg = LazyLoad("lnvim.cfg")
local LSP = require("lnvim.lsp")

M = {}
local api = vim.api
local Job = require("plenary.job")
local stream_insert_ns = api.nvim_create_namespace("lnvim_model_stream")
local stream_insert_extmark = 0

function M.generate_prompt()
	local file_contents = {}
	local file_paths = vim.api.nvim_buf_get_lines(buffers.files_buffer, 0, -1, false)

	for _, path in ipairs(file_paths) do
		if path:match("^@lsp:") then
			-- Handle LSP entry
			local lsp_content = LSP.get_lsp_definition(path)
			if lsp_content then
				table.insert(file_contents, lsp_content)
			end
		else
			-- Handle regular file
			local contents = helpers.read_file_contents_into_markdown(path)
			table.insert(file_contents, contents)
		end
	end

	local preamble_text = vim.api.nvim_buf_get_lines(buffers.preamble_buffer, 0, -1, false)
	local diff_buffer_content = vim.api.nvim_buf_get_lines(buffers.diff_buffer, 0, -1, false)

	local file_contents_text = ""
	if #file_contents > 0 then
		file_contents_text = table.concat(primitive.flatten(file_contents), "\n\n") .. "\n\n"
	end

	local preamble_text_formatted = #preamble_text > 0 and "NOTES:\n" .. table.concat(preamble_text, "\n") .. "\n\n"
		or ""

	local messages = {}
	local current_message = { role = "system", content = preamble_text_formatted .. file_contents_text }
	local current_role = nil
	local current_content = ""

	for _, line in ipairs(diff_buffer_content) do
		if line:match("%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-user") then
			if current_role then
				table.insert(messages, { role = current_role, content = current_content:gsub("^%s*(.-)%s*$", "%1") })
			end
			current_role = "user"
			current_content = ""
		elseif line:match("%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-assistant") then
			if current_role then
				table.insert(messages, { role = current_role, content = current_content:gsub("^%s*(.-)%s*$", "%1") })
			end
			current_role = "assistant"
			current_content = ""
		else
			current_content = current_content .. line .. "\n"
		end
	end

	if current_role then
		table.insert(messages, { role = current_role, content = current_content:gsub("^%s*(.-)%s*$", "%1") })
	end

	-- Insert the system message at the beginning
	table.insert(messages, 1, current_message)

	return messages
end

local function generate_args(model, system_prompt, prompt, messages, streaming)
	local is_streaming = true
	if streaming ~= nil then
		is_streaming = is_streaming
	end
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
		if model.model_type == "anthropic" then
			table.insert(args, "x-api-key: " .. os.getenv(model.api_key))
		else
			table.insert(args, "Authorization: Bearer " .. os.getenv(model.api_key))
		end
	end

	local data = {
		model = model.model_id,
		messages = messages or {
			{ role = "system", content = system_prompt },
			{ role = "user", content = prompt },
		},
		stream = is_streaming,
	}

	if model.model_type == "anthropic" then
		data.max_tokens = 5000
		local system_message = table.remove(data.messages, 1)
		data.system = system_message.content
		table.insert(args, "-H")
		table.insert(args, "anthropic-version: 2023-06-01")
	else
		data.max_tokens = M.max_tokens or 1024
	end

	if model.use_toolcalling and toolcall.tools_enabled then
		data.tools = {}
		for _, tool in pairs(toolcall.tools_available) do
			table.insert(data.tools, {
				name = tool.name,
				description = tool.description,
				input_schema = vim.deepcopy(tool.input_schema, true),
			})
		end
	end

	table.insert(args, "-d")
	table.insert(args, vim.json.encode(data))
	table.insert(args, model.api_url)
	return args
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

function M.insert_assistant_delimiter()
	local delimiter = string.rep("-", 40) .. "assistant" .. os.date(" %Y-%m-%d %H:%M:%S ") .. string.rep("-", 40)
	vim.api.nvim_buf_set_lines(buffers.diff_buffer, -1, -1, false, { "", delimiter, "" })
	local line_count = vim.api.nvim_buf_line_count(buffers.diff_buffer)
	stream_insert_extmark = vim.api.nvim_buf_set_extmark(buffers.diff_buffer, stream_insert_ns, line_count - 1, 0, {})
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
		-- delimit

		local lines = vim.split(str, "\n", {})

		pcall(vim.cmd.undojoin)
		api.nvim_buf_set_text(buffers.diff_buffer, row, col, row, col, lines)
	end)
end

function M.print_user_delimiter()
	vim.schedule(function()
		local delimiter = string.rep("-", 40) .. "user" .. os.date(" %Y-%m-%d %H:%M:%S ") .. string.rep("-", 40)

		local row, col

		-- Get the current buffer line count
		local line_count = api.nvim_buf_line_count(buffers.diff_buffer)

		-- If the buffer is not empty, add a new line
		if line_count > 0 then
			api.nvim_buf_set_lines(buffers.diff_buffer, line_count, -1, false, { "", "" })
			row = line_count + 1
		else
			row = 0
		end
		col = 0

		-- Insert the delimiter
		api.nvim_buf_set_lines(buffers.diff_buffer, row, row + 1, false, { delimiter, "" })

		-- Check if the existing extmark is valid
		local is_valid = stream_insert_extmark > 0
		-- If the extmark is not valid, create a new one
		if not is_valid then
			stream_insert_extmark = api.nvim_buf_set_extmark(buffers.diff_buffer, stream_insert_ns, row + 1, 0, {})
		else
			-- Update the existing extmark
			stream_insert_extmark = api.nvim_buf_set_extmark(
				buffers.diff_buffer,
				stream_insert_ns,
				row + 1,
				0,
				{ id = stream_insert_extmark }
			)
		end
		-- Set the cursor to the end of the buffer
		local new_line_count = api.nvim_buf_line_count(buffers.diff_buffer)
		api.nvim_win_set_cursor(0, { new_line_count, 0 })
	end)
end

local llm_messages = {}
local tool_queue = {}
local partial_json = ""
local tool_name = ""
function M.handle_anthropic_data(data_stream)
	local json_ok, json = pcall(vim.json.decode, data_stream)
	if json_ok then
		if json.type == "error" then
			M.write_string_at_llmstream(vim.inspect(json.error))
		elseif json.type == "content_block_start" then
			if json.content_block and json.content_block.type == "tool_use" then
				tool_name = json.content_block.name or tool_name or "Unknown"
			elseif json.content and json.content.type == "tool_use" then
				tool_name = json.content.name or tool_name or "Unknown"
			end
			partial_json = ""
		elseif json.type == "content_block_delta" then
			if json.delta and json.delta.type == "input_json_delta" then
				partial_json = partial_json .. (json.delta.partial_json or "")
			elseif json.delta and json.delta.text then
				M.write_string_at_llmstream(json.delta.text)
			end
		elseif json.type == "content_block_stop" then
			local tool_input_ok, tool_input = pcall(vim.json.decode, partial_json)
			if tool_input_ok then
				M.write_string_at_llmstream("Arguments: " .. vim.inspect(tool_input) .. "\n")
				table.insert(tool_queue, {
					name = tool_name,
					input = tool_input,
				})
				vim.schedule(M.process_tool_queue)
			elseif toolcall.tools_enabled then
				vim.print("Failed to parse tool input JSON: " .. partial_json)
			end
			M.print_user_delimiter()
		end
	else
		vim.print("Failed to parse JSON: " .. data_stream)
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
	elseif data_stream:match("%[DONE%]") then
		M.print_user_delimiter()
	end
end

function M.process_tool_queue()
	if #tool_queue > 0 then
		local tool = table.remove(tool_queue, 1)
		local tool_func = toolcall.tools_functions[tool.name]

		if not tool_func then
			vim.notify("Tool function not found for: " .. tool.name)
			return
		end

		if type(tool.input) ~= "table" or vim.tbl_isempty(tool.input) then
			vim.notify("Invalid tool input: " .. vim.inspect(tool.input))
			return
		end

		local ok, result = pcall(tool_func, tool.input)
		if not ok then
			vim.notify("Error executing tool: " .. result)
			return
		end

		M.write_string_at_llmstream("Result: " .. result .. "\n\n")

		-- Format the tool result as per the requirement
		local tool_result = {
			role = "user",
			content = {
				{
					type = "tool_result",
					tool_use_id = "toolu_" .. os.time(), -- Generate a unique ID
					content = result,
				},
			},
		}

		-- Append tool result to messages
		table.insert(llm_messages, tool_result)

		-- Call LLM again with updated messages
		M.call_llm_with_messages()
	end
end

local group = vim.api.nvim_create_augroup("FLATVIBE_AutoGroup", { clear = true })
local active_job = nil

function M.chat_with_buffer()
	if not cfg.current_model then
		vim.notify("No model selected", vim.log.levels.ERROR)
		return nil
	end

	local messages = M.generate_prompt()
	stream_insert_extmark = vim.api.nvim_buf_set_extmark(buffers.diff_buffer, stream_insert_ns, 0, 0, {})
	vim.print(vim.inspect(cfg.current_model))
	local handler = cfg.current_model.model_type == "anthropic" and M.handle_anthropic_data or M.handle_openai_data
	local args = generate_args(cfg.current_model, nil, nil, messages)

	return M.call_llm(args, handler)
end

function M.chat_with_buffer_and_diff()
	-- This function can now be identical to chat_with_buffer
	return M.chat_with_buffer()
end

function M.call_llm(args, handler)
	local curr_event_state = nil

	tool_name = ""
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
	-- vim.print("Full curl command: curl " .. table.concat(args, " "))
	active_job = Job:new({
		command = "curl",
		args = args,
		on_stdout = function(_, out)
			parse_and_call(out)
		end,
		on_stderr = function(_, err)
			vim.print("Error in LLM call: " .. err, vim.log.levels.ERROR)
			-- active_job.shutdown()
			--
			vim.schedule(function()
				vim.api.nvim_buf_set_lines(buffers.diff_buffer, -1, -1, false, { "Error: " .. err })
			end)
		end,
	})
	vim.notify("requesting from LLM " .. cfg.current_model.model_type)
	M.insert_assistant_delimiter()
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

return M
