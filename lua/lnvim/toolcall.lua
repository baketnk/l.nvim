local M = {}

M.tools_available = {}

function M.add_tool(opts)
	local tool = {
		name = opts.name,
		description = opts.desc,
		func = opts.func,
		parameters = {
			type = "object",
			properties = {},
			required = {},
		},
	}
	local props = {}
	local required = {}
	for _, arg in ipairs(opts.properties) do
		props[arg.name] = {
			type = arg.type,
			description = arg.desc,
		}
		if arg.required then
			required[#required + 1] = arg.name
		end
	end
	tool.parameters.properties = props
	M.tools_available[opts.name] = tool
	return tool
end

M.tools_enabled = false

local allowed_commands = require("lnvim.allowed_commands")

M.add_tool({
	name = "shell_command",
	desc = "runs basic shell commands in the Docker container",
	properties = {
		{
			name = "command",
			type = "string",
			desc = "shell command to execute (allowed: " .. table.concat(allowed_commands, ", ") .. ")",
			required = true,
		},
	},
	func = function(args)
		local command = args.command:match("^%s*(%S+)")
		if not vim.tbl_contains(allowed_commands, command) then
			return "Command not allowed: " .. command
		end
		local full_command = string.format("docker exec %s /bin/bash -c '%s'", vim.g.llm_container_name, args.command)
		local handle = io.popen(full_command)
		local result = handle:read("*a")
		handle:close()
		return result
	end,
})
return M
