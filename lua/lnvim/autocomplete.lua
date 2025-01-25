-- autocomplete.lua
local M = {
  job = 0,
}
local Job = require("plenary.job")
local cmp = require("cmp")
local state = require("lnvim.state")
local consts = require("lnvim.constants")
local source = {}

M.config = {
    highlight = {
        suggestion = "Comment", -- highlight group for suggestions
    },
    display = {
        position = 'inline', -- 'inline' or 'eol'
        max_suggestions = 3, -- maximum number of suggestions to show
    }
}

-- this function is taken from https://github.com/yasuoka/stralnumcmp/blob/master/stralnumcmp.lua
local function stralnumcmp(a, b)
  local a0, b0, an, bn, as, bs, c
  a0 = a
  b0 = b
  while a:len() > 0 and b:len() > 0 do
    an = a:match('^%d+')
    bn = b:match('^%d+')
    as = an or a:match('^%D+')
    bs = bn or b:match('^%D+')

    if an and bn then
      c = tonumber(an) - tonumber(bn)
    else
      c = (as < bs) and -1 or ((as > bs) and 1 or 0)
    end
    if c ~= 0 then
      return c
    end
    a = a:sub((an and an:len() or as:len()) + 1)
    b = b:sub((bn and bn:len() or bs:len()) + 1)
  end
  return (a0:len() - b0:len())
end



function source:is_available()
   return true
end
function source:get_debug_name()
   return consts.display_name
end
function source:get_keyword_pattern()
   return [[\k+]]
end
function source:get_trigger_characters()
   return { } -- "{", "}", "(", ")", "[", "]" }
end

-- greetz to avante
local function format_line_number(lines, start_line)
   if start_line == nil then
      start_line = 1
   end
   start_line = start_line - 1
   local result = {}
   for i, val in ipairs(lines) do
      table.insert(result, "Line" .. (i+start_line) .. ": " .. val)
   end
   return table.concat(result, "\n")
end

local function format_code(filename, lines, start_line)
   return table.concat({
      "<file>" ..
      "<filepath>" .. filename .. "</filepath>" ..
      "<code>" ..
      format_line_number(lines, start_line) ..
      "</code>" ..
      "</file>"
   }, "\n")
end



