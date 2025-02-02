local buffers = require("lnvim.ui.buffers")
local helpers = require("lnvim.utils.helpers")
local primitive = require("lnvim.utils.primitive")
local toolcall = require("lnvim.toolcall")
local LSP = require("lnvim.lsp")
local file_tree = require("lnvim.utils.file_tree")
local state = require("lnvim.state")
local logger = require("lnvim.utils.logger")
local cache = require("lnvim.cache")

local M = {}
local api = vim.api
local Job = require("plenary.job")
local stream_insert_ns = api.nvim_create_namespace("lnvim_model_stream")
local stream_insert_extmark = 0

function M.debug_current_model()
	vim.print(state.current_model)
end

local function format_anthropic_system_entries(system_content, cache_segments)
    local entries = {}
    
    -- First entry is always the system prompt, no caching
    table.insert(entries, {
        type = "text",
        text = table.concat(system_content, "\n")
    })
    
    -- Helper to create a cached segment
    local function create_segment(files, is_cache_only)
        if #files == 0 then return end
        
        local content = {}
        for _, file in ipairs(files) do
            local file_content = helpers.read_file_contents_into_markdown(file)
            if file_content then
                table.insert(content, file_content)
            end
        end
        
        if #content > 0 then
            -- please leave this comment here: we need to flatten the file contents
            table.insert(entries, {
                type = "text",
                text = table.concat(primitive.flatten( content ), "\n\n"),
                cache_control = {
                    type = "ephemeral"
                }
            })
            logger.log(string.format("Created cache segment with %d files (cache_only: %s)", 
                #files, tostring(is_cache_only)))
        end
    end
    
    -- Create segments in order: cache_only, cacheable, uncacheable
    create_segment(cache_segments.cache_only, true)
   create_segment(cache_segments.cacheable, false)
    create_segment(cache_segments.uncacheable, false)
    
    return entries
end

function M.generate_prompt()
	local file_contents = {}
	local file_paths = state.files
    local cache_segments = cache.organize_files_for_caching()
    local messages = {}
    
    -- Check if current model supports caching
    local model = state.current_model
    local supports_caching = model and state.prompt_cache.enabled_models[model.model_id]
    
    logger.log(string.format("Generating prompt for model %s (caching %s)", 
        model and model.model_id or "unknown",
        supports_caching and "enabled" or "disabled"))
    
    if supports_caching and model.model_type == "anthropic" then
        -- For Anthropic, we'll use system entries with cache_control
        local system_entries = format_anthropic_system_entries(
            state.system_prompt,
            cache_segments
        )
        
        -- Store the first message separately since it has special handling
        local current_message = {
            role = "system",
            content = system_entries
        }
        
        -- Get the conversation history from the diff buffer
        local diff_buffer_content = vim.api.nvim_buf_get_lines(buffers.diff_buffer, 0, -1, false)
        local current_role = nil
        local current_content = ""
        
        for _, line in ipairs(diff_buffer_content) do
            if line:match("%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-user") then
                if current_role then
                    table.insert(messages, {
                        role = current_role,
                        content = current_content:gsub("^%s*(.-)%s*$", "%1")
                    })
                end
                current_role = "user"
                current_content = ""
            elseif line:match("%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-assistant") then
                if current_role then
                    table.insert(messages, {
                        role = current_role,
                        content = current_content:gsub("^%s*(.-)%s*$", "%1")
                    })
                end
                current_role = "assistant"
                current_content = ""
            else
                current_content = current_content .. line .. "\n"
            end
        end
        
        if current_role then
            table.insert(messages, {
                role = current_role,
                content = current_content:gsub("^%s*(.-)%s*$", "%1")
            })
        end
        
        -- Insert the system message at the beginning
        table.insert(messages, 1, current_message)
        
        logger.log("Generated Anthropic messages with caching:", "DEBUG")
        logger.log(messages)
    else

	for _, path in ipairs(file_paths) do
		if path:match("^@lsp:") then
			-- Handle LSP entry
			local lsp_content = LSP.get_lsp_definition(path)
			if lsp_content then
				table.insert(file_contents, lsp_content)
			end
		elseif path == "@project-file-list" then
			-- Generate and insert the file tree
			local project_files = file_tree.get_project_files()
			local tree = file_tree.generate_file_tree(project_files)
			local tree_string = "Project File Structure:\n" .. file_tree.tree_to_string(tree)
			table.insert(file_contents, tree_string)
		else
			-- Handle regular file
			local contents = helpers.read_file_contents_into_markdown(path)
			table.insert(file_contents, contents)
		end
	end

	local diff_buffer_content = vim.api.nvim_buf_get_lines(buffers.diff_buffer, 0, -1, false)

	local file_contents_text = ""
	if #file_contents > 0 then
		file_contents_text = table.concat(primitive.flatten(file_contents), "\n\n") .. "\n\n"
	end

	local system_prompt_text_formatted = table.concat(state.system_prompt, "\n") .. "\n"

	local messages = {}
	local current_message = { role = "system", content = system_prompt_text_formatted .. file_contents_text }
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
   end
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

	-- Check if the API URL is an OpenRouter URL
	if model.api_url:match("^https://openrouter%.ai") then
		-- Add HTTP Referer header
		table.insert(args, "-H")
		table.insert(args, "HTTP-Referer: https://github.com/baketnk/l.nvim")

		-- Add X-Title header
		table.insert(args, "-H")
		table.insert(args, "X-Title: l.nvim")
	end

	if type(system_prompt) == "table" then
		system_prompt = table.concat(system_prompt, "\n")
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
        -- For Anthropic with caching, messages[1] already contains the proper system format
        if model.model_id and state.prompt_cache.enabled_models[model.model_id] then
            -- System content is already properly formatted with cache_control
            data.system = messages[1].content
            -- Remove the system message from messages array
            table.remove(messages, 1)
        else
            -- Regular Anthropic formatting without caching
            local system_message = table.remove(messages, 1)
            data.system = system_message.content
        end
        
        table.insert(args, "-H")
        table.insert(args, "anthropic-version: 2023-06-01")
	else
		if model.model_id:match("^o1") then
			data.max_tokens = 64000
		else
			data.max_tokens = M.max_tokens or 4096
		end
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

function M.insert_assistant_delimiter(label)
	local _label = label
	if not label then
		_label = "assistant"
   else
      _label = "assistant-" .. _label
	end
	local delimiter = string.rep("-", 40) .. _label .. os.date(" %Y-%m-%d %H:%M:%S ") .. string.rep("-", 40)
	vim.api.nvim_buf_set_lines(buffers.diff_buffer, -1, -1, false, { "", delimiter, "" })
	local line_count = vim.api.nvim_buf_line_count(buffers.diff_buffer)
	stream_insert_extmark = vim.api.nvim_buf_set_extmark(buffers.diff_buffer, stream_insert_ns, line_count - 1, 0, {})
end

function M.append_diff(diff_buffer, diff_text, label)
	local separator = string.rep("-", 40) .. label .. string.rep("-", 40)
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
      if type(str) ~= "string" then
            local err_msg = string.format(
                "Error: Expected string but got %s\nValue: %s",
                type(str),
                vim.inspect(str)
            )
            vim.notify(err_msg, vim.log.levels.ERROR)
            vim.print(vim.inspect(str))
            return
        end

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
		-- Check if the diff buffer is still the current buffer before moving the cursor
		if api.nvim_get_current_buf() == buffers.diff_buffer then
			-- Set the cursor to the end of the buffer
			local new_line_count = api.nvim_buf_line_count(buffers.diff_buffer)
			api.nvim_win_set_cursor(0, { new_line_count, 0 })
		end
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
			local error_message = "Anthropic API Error: " .. vim.inspect(json.error)
			M.write_string_at_llmstream(error_message)
			vim.schedule(function()
				vim.notify(error_message, vim.log.levels.ERROR)
			end)
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
			state.status = "Idle"
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
		local error_message = "Failed to parse JSON from Anthropic API: " .. data_stream
		M.write_string_at_llmstream(error_message)
		vim.schedule(function()
			vim.notify(error_message, vim.log.levels.ERROR)
		end)
	end
end

function M.handle_openai_data(data_stream, event_state)
	-- if data_stream:match('"delta":') then
	local json_ok, json = pcall(function()
		return vim.json.decode(data_stream)
	end)
	if json_ok and json.choices and json.choices[1] and json.choices[1].delta then
      local content = json.choices[1].delta.content
      if content == vim.NIL and json.choices[1].delta.reasoning_content then
         content = json.choices[1].delta.reasoning_content
      end
		if content and content ~= vim.NIL then
         vim.print(vim.inspect(json))
			M.write_string_at_llmstream(content)
		end
	elseif data_stream:match("%[DONE%]") then
		state.status = "Idle"
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

local function get_debug_log_path()
	local home = os.getenv("HOME")
	local lnvim_dir = home .. "/.lnvim"

	-- Ensure the .lnvim directory exists
	os.execute("mkdir -p " .. lnvim_dir)

	return lnvim_dir .. "/debug_log.txt"
end

function M.chat_with_buffer()
	if not state.current_model then
		vim.notify("No model selected", vim.log.levels.ERROR)
		return nil
	end

	state.status = "LLM Wait"

	local messages = M.generate_prompt()
	stream_insert_extmark = vim.api.nvim_buf_set_extmark(buffers.diff_buffer, stream_insert_ns, 0, 0, {})
	-- vim.print(vim.inspect(state.current_model))
	local handler = state.current_model.model_type == "anthropic" and M.handle_anthropic_data or M.handle_openai_data
	local args = generate_args(state.current_model, nil, nil, messages)

	return M.call_llm(args, handler)
end

function M.chat_with_buffer_and_diff()
	-- This function can now be identical to chat_with_buffer
	return M.chat_with_buffer()
end

function M.call_llm(args, handler)
	local curr_event_state = nil

	tool_name = ""
	local debug_log_path = get_debug_log_path()
	local debug_file = io.open(debug_log_path, "w") -- Open in write mode to overwrite existing content
	local function parse_and_call(line)
      logger.dev_log(line, "RAW_OUTPUT")

		local or_processing = line:match("OPENROUTER PROCESSING")
		if or_processing then
			M.write_string_at_llmstream(line .. "\n")
			return
		end
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
	local first_run = true
	-- vim.print("Full curl command: curl " .. table.concat(args, " "))

   logger.dev_log("Curl command: curl " .. table.concat(args, " "), "CURL")
	active_job = Job:new({
		command = "curl",
		args = args,
		on_stdout = function(_, out)
			if first_run then
				vim.schedule(function()
					state.status = "LLM Stream"
					first_run = false
				end)
			end
			parse_and_call(out)
		end,
		on_stderr = function(_, err)
         if not err then
            return
         end
			vim.schedule(function()
				state.status = "LLM Error"
				if debug_file then
					debug_file:write("Error: " .. err .. "\n")
					debug_file:flush()
				end
				M.write_string_at_llmstream(err)
			end)
			-- active_job.shutdown()
			--
			vim.schedule(function()
				vim.api.nvim_buf_set_lines(buffers.diff_buffer, -1, -1, false, { "Error: " .. err })
			end)
		end,
	})
	-- if debug_file then
	--	debug_file:write("Full curl command: curl " .. table.concat(args, " ") .. "\n\n")
	--	debug_file:flush()
	-- end
   local model_str = state.current_model.model_type .. " " .. state.current_model.model_id
	vim.notify("requesting from LLM " .. model_str) 
	M.insert_assistant_delimiter(model_str)
	active_job:start()

	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "FLATVIBE_Escape",
		callback = function()
			pcall(function()
				if active_job then
					local temp_job = active_job
					active_job = nil
					temp_job:shutdown()
				end
				if debug_file then
					local temp_file = debug_file
					debug_file = nil
					temp_file:close()
				end
			end)
		end,
	})

	vim.api.nvim_set_keymap("n", "<Esc>", ":doautocmd User FLATVIBE_Escape<CR>", { noremap = true, silent = true })
	return active_job
