local M = {}
local Job = require("plenary.job")

-- Execute a bash command
-- command: The bash command to execute
-- callback: Function to call with the command's output
-- error_callback: Function to call with error messages
function M.execute(command, callback, error_callback)
	Job:new({
		command = "/bin/bash",
		args = { "-c", command },
		on_exit = function(j, return_val)
			if return_val ~= 0 then
				error_callback("Bash command failed with exit code: " .. return_val)
				return
			end
			local output = table.concat(j:result(), "\n")
			callback(output)
		end,
		on_stderr = function(_, stderr)
			vim.schedule(function()
				vim.notify("Bash Error: " .. stderr, vim.log.levels.ERROR)
			end)
		end,
	}):start()
end

return M
