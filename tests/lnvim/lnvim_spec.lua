local lnvim = require("lnvim")
local match = require("luassert.match")
local toolcall = require("lnvim.toolcall")
local editor = require("lnvim.ui.editor")
local cmd = require("lnvim.cmd")
local LLM = require("lnvim.llm")
local buffers = require("lnvim.ui.buffers")
local constants = require("lnvim.constants")
local helpers = require("lnvim.utils.helpers")
describe("basic nav", function()
	it("opens the drawer and does basic nav", function()
		lnvim.setup()
		cmd.decide_with_magic()
		-- new L window is open with buffer
		local buf = vim.api.nvim_get_current_buf()
		assert(
			string.match(vim.api.nvim_buf_get_name(buffers.work_buffer), constants.filetype_ext) ~= nil,
			"lslop buf missing"
		)
		-- make sure its empty
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
			"trollolol",
			"",
			"```",
			"block1",
			"```",
			"between blocks",
			"```lua",
			"local x = 'block2'",
			"```",
		})
		editor.mark_codeblocks(buf)
		-- test cursor
		local cursor = vim.api.nvim_win_get_cursor(0)
		local next_cursor = nil

		cmd.next_magic()
		next_cursor = vim.api.nvim_win_get_cursor(0)
		vim.print(vim.inspect(cursor))
		vim.print(vim.inspect(next_cursor))
		assert(cursor[1] ~= next_cursor[1], "cursor did not move on next1")
		cursor = next_cursor

		cmd.next_magic()
		next_cursor = vim.api.nvim_win_get_cursor(0)
		assert(cursor[1] ~= next_cursor[1], "cursor did not move on next2")
		cursor = next_cursor

		cmd.next_magic()
		next_cursor = vim.api.nvim_win_get_cursor(0)
		assert(cursor[1] ~= next_cursor[1], "cursor did not move on next3")
		cursor = next_cursor

		cmd.previous_magic()
		next_cursor = vim.api.nvim_win_get_cursor(0)
		assert(cursor[1] ~= next_cursor[1], "cursor did not move on prev1")
		cursor = next_cursor

		cmd.previous_magic()
		next_cursor = vim.api.nvim_win_get_cursor(0)
		assert(cursor[1] ~= next_cursor[1], "cursor did not move on prev2")

		-- cursor stuff work
		cmd.set_system_prompt("hello world")
		assert(LLM.system_prompt == "hello world")

		helpers.set_prompt_files({ ".gitignore " })
		local buffer_content = vim.api.nvim_buf_get_lines(buffers.files_buffer, 0, -1, false)
		local has_the_line = false
		for _, line in ipairs(buffer_content) do
			if line:find(".gitignore") then
				has_the_line = true
				break
			end
		end
		assert(has_the_line)

		-- sys prompt function
		--
		-- see if default config runs LLM without error
		cmd.chat_with_magic()

		-- TODO: test pasting I guess
		--
		vim.notify("basic test passed")
		return true
	end)
	it("should yank the current codeblock", function()
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
			"Some text",
			"```lua",
			"local x = 1",
			"print(x)",
			"```",
			"More text",
		})

		vim.api.nvim_win_set_buf(0, buf)
		vim.api.nvim_win_set_cursor(0, { 3, 0 }) -- Move cursor to the codeblock

		editor.mark_codeblocks(buf)

		local result = editor.yank_codeblock()
		assert.is_true(result)

		local yanked = vim.fn.getreg('"')
		assert.are.equal("local x = 1\nprint(x)", yanked)
	end)
end)

