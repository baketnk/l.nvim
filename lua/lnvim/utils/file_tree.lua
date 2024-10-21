local M = {}

function M.get_project_files()
	local files = vim.fn.systemlist("git ls-files")
	if #files == 0 then
		-- If not a git repo or no files, fallback to rg
		files = vim.fn.systemlist("rg --files")
	end
	return files
end

function M.generate_file_tree(files)
	local tree = {}
	for _, file in ipairs(files) do
		local parts = vim.split(file, "/")
		local current = tree
		for i, part in ipairs(parts) do
			if i == #parts then
				table.insert(current, part)
			else
				current[part] = current[part] or {}
				current = current[part]
			end
		end
	end
	return tree
end

function M.tree_to_string(tree, prefix)
	prefix = prefix or ""
	local result = ""
	for k, v in pairs(tree) do
		if type(v) == "table" then
			result = result .. prefix .. k .. "/\n" .. M.tree_to_string(v, prefix .. "  ")
		else
			result = result .. prefix .. v .. "\n"
		end
	end
	return result
end

return M