local function make_template()
   return {
      { role = "system",
       content = [[
Your task is to suggest code modifications at the cursor position. Follow these instructions meticulously:
  1. Carefully analyze the original code, paying close attention to its structure and the cursor position.
  2. You must follow this JSON format when suggesting modifications:
    ```
    [
      [
        {
          "start_row": ${start_row},
          "end_row": ${end_row},
          "content": "Your suggested code here"
        },
        {
          "start_row": ${start_row},
          "end_row": ${end_row},
          "content": "Your suggested code here"
        }
      ],
      [
        {
          "start_row": ${start_row},
          "end_row": ${end_row},
          "content": "Your suggested code here"
        },
        {
          "start_row": ${start_row},
          "end_row": ${end_row},
          "content": "Your suggested code here"
        }
    ]
    ```

    JSON fields explanation:
      start_row: The starting row of the code snippet you want to replace, start from 1, inclusive
      end_row: The ending row of the code snippet you want to replace, start from 1, inclusive
      content: The suggested code you want to replace the original code with

Guidelines:
  1. Make sure you have maintained the user's existing whitespace and indentation. This is REALLY IMPORTANT!
  2. Each code snippet returned in the list must not overlap, and together they complete the same task.
  3. The more code snippets returned at once, the better.
  4. If there is incomplete code on the current line where the cursor is located, prioritize completing the code on the current line.
  5. DO NOT include three backticks: '```' in your suggestion. Treat the suggested code AS IS.
  6. Each element in the returned list is a COMPLETE code snippet.
  7. MUST be a valid JSON format. DO NOT be lazy!
  8. Only return the new code to be inserted. DO NOT be lazy!
  9. Please strictly check the code around the position and ensure that the complete code after insertion is correct. DO NOT be lazy!
  10. Do not return the entire file content or any surrounding code. Only return the suggested code.
  11. Do not include any explanations, comments, or line numbers in your response.
  12. Ensure the suggested code fits seamlessly with the existing code structure and indentation.
  13. If there are no recommended modifications, return an empty list.
  14. Remember to ONLY RETURN the suggested code snippet, without any additional formatting or explanation.
  15. The returned code must satisfy the context, especially the context where the current cursor is located.
  16. Each line in the returned code snippet is complete code; do not include incomplete code.
       ]]
    },
         {
            role = "user",
            content = [[
      <filepath>a.py</filepath>
      <code>
      L1: def fib
      L2:
      L3: if __name__ == "__main__":
      L4:    # just pass
      L5:    pass
      </code>
            ]],
          },
          {
            role = "assistant",
            content = "ok",
          },
          {
            role = "user",
            content = '<question>{ "indentSize": 4, "position": { "row": 1, "col": 2 } }</question>',
          },
          {
            role = "assistant",
            content = [[
      [
        [
          {
            "start_row": 1,
            "end_row": 1,
            "content": "def fib(n):\n    if n < 2:\n        return n\n    return fib(n - 1) + fib(n - 2)"
          },
          {
            "start_row": 4,
            "end_row": 5,
            "content": "    fib(int(input()))"
          },
        ],
        [
          {
            "start_row": 1,
            "end_row": 1,
            "content": "def fib(n):\n    a, b = 0, 1\n    for _ in range(n):\n        yield a\n        a, b = b, a + b"
          },
          {
            "start_row": 4,
            "end_row": 5,
            "content": "    list(fib(int(input())))"
          },
        ]
      ]
            ]],
          },
      }
end

local function estimate_token_length(s)
   return #s / 4
end

local function generate_messages(params, targetLength, maxLength)
    local messages = make_template()
    local nvim_buf_get_lines = vim.api.nvim_buf_get_lines
    local nvim_buf_line_count = vim.api.nvim_buf_line_count

    local bufnr = params.context.bufnr
    local filepath = vim.api.nvim_buf_get_name(bufnr)
    local cursor = params.context.cursor
    
    local row, col = cursor.row, cursor.col

    local indentSize = vim.api.nvim_get_option_value("tabstop", { buf = bufnr })

    -- get current file (todo: reduce length? limit scope to LSP?)
    table.insert(messages,
      {
         role = "user",
         content = format_code(filepath, nvim_buf_get_lines(bufnr, 0, -1, false), 0)
      })
      table.insert(messages, 
      { 
         role = "assistant", content = "ok" 
      })
      table.insert(messages,
      {
         role = "user",
         content = ' <question>{ "indentSize": ' .. indentSize .. ', "row": ' .. row .. ', "col": ' .. col .. '}</question>'
      })

      -- TODO: LSP link from current function
   return messages
end

M.AUTOCOMPLETE_NS = vim.api.nvim_create_namespace("lnvim.autcomplete")
M.extmark = nil
M.suggestions = {}  -- Store the current suggestions
M.current_suggestion_index = 1  -- Track the current suggestion index