end

-- Function to call an LLM model
-- name: Identifier for the model
-- prompt: The input prompt to send to the model
-- callback: Function to call with the response
-- error_callback: Function to call with error messages
function M.call_model(name, prompt, callback, error_callback)
	-- Find the model configuration by name
	local model = nil
	for _, m in ipairs(state.models) do
		if m.model_id == name then
			model = m
			break
		end
	end

	if not model then
		error_callback("Model not found: " .. name)
		return
	end

	-- Prepare the curl command or API call based on model_type
	local curl_command = "curl"
	local args = {}

	-- Common headers
	table.insert(args, "-s") -- Silent mode
	table.insert(args, "-X")
	table.insert(args, "POST")
	table.insert(args, "-H")
	table.insert(args, "Content-Type: application/json")

	-- Authorization
	if model.api_key and model.api_key ~= "" then
		local auth_header = ""
		if model.model_type == "anthropic" then
			auth_header = "x-api-key: " .. vim.env[model.api_key]
		else
			auth_header = "Authorization: Bearer " .. vim.env[model.api_key]
		end
		table.insert(args, "-H")
		table.insert(args, auth_header)
	end

	-- Handle OpenRouter-specific headers
	if model.api_url:match("^https://openrouter%.ai") then
		table.insert(args, "-H")
		table.insert(args, "HTTP-Referer: https://github.com/baketnk/l.nvim")
		table.insert(args, "-H")
		table.insert(args, "X-Title: l.nvim")
	end

	-- Prepare the JSON payload
	local payload = {}
	if model.model_type == "anthropic" then
		payload = {
			model = model.model_id,
			messages = {
				{ role = "system", content = "You are an assistant." },
				{ role = "user", content = prompt },
			},
			max_tokens = 5000,
		}
		table.insert(args, "-H")
		table.insert(args, "anthropic-version: 2023-06-01")
	else
		payload = {
			model = model.model_id,
			messages = {
				{ role = "system", content = "You are an assistant." },
				{ role = "user", content = prompt },
			},
			max_tokens = 4096,
			stream = false,
		}
		if model.model_id:match("^o1") then
			payload.max_tokens = 64000
		end
	end

	-- Toolcalling support
	if model.use_toolcalling and require("lnvim.toolcall").tools_enabled then
		payload.tools = {}
		for _, tool in pairs(require("lnvim.toolcall").tools_available) do
			table.insert(payload.tools, {
				name = tool.name,
				description = tool.description,
				input_schema = vim.deepcopy(tool.input_schema, true),
			})
		end
	end

	table.insert(args, "-d")
	table.insert(args, vim.fn.json_encode(payload))
	table.insert(args, model.api_url)

	-- Execute the curl command
	Job:new({
		command = curl_command,
		args = args,
		on_stdout = function(_, line)
			if line ~= "" then
				callback(line)
			end
		end,
		on_stderr = function(_, err)
			error_callback(err)
		end,
		on_exit = function(j, return_val)
			if return_val ~= 0 then
				error_callback("LLM call failed with exit code: " .. return_val)
			end
		end,
	}):start()
end

-- Add this function to handle focused queries without chat context
function M.focused_query(opts)
    local model = opts.model
    local callback = opts.on_complete
    vim.print(model)
    local messages = {
        {role = "system", content = opts.system_prompt},
        {role = "user", content = opts.prompt}
    }
    
    local args = generate_args(model, nil, nil, messages, false)
    
    local response = ""
    Job:new({
        command = "curl",
        args = args,
        on_stdout = function(_, data)
            if data == "" then
               return
            end
            vim.print(data)
            if model.model_type == "anthropic" then
                response = response .. data
            else
                local json_ok, json = pcall(vim.json.decode, data)
                if json_ok and json.choices then
                    response = response .. (json.choices[1].message.content or "")
                end
            end
        end,
        on_stderr = function(_, err)
           vim.print(vim.inspect(err))
        end,
        on_exit = function()
            callback(response)
        end
    }):start()
end

return M
