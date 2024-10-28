-- autocomplete.lua
local M = {}
local completion = ""
local Job = require("plenary.job")
local state = require("lnvim.state")

local function get_context(lines_before, lines_after)
	local current_line = vim.fn.line(".")
	local start_line = math.max(1, current_line - lines_before)
	local end_line = math.min(vim.fn.line("$"), current_line + lines_after)

	return vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
end

local function generate_autocomplete_args(model, prompt, suffix)
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

local autocmd_id = nil
local remove_completion_text = function() end
local function create_autocmd()
	autocmd_id = vim.api.nvim_create_autocmd({ "InsertCharPre", "TextChanged", "TextChangedI" }, {
		callback = function(ev)
			if
				ev.event == "InsertCharPre" and (vim.v.char == "\x17" or vim.v.char == "\x0c" or vim.v.char == "\x06")
			then
				-- Ignore Ctrl-W, Ctrl-L, and Ctrl-F
				return
			end
			remove_completion_text()
		end,
	})
end

function M.trigger_autocomplete()
	local context = get_context(100, 0)
	local post_context = get_context(0, 100)
	local current_line = vim.api.nvim_get_current_line()
	local cursor_pos = vim.api.nvim_win_get_cursor(0)[2]
	local code_before_cursor = current_line:sub(1, cursor_pos)
	local code_after_cursor = current_line:sub(cursor_pos + 1)

	local prompt = table.concat(context, "\n") .. "\n" .. code_before_cursor
	local suffix = code_after_cursor .. "\n" .. table.concat(post_context, "\n")
	state.status = "Autocomplete"

	completion = ""

	create_autocmd()
	M.autocomplete(prompt, suffix, state.autocomplete_model, function(completion)
		vim.schedule(function()
			local lines = vim.split(completion, "\n")
			-- Insert the lines at the cursor position
			vim.api.nvim_put(lines, "c", true, true)
		end)
	end)
end

local function complete_word()
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2]
	local word_start = vim.fn.match(line:sub(1, col), "\\k*$")
	local word = vim.split(completion, "%s+")[1]
	vim.api.nvim_buf_set_text(0, vim.fn.line(".") - 1, word_start, vim.fn.line(".") - 1, col, { word })
end

local function complete_line()
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2]
	local completion_line = vim.split(completion, "\n")[1]
	vim.api.nvim_buf_set_text(
		0,
		vim.fn.line(".") - 1,
		col,
		vim.fn.line(".") - 1,
		#line,
		{ completion_line:sub(col + 1) }
	)
end

local function complete_full()
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2]
	local lines = vim.split(completion, "\n")
	vim.api.nvim_buf_set_text(0, vim.fn.line(".") - 1, col, vim.fn.line(".") - 1, #line, lines)
end

M.complete_word = complete_word
M.complete_line = complete_line
M.complete_full = complete_full

local ns_id = vim.api.nvim_create_namespace("LnvimAutoComplete")
local completion_mark = nil
vim.api.nvim_set_hl(0, "LnvimAutoComplete", {
	bg = vim.o.background == "dark" and "#3c3c3c" or "#dddddd",
	fg = vim.o.background == "dark" and "#bcbcbc" or "#454545",
	italic = true,
})

local function set_completion_mark()
	local line, col = unpack(vim.api.nvim_win_get_cursor(0))
	local line_text = vim.api.nvim_get_current_line()
	local end_col = math.min(col + #completion, #line_text)

	completion_mark = vim.api.nvim_buf_set_extmark(0, ns_id, line - 1, col, {
		end_line = line - 1,
		end_col = end_col,
		hl_group = "LnvimAutoComplete",
	})
end

local function clear_completion_mark()
	if completion_mark then
		vim.api.nvim_buf_del_extmark(0, ns_id, completion_mark)
		completion_mark = nil
	end
end

local function disable_autocmd()
	if autocmd_id then
		vim.api.nvim_del_autocmd(autocmd_id)
		autocmd_id = nil
	end
end

local function remove_completion_text()
	if completion_mark then
		local mark = vim.api.nvim_buf_get_extmark_by_id(0, ns_id, completion_mark, { details = true })
		if mark and #mark > 0 then
			local start_line, start_col = mark[1], mark[2]
			local end_line, end_col = mark[3].end_line, mark[3].end_col
			local current_text = vim.api.nvim_buf_get_text(0, start_line, start_col, end_line, end_col, {})[1] or ""
			if #current_text > 0 then
				vim.api.nvim_buf_set_text(0, start_line, start_col, end_line, end_col, { "" })
			end
		end
		clear_completion_mark()
	end
	disable_autocmd()
end

function M.autocomplete(prompt, suffix, model, callback)
	local args = generate_autocomplete_args(model, prompt, suffix)

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
				set_completion_mark()
				state.status = "Idle"
			end)
		end,
	}):start()
end

return M