function M.call_autocomplete()

    local bufnr = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row, col = unpack(cursor)
    local params = {
        context = {
            bufnr = bufnr,
            cursor = {
                row = row,
                col = col
            }
        }
    }

    -- Create a wrapper for the callback to format the response properly
    local function handle_completion(text)
        text = text:gsub("^```%w*\n(.-)\n```$", "%1")
        text = text:gsub("(.-)\n```\n?$", "%1")
        text = text:gsub("^.-(%[.*)", "%1")
        vim.print(text)
        if not text then
           vim.print("text is garbo")
           return
        end
        -- Clear existing extmarks
        if M.extmark then
            for _, extmark in ipairs(M.extmark) do
                vim.api.nvim_buf_del_extmark(bufnr, M.AUTOCOMPLETE_NS, extmark)
            end
            M.extmark = nil
        end

        if text and text ~= "" then
            -- Parse the JSON response
            local ok, parsed = pcall(vim.json.decode, text)
            if not ok then
                vim.notify("Failed to parse completion response", vim.log.levels.ERROR)
                vim.print(text)
                return
            end

            -- Create virtual text for each suggestion
            M.extmark = {}
            local suggestions = parsed[1] -- Take first set of suggestions
            M.suggestions = parsed[1] or {}
            M.current_suggestion_index = 1

            if M.suggestions then
                for _, suggestion in ipairs(suggestions) do
                    -- Split content into lines
                    local lines = vim.split(suggestion.content, "\n")
                    local start_row = suggestion.start_row - 1 -- Convert to 0-based index
                    local end_row = suggestion.end_row - 1 -- Convert to 0-based index

                    for i, line in ipairs(lines) do
                        local row_idx = start_row + i - 1
                        if row_idx <= end_row then
                            local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, M.AUTOCOMPLETE_NS, row_idx, 0, {
                                virt_text = {{line, "Comment"}},
                                virt_text_pos = 'inline', -- or 'eol' for end of line
                                priority = 1000,
                                hl_mode = 'combine',
                            })
                            table.insert(M.extmark, extmark_id)
                        end
                        pcall(function()
                            local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, M.AUTOCOMPLETE_NS, end_row+1, 0, {
                                virt_text = {{"", "Comment"}},
                                virt_text_pos = 'inline', -- or 'eol' for end of line
                                priority = 1000,
                                hl_mode = 'combine',
                            })
                            table.insert(M.extmark, extmark_id)
                         end)
                    end
                end
            else 
               vim.print("no suggestion")
               vim.print(parsed)
            end

            -- Setup autocommands to clear extmarks
            vim.api.nvim_create_autocmd({"InsertChange", "CursorMoved"}, {
                buffer = bufnr,
                callback = function()
                    if M.extmark then
                        for _, extmark in ipairs(M.extmark) do
                            vim.api.nvim_buf_del_extmark(bufnr, M.AUTOCOMPLETE_NS, extmark)
                        end
                        M.extmark = nil
                    end
                end,
            })

        end
    end

    local messages = generate_messages(params, 1024, 2048)

    M.autocomplete(messages, state.autocomplete_model, params, handle_completion)
end

function M.insert_next_line()
    if not M.suggestions or #M.suggestions == 0 then
        vim.notify("No suggestions available", vim.log.levels.WARN)
        return
    end

    local suggestion = M.suggestions[M.current_suggestion_index]
    if not suggestion then
        vim.notify("No more suggestions", vim.log.levels.WARN)
        return
    end

    local lines = vim.split(suggestion.content, "\n")
    local current_line = lines[1]
    table.remove(lines, 1)  -- Remove the first line

    -- Insert the current line at the cursor position
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    vim.api.nvim_buf_set_lines(0, row - 1, row - 1, false, {current_line})

    -- Update the suggestion content with the remaining lines
    suggestion.content = table.concat(lines, "\n")

    -- If there are no more lines, move to the next suggestion
    if #lines == 0 then
        M.current_suggestion_index = M.current_suggestion_index + 1
    end
end

function M.insert_whole_suggestion()
    if not M.suggestions or #M.suggestions == 0 then
        vim.notify("No suggestions available", vim.log.levels.WARN)
        return
    end

    local suggestion = M.suggestions[M.current_suggestion_index]
    if not suggestion then
        vim.notify("No more suggestions", vim.log.levels.WARN)
        return
    end

    -- Insert the whole suggestion at the cursor position
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    vim.api.nvim_buf_set_lines(0, row - 1, row - 1, false, vim.split(suggestion.content, "\n"))

    -- Move to the next suggestion
    M.current_suggestion_index = M.current_suggestion_index + 1
end

