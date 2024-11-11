-- autocomplete.lua
local M = {
  job = 0,
}
local Job = require("plenary.job")
local cmp = require("cmp")
local state = require("lnvim.state")
local consts = require("lnvim.constants")
local source = {}

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

local function get_context(params, maxLength)
    local nvim_buf_get_lines = vim.api.nvim_buf_get_lines
    local nvim_buf_line_count = vim.api.nvim_buf_line_count

    local bufnr = params.context.bufnr
    local cursor = params.context.cursor
    
    local row, col = cursor.row, cursor.col
    local totalLines = nvim_buf_line_count(bufnr)

    -- Function to get text before cursor (excluding current line)
    local function getTextBefore()
        if row <= 0 then return "" end
        
        local startRow = math.max(0, row - 10) -- Get up to 10 lines before
        local lines = nvim_buf_get_lines(bufnr, startRow, row, false)
        
        local textBefore = table.concat(lines, "\n")
        -- Limit the length from the end (as we want the most recent context)
        return string.sub(textBefore, -maxLength)
    end

    -- Function to get text after cursor (excluding current line)
    local function getTextAfter()
        if row >= totalLines - 1 then return "" end
        
        local endRow = math.min(totalLines, row + 11) -- Get up to 10 lines after
        local lines = nvim_buf_get_lines(bufnr, row + 1, endRow, false)
        
        local textAfter = table.concat(lines, "\n")
        -- Limit the length from the start
        return string.sub(textAfter, 1, maxLength)
    end

    return getTextBefore(), getTextAfter()
end

function source:complete(params, callback)
    vim.print("called lnvim autocomplete")
    vim.print(vim.inspect(params))
    -- Use the params object to get context instead of direct buffer access
    local cursor_line = params.context
    local cursor_col = params.context.cursor.col

    -- Get the lines before the cursor
    local lines_before, lines_after = get_context(params, 1024) -- gotta find this constant
vim.print("Lines before:", lines_before)
vim.print("Lines after:", lines_after)
    -- Construct the prompt with proper context
    local prompt = "<|fim_prefix|>" .. lines_before .. params.context.cursor_before_line .. "<|fim_suffix>" .. params.context.cursor_after_line .. lines_after .. "<|fim_middle|>"
    vim.print(prompt)

    -- Create a wrapper for the callback to format the response properly
    local function handle_completion(text)
        vim.print("handle completion callback -> cmp")
        if text and text ~= "" then
            local items = {}
            -- Split the completion into lines
            local lines = vim.split(text, "\n")
            for _, line in ipairs(lines) do
                if line ~= "" then
                    table.insert(items, {
                        label = line,
                        insertText = line,
                        kind = cmp.lsp.CompletionItemKind.Text,
                        documentation = {
                            kind = cmp.lsp.MarkupKind.Markdown,
                            value = text
                        }
                    })
                end
            end
            callback(items)
        else
            callback(nil)
        end
    end

    M.autocomplete(prompt, state.autocomplete_model, handle_completion)
end


function source:resolve(item, callback)
   callback(item)
end

function source:execute(completion_item, callback)
    -- Get the current line text before cursor
    local cursor_line = vim.api.nvim_get_current_line()
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local _, col = cursor_pos[1], cursor_pos[2]
    
    -- Get the text before cursor on current line
    local text_before = string.sub(cursor_line, 1, col)
    
    -- Get the completion text from the item
    local completion_text = completion_item.insertText or completion_item.label
    
    -- Find the common prefix between what's already typed and the completion
    local common_length = 0
    while common_length < #text_before and common_length < #completion_text do
        if stralnumcmp(string.sub(text_before, -common_length), string.sub(completion_text, 1, common_length)) == 0 then
            common_length = common_length + 1
        else
            break
        end
    end
    
    -- Extract only the new text to insert (excluding what's already typed)
    local text_to_insert = string.sub(completion_text, common_length + 1)
    
    -- Create a modified completion item with the correct text to insert
    local modified_item = vim.deepcopy(completion_item)
    modified_item.insertText = text_to_insert
    
    callback(modified_item)
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
		table.insert(args, "Authorization: Bearer " .. os.getenv(model.api_key))
	end

	local data = {
		model = model.model_id,
		prompt = prompt,
		max_tokens = state.autocomplete.max_tokens,
		temperature = state.autocomplete.temperature,
		stop = [[\n]], -- Stop at newline
		stream = true,
	}

	table.insert(args, "-d")
	table.insert(args, vim.json.encode(data))
	table.insert(args, model.api_url)

	return args
end


function M.autocomplete(prompt, model, callback)
	local args = generate_autocomplete_args(model, prompt)
   vim.print(args)
   local completion = ""
	local function handle_data(data)
		vim.print(vim.inspect(data))
		local json_string = data:match("^data: (.+)$")
		if not json_string then
			return
		end

		local json_ok, json = pcall(vim.json.decode, json_string)
		if json_ok then
			if json.choices and json.choices[1] and json.choices[1].text then
				local content = json.choices[1].text
				if content then
					completion = completion .. content
					-- Print each new line as it's streamed
					local lines = vim.split(content, "\n")
					for _, line in ipairs(lines) do
						if line ~= "" then
							print("New line: " .. line)
						end
					end
				end
			elseif json.error then
				state.status = "AC ERROR"
				vim.notify(vim.inspect(json.error))
			end
		elseif data:match("%[DONE%]") then
			state.status = "Idle"
			callback(completion)
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
			handle_data(out)
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
