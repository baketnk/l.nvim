local lnvim = require("lnvim")

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

		-- sys prompt function
		--
		-- see if default config runs LLM without error
		lnvim.chat_with_buffer_default_system()

		-- TODO: test pasting I guess
		--
		vim.notify("basic test passed")
		return true
	end)
end)