local function generate_autocomplete_args(model, prompt)
   vim.print("ac args")
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
		table.insert(args, "Authorization: Bearer " .. os.getenv(model.api_key or ""))
	end

	local data = {
		model = model.model_id,
		messages = prompt,
		max_tokens = state.autocomplete.max_tokens,
		temperature = state.autocomplete.temperature,
		-- stop = [[\n]], -- Stop at newline
		stream = true,
	}
   if model.model_type == "anthropic" then
		local system_message = table.remove(data.messages, 1)
		data.system = system_message.content
		table.insert(args, "-H")
		table.insert(args, "anthropic-version: 2023-06-01")
   end
	table.insert(args, "-d")
	table.insert(args, vim.json.encode(data))
	table.insert(args, model.api_url)

	return args
end


function M.autocomplete(messages, model, params, callback)
   local args = generate_autocomplete_args(model, messages)
   local completion = ""
   local partial_json = ""
   local tool_name = ""
   
   local bufnr = params.context.bufnr
   
   M.extmark = { vim.api.nvim_buf_set_extmark(bufnr, M.AUTOCOMPLETE_NS, params.context.cursor.row - 1, params.context.cursor.col, {
                virt_text = {{ "loading", "Comment"}},
                virt_text_pos = 'inline', -- or 'eol' for end of line
                priority = 1000,
                hl_mode = 'combine',
            }) }

	local function handle_data(data)
        if not data then
           return
        end
        local json_string = data:match("^data: (.+)$")
        if not json_string then
            return
        end

        local json_ok, json = pcall(vim.json.decode, json_string)
        if not json_ok then
            if json_string:match("%[DONE%]") then
                state.status = "Idle"
                vim.schedule(function()
                   callback(completion)
                end)
                return
             else
            vim.notify("Failed to parse JSON: " .. json_string, vim.log.levels.ERROR)
            return
         end
        end

        -- Handle Anthropic API response
        if model.model_type == "anthropic" then
            if json.type == "error" then
                state.status = "AC ERROR"
                vim.notify("Anthropic API Error: " .. vim.inspect(json.error), vim.log.levels.ERROR)
            elseif json.type == "content_block_start" then
                if json.content_block and json.content_block.type == "tool_use" then
                    tool_name = json.content_block.name or tool_name or "Unknown"
                end
                partial_json = ""
            elseif json.type == "content_block_delta" then
                if json.delta and json.delta.type == "input_json_delta" then
                    partial_json = partial_json .. (json.delta.partial_json or "")
                elseif json.delta and json.delta.text then
                    completion = completion .. json.delta.text
                end
            elseif json.type == "content_block_stop" then
                state.status = "Idle"
                vim.schedule(function()
                   callback(completion)
                end)
            end
        -- Handle OpenAI API response
        else
            if json.choices and json.choices[1] and json.choices[1].delta then
                local content = json.choices[1].delta.content
                if content then
                    completion = completion .. content
                end
            elseif json.error then
               vim.schedule(function()
                  state.status = "AC ERROR"
                  vim.notify("API Error: " .. vim.inspect(json.error), vim.log.levels.ERROR)
               end)
            elseif json_string:match("%[DONE%]") then
                state.status = "Idle"
                vim.schedule(function()
                   callback(completion)
                end)
            end
        end
    end
	local first_run = true
	Job:new({
		command = "curl",
		args = args,
		on_stdout = function(_, out)
			-- vim.print(out)
			--
			if first_run then
				first_run = false
				state.status = "AC Stream"
			end
         vim.schedule(function()
			   handle_data(out)
         end)
		end,
		on_stderr = function(_, err)
			state.status = "AC Error"
			vim.notify("Error in autocomplete LLM call: " .. err, vim.log.levels.ERROR)
		end,
		on_exit = function()
			vim.schedule(function()
				state.status = "Idle"
			end)
		end,
	}):start()
end

cmp.register_source(consts.display_name, source)
M.source = source
return M
