local lnvim = require("lnvim")
local match = require("luassert.match")
describe("basic nav", function()
	it("opens the drawer and does basic nav", function()
		lnvim.setup()
		lnvim.decide_with_magic()
		-- new L window is open with buffer
		local buf = vim.api.nvim_get_current_buf()
		assert(string.match(vim.api.nvim_buf_get_name(buf), lnvim.filetype_ext) ~= nil, "lslop buf missing")
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
		lnvim.editor.mark_codeblocks(buf)
		-- test cursor
		local cursor = vim.api.nvim_win_get_cursor(0)
		local next_cursor = nil

		lnvim.next_magic()
		next_cursor = vim.api.nvim_win_get_cursor(0)
		vim.print(vim.inspect(cursor))
		vim.print(vim.inspect(next_cursor))
		assert(cursor[1] ~= next_cursor[1], "cursor did not move on next1")
		cursor = next_cursor

		lnvim.next_magic()
		next_cursor = vim.api.nvim_win_get_cursor(0)
		assert(cursor[1] ~= next_cursor[1], "cursor did not move on next2")
		cursor = next_cursor

		lnvim.next_magic()
		next_cursor = vim.api.nvim_win_get_cursor(0)
		assert(cursor[1] ~= next_cursor[1], "cursor did not move on next3")
		cursor = next_cursor

		lnvim.previous_magic()
		next_cursor = vim.api.nvim_win_get_cursor(0)
		assert(cursor[1] ~= next_cursor[1], "cursor did not move on prev1")
		cursor = next_cursor

		lnvim.previous_magic()
		next_cursor = vim.api.nvim_win_get_cursor(0)
		assert(cursor[1] ~= next_cursor[1], "cursor did not move on prev2")

		-- cursor stuff work
		lnvim.set_system_prompt("hello world")
		assert(lnvim.LLM.system_prompt == "hello world")

		lnvim.paste_files_to_prompt({ ".gitignore" })
		local buffer_content = vim.api.nvim_buf_get_lines(lnvim.work_buffer, 0, -1, false)
		local has_the_line = false
		for _, line in ipairs(buffer_content) do
			if line:find("*.DS_Store") then
				has_the_line = true
				break
			end
		end
		assert(has_the_line)

		-- sys prompt function
		--
		-- see if default config runs LLM without error
		lnvim.chat_with_buffer_default_system()

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

		local editor = require("lnvim.editor")
		editor.mark_codeblocks(buf)

		local result = editor.yank_codeblock(buf)
		assert.is_true(result)

		local yanked = vim.fn.getreg('"')
		assert.are.equal("local x = 1\nprint(x)", yanked)
	end)
end)