describe("toolcall", function()
	it("should add tools with correct schema", function()
		-- Add a sample tool
		local sample_tool = toolcall.add_tool({
			name = "sample_tool",
			description = "A sample tool for testing",
			input_schema = {
				properties = {
					{
						name = "param1",
						type = "string",
						desc = "A sample parameter",
						required = true,
					},
					{
						name = "param2",
						type = "integer",
						desc = "Another sample parameter",
						required = false,
					},
				},
			},
			func = function(args)
				return "Sample result"
			end,
		})

		-- Check if the tool was added correctly
		assert.is_not_nil(toolcall.tools_available.sample_tool)
		assert.is_not_nil(toolcall.tools_functions.sample_tool)

		-- Verify the tool schema
		local tool = toolcall.tools_available.sample_tool
		assert.equals("sample_tool", tool.name)
		assert.equals("A sample tool for testing", tool.description)
		assert.equals("object", tool.input_schema.type)

		-- Check properties
		assert.is_not_nil(tool.input_schema.properties.param1)
		assert.equals("string", tool.input_schema.properties.param1.type)
		assert.equals("A sample parameter", tool.input_schema.properties.param1.description)

		assert.is_not_nil(tool.input_schema.properties.param2)
		assert.equals("integer", tool.input_schema.properties.param2.type)
		assert.equals("Another sample parameter", tool.input_schema.properties.param2.description)

		-- Check required fields
		assert.is_true(vim.tbl_contains(tool.input_schema.required, "param1"))
		assert.is_false(vim.tbl_contains(tool.input_schema.required, "param2"))
	end)

	it("should toggle tools", function()
		-- Enable tools (assuming they start disabled)
		toolcall.tools_toggle()
		assert.is_false(toolcall.tools_enabled)

		-- Disable tools
		toolcall.tools_toggle()
		assert.is_true(toolcall.tools_enabled)
	end)
	describe("LLM with tool calling", function()
		it("should stream text to diff_buffer when asking about embedding models", function()
			-- Setup
			lnvim.setup()
			local LLM = require("lnvim.llm")
			local buffers = require("lnvim.ui.buffers")
			local toolcall = require("lnvim.toolcall")

			-- Enable tool calling
			-- toolcall.tools_toggle()
			assert.is_true(toolcall.tools_enabled)

			-- Set up a mock system prompt and user query
			LLM.system_prompt = "You are a helpful AI assistant."
			local user_query = "What are some popular embedding models and their key features?"

			-- Clear the diff buffer
			vim.api.nvim_buf_set_lines(buffers.diff_buffer, 0, -1, false, {})

			-- Call the LLM
			local job = LLM.chat_with_buffer(LLM.system_prompt)

			-- Wait for the job to complete (you might need to adjust the timeout)
			vim.wait(10000, function()
				return job.is_shutdown
			end)

			-- Check if the diff buffer has content
			local buffer_content = vim.api.nvim_buf_get_lines(buffers.diff_buffer, 0, -1, false)
			assert.is_true(#buffer_content > 0, "Diff buffer should not be empty")

			-- Check if the content includes information about embedding models
			local has_embedding_info = false
			for _, line in ipairs(buffer_content) do
				print(line)
				if line:match("embedding") or line:match("model") then
					has_embedding_info = true
					break
				end
			end
			assert.is_true(has_embedding_info, "Response should contain information about embedding models")

			-- Check if tool calling was attempted
			local has_tool_call = false
			for _, line in ipairs(buffer_content) do
				if line:match("Tool Call:") then
					has_tool_call = true
					break
				end
			end
			assert.is_true(has_tool_call, "Tool calling should have been attempted")

			-- Clean up
			toolcall.tools_toggle()
		end)
	end)
end)

describe("promptmacro", function()
	it("should execute PromptMacro command", function()
		vim.api.nvim_buf_set_lines(buffers.work_buffer, 0, -1, false, {})
		-- Execute the PromptMacro command
		cmd.execute_prompt_macro("tests/macro.text")
		-- Check if the content is correctly added to the work buffer
		local buffer_content = vim.api.nvim_buf_get_lines(buffers.work_buffer, 0, -1, false)

		-- The expected content should include the executed bash command output
		local expected_content = {
			"",
			"Some text before",
			"",
			"```bash",
			'$ echo "Hello from bash" ',
			"Hello from bash",
			"```",
			"",
			"Some text after",
			"",
		}

		assert.are.same(expected_content, buffer_content)
	end)
end)
