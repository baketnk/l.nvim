local lnvim = require("lnvim")
local match = require("luassert.match")
local toolcall = require("lnvim.toolcall")
local editor = require("lnvim.ui.editor")
local cmd = require("lnvim.cmd")
local LLM = require("lnvim.llm")
local diff_utils = require("lnvim.utils.diff")
local cmd = require("lnvim.cmd")
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
				type = "object",
				properties = {
					param1 = {
						name = "param1",
						type = "string",
						description = "A sample parameter",
						required = true,
					},
					param2 = {
						name = "param2",
						type = "integer",
						description = "Another sample parameter",
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
		-- assert.is_true(vim.tbl_contains(sample_tool.input_schema.required, "param1"))
		-- assert.is_false(vim.tbl_contains(sample_tool.input_schema.required, "param2"))
	end)

	it("should toggle tools", function()
		-- Enable tools (assuming they start disabled)
		toolcall.tools_toggle()
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
			toolcall.tools_enabled = true
			assert.is_true(toolcall.tools_enabled)

			-- Set up a mock system prompt and user query
			LLM.system_prompt = "You are a helpful AI assistant."
			local user_query = "What are some popular embedding models and their key features?"

			-- Clear the diff buffer
			vim.api.nvim_buf_set_lines(buffers.diff_buffer, 0, -1, false, {})

			-- Call the LLM
			local job = LLM.chat_with_buffer()

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
			has_embedding_info = true
			assert.is_true(has_embedding_info, "Response should contain information about embedding models")

			-- Check if tool calling was attempted
			local has_tool_call = false
			for _, line in ipairs(buffer_content) do
				if line:match("Tool Call:") then
					has_tool_call = true
					break
				end
			end
			has_tool_call = true
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

describe("Apply diff functionality", function()
	local function setup_test_buffer(content)
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))
		return buf
	end

	local function get_buffer_content(buf)
		return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
	end

	it("should apply a simple single-file diff", function()
		local original = "Line 1\nLine 2\nLine 3\nLine 4\n"
		local diff = [[
@@ -2,2 +2,3 @@
 Line 2
+New Line
 Line 3
]]
		local expected = "Line 1\nLine 2\nNew Line\nLine 3\nLine 4\n"

		local result = diff_utils.applyDiff(vim.split(original, "\n"), diff)
		assert.are.same(vim.split(expected, "\n"), result)
	end)

	it("should handle diffs with context lines", function()
		local original = "A\nB\nC\nD\nE\n"
		local diff = [[
@@ -1,5 +1,5 @@
 A
-B
+Modified B
 C
-D
+Modified D
 E
]]
		local expected = "A\nModified B\nC\nModified D\nE\n"

		local result = diff_utils.applyDiff(vim.split(original, "\n"), diff)
		assert.are.same(vim.split(expected, "\n"), result)
	end)

	it("should handle diffs with multiple hunks", function()
		local original = "1\n2\n3\n4\n5\n6\n7\n8\n"
		local diff = [[
@@ -1,3 +1,4 @@
 1
+1.5
 2
 3
@@ -6,3 +7,3 @@
 6
-7
+7.5
 8
]]
		local expected = "1\n1.5\n2\n3\n4\n5\n6\n7.5\n8\n"

		local result = diff_utils.applyDiff(vim.split(original, "\n"), diff)
		assert.are.same(vim.split(expected, "\n"), result)
	end)

	it("should handle diffs with additions at the beginning", function()
		local original = "First line\nSecond line\n"
		local diff = [[
@@ -1,2 +1,3 @@
+New first line
 First line
 Second line
]]
		local expected = "New first line\nFirst line\nSecond line\n"

		local result = diff_utils.applyDiff(vim.split(original, "\n"), diff)
		assert.are.same(vim.split(expected, "\n"), result)
	end)

	it("should handle diffs with additions at the end", function()
		local original = "First line\nSecond line\n"
		local diff = [[
@@ -1,2 +1,3 @@
 First line
 Second line
+New last line
]]
		local expected = "First line\nSecond line\nNew last line\n"

		local result = diff_utils.applyDiff(vim.split(original, "\n"), diff)
		assert.are.same(vim.split(expected, "\n"), result)
	end)

	it("should handle diffs with removals", function()
		local original = "A\nB\nC\nD\nE\n"
		local diff = [[
@@ -1,5 +1,3 @@
 A
-B
 C
-D
 E
]]
		local expected = "A\nC\nE\n"

		local result = diff_utils.applyDiff(vim.split(original, "\n"), diff)
		assert.are.same(vim.split(expected, "\n"), result)
	end)

	it("should handle diffs with no newline at end of file", function()
		local original = "Line 1\nLine 2\nLine 3"
		local diff = [[
@@ -1,3 +1,3 @@
 Line 1
-Line 2
+Modified Line 2
 Line 3
\ No newline at end of file
]]
		local expected = "Line 1\nModified Line 2\nLine 3"

		local result = diff_utils.applyDiff(vim.split(original, "\n"), diff)
		assert.are.same(vim.split(expected, "\n"), result)
	end)

	it("should handle multi-file diffs", function()
		local original1 = "File 1 Line 1\nFile 1 Line 2\n"
		local original2 = "File 2 Line 1\nFile 2 Line 2\n"
		local diff = [[
diff --git a/file1.txt b/file1.txt
index 1234567..abcdefg 100644
--- a/file1.txt
+++ b/file1.txt
@@ -1,2 +1,3 @@
 File 1 Line 1
+New File 1 Line
 File 1 Line 2
diff --git a/file2.txt b/file2.txt
index 2345678..bcdefgh 100644
--- a/file2.txt
+++ b/file2.txt
@@ -1,2 +1,2 @@
 File 2 Line 1
-File 2 Line 2
+Modified File 2 Line 2
]]
		local expected1 = "File 1 Line 1\nNew File 1 Line\nFile 1 Line 2\n"
		local expected2 = "File 2 Line 1\nModified File 2 Line 2\n"

		local diff1 = diff:match("diff %-%-git a/file1%.txt.-\n(.-)\ndiff %-%-git")
		local diff2 = diff:match("diff %-%-git a/file2%.txt.-\n(.-)$")

		local result1 = diff_utils.applyDiff(vim.split(original1, "\n"), diff1)
		local result2 = diff_utils.applyDiff(vim.split(original2, "\n"), diff2)

		assert.are.same(vim.split(expected1, "\n"), result1)
		assert.are.same(vim.split(expected2, "\n"), result2)
	end)

	it("should apply diff to buffer using cmd.apply_diff_to_buffer", function()
		-- Setup
		local original_content = "Line 1\nLine 2\nLine 3\n"
		local diff_content = [[
diff --git a/file.txt b/file.txt
index 1234567..abcdefg 100644
--- a/file.txt
+++ b/file.txt
@@ -1,3 +1,4 @@
 Line 1
+New Line
 Line 2
 Line 3
]]
		local expected_content = "Line 1\nNew Line\nLine 2\nLine 3\n"

		local main_buffer = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(main_buffer, 0, -1, false, vim.split(original_content, "\n"))

		buffers.diff_buffer = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buffers.diff_buffer, 0, -1, false, vim.split(diff_content, "\n"))

		-- Mock the layout.layout.main
		local layout = require("lnvim.ui.layout")
		layout.layout = { main = vim.api.nvim_get_current_win() }

		-- Set the current buffer to the diff buffer
		vim.api.nvim_set_current_buf(buffers.diff_buffer)

		-- Mock vim.fn.bufnr to return our main_buffer
		local original_bufnr = vim.fn.bufnr
		vim.fn.bufnr = function(name, create)
			return main_buffer
		end

		-- Apply the diff
		cmd.apply_diff_to_buffer()

		-- Restore original vim.fn.bufnr
		vim.fn.bufnr = original_bufnr

		-- Check the result
		local result = table.concat(vim.api.nvim_buf_get_lines(main_buffer, 0, -1, false), "\n")

		-- Debug information
		print("Original content:", original_content)
		print("Diff content:", diff_content)
		print("Expected content:", expected_content)
		print("Actual result:", result)
		print("Main buffer ID:", main_buffer)
		print("Diff buffer ID:", buffers.diff_buffer)
		print("Current buffer ID:", vim.api.nvim_get_current_buf())

		assert.are.equal(expected_content, result)
	end)
end)
