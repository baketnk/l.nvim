local M = {}

-- module references
local LLM = require("lnvim.llm")
local primitive = require("lnvim.utils.primitive")
local editor = require("lnvim.ui.editor")
local layout = require("lnvim.ui.layout")
local constants = require("lnvim.constants")
local cmd = require("lnvim.cmd")
local cfg = require("lnvim.cfg")
local Job = require("plenary.job")

local function setup_docker()
	local handle = io.popen("pwd")
	local cwd = handle:read("*a"):gsub("\n", "")
	handle:close()

	local container_name = "llm_sandbox_" .. cwd:gsub("/", "_")
	vim.g.llm_container_name = container_name

	local setup_cmd = string.format("bash %s/llm_container.sh %s", vim.fn.stdpath("config"), container_name)

	Job:new({
		command = "bash",
		args = { "-c", setup_cmd },
		on_exit = function(j, return_val)
			if return_val == 0 then
				print("Docker container setup complete")
			else
				print("Docker container setup failed")
			end
		end,
	}):start()
end

local function cleanup_docker()
	if vim.g.llm_container_name then
		local cleanup_cmd =
			string.format("docker stop %s && docker rm %s", vim.g.llm_container_name, vim.g.llm_container_name)
		vim.fn.jobstart(cleanup_cmd, {
			on_exit = function(_, exit_code)
				if exit_code == 0 then
					print("Docker container cleaned up")
				else
					print("Docker container cleanup failed")
				end
			end,
		})
	end
end

function M.setup(_opts)
	-- setup_docker()
	cfg.setup(_opts)
	vim.cmd([[
        augroup LLMDockerCleanup
        autocmd!
        autocmd VimLeavePre * lua require('lnvim').cleanup()
        augroup END
    ]])
end
function M.cleanup()
	-- cleanup_docker()
end
return M
