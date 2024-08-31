local M = {}
local Job = require("plenary.job")
local plenary_curl = require("plenary.curl")
M.tools_available = {}
M.tools_functions = {}

local function url_encode(str)
	if str then
		str = string.gsub(str, "\n", "\r\n")
		str = string.gsub(str, "([^%w %-%_%.%~])", function(c)
			return string.format("%%%02X", string.byte(c))
		end)
		str = string.gsub(str, " ", "+")
	end
	return str
end

function M.add_tool(opts)
	local tool = {
		name = opts.name,
		description = opts.description,
		input_schema = {
			type = "object",
			properties = {},
			required = {},
		},
	}

	for _, arg in ipairs(opts.input_schema.properties) do
		tool.input_schema.properties[arg.name] = {
			type = arg.type,
			description = arg.desc,
		}
		if arg.required then
			table.insert(tool.input_schema.required, arg.name)
		end
	end

	M.tools_available[opts.name] = tool
	M.tools_functions[opts.name] = opts.func
	return tool
end

M.tools_enabled = true
function M.tools_toggle()
	M.tools_enabled = not M.tools_enabled
	vim.notify("tool calling is now " .. vim.inspect(M.tools_enabled))
end

local allowed_commands = require("lnvim.allowed_commands")

local shell_enabled = false
if shell_enabled then
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
			local full_command =
				string.format("docker exec %s /bin/bash -c '%s'", vim.g.llm_container_name, args.command)
			local handle = io.popen(full_command)
			local result = handle:read("*a")
			handle:close()
			return result
		end,
	})
end

local net_enabled = true
if net_enabled then
	M.add_tool({
		name = "search_huggingface_models",
		description = "Searches Hugging Face for models based on various criteria",
		input_schema = {
			type = "object",
			properties = {
				search = { type = "string", description = "Filter based on substrings for repos and their usernames" },
				author = { type = "string", description = "Filter models by an author or organization" },
				filter = { type = "string", description = "Filter based on tags" },
				sort = { type = "string", description = "Property to use when sorting (e.g., downloads, author)" },
				direction = {
					type = "string",
					description = "Direction in which to sort (-1 for descending, 1 for ascending)",
				},
				limit = { type = "integer", description = "Limit the number of models fetched" },
				full = { type = "boolean", description = "Whether to fetch most model data" },
				config = { type = "boolean", description = "Whether to also fetch the repo config" },
			},
			required = { "search" },
		},
		func = function(args)
			local api_key = os.getenv("HUGGINGFACE_API_KEY")
			if not api_key then
				return "Error: HUGGINGFACE_API_KEY environment variable not set"
			end

			local base_url = "https://huggingface.co/api/models"
			local query_params = {}

			-- Add all provided parameters to the query
			for key, value in pairs(args) do
				if key ~= "search" then -- 'search' is handled separately
					table.insert(query_params, key .. "=" .. url_encode(tostring(value)))
				end
			end

			-- Always add the search parameter
			table.insert(query_params, "search=" .. url_encode(args.search))

			local url = base_url .. "?" .. table.concat(query_params, "&")

			local response = plenary_curl.get(url, {

				headers = {
					Authorization = "Bearer " .. api_key,
					Accept = "application/json",
				},
			})

			if response.status ~= 200 then
				return string.format(
					"Error: HTTP request failed with code %d. Body: %s",
					response.status,
					response.body
				)
			end

			local success, response_json = pcall(vim.json.decode, response.body)
			if not success then
				return "Error: Failed to parse JSON response. Raw response: " .. response.body
			end

			if type(response_json) ~= "table" or #response_json == 0 then
				return "No models found matching the criteria."
			end

			local result = "Hugging Face Models:\n\n"
			for i, model in ipairs(response_json) do
				result = result
					.. string.format(
						"%d. %s\n   Author: %s\n   Description: %s\n   Downloads: %d\n   Likes: %d\n\n",
						i,
						model.modelId,
						model.author,
						model.description,
						model.downloads,
						model.likes
					)

				-- Add extra information if 'full' or 'config' was requested
				if args.full then
					result = result .. "   Tags: " .. table.concat(model.tags, ", ") .. "\n"
					result = result .. "   Last Modified: " .. model.lastModified .. "\n"
				end
				if args.config and model.config then
					result = result .. "   Config: " .. vim.inspect(model.config) .. "\n"
				end
				result = result .. "\n"
			end

			return result
		end,
	})
end

return M
