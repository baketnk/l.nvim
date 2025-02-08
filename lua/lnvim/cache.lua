-- cache.lua (new file)
local M = {}
local state = require("lnvim.state")
local logger = require("lnvim.utils.logger")

local telescope = require("telescope.builtin")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
-- Cache-only files are stored separately from regular files
-- They will always be included in cached segments when possible
state.cache_only_files = state.cache_only_files or {}

function M.select_cache_only_files()
    local helpers = require("lnvim.utils.helpers")
    
    local function on_select(selected_files)
        
    end
local existing_paths = state.files
	local selected_paths = {}

	local opts = {
		prompt_title = "Select files for caching",
		attach_mappings = function(prompt_bufnr, map)
			actions.select_default:replace(function()
				local current_picker = action_state.get_current_picker(prompt_bufnr)
				local multi_selections = current_picker:get_multi_selection()
				if #multi_selections > 0 then
					for _, select in ipairs(multi_selections) do
						table.insert(selected_paths, select.path)
					end
				else
					local selection = action_state.get_selected_entry()
					if selection then
						table.insert(selected_paths, selection.path)
					end
				end

				actions.close(prompt_bufnr)
            state.cache_only_files = selected_paths 
			end)
			return true
		end,
		multi = true,
		hidden = hidden,
		no_ignore = no_ignore,
	}
	if hidden then
		opts.find_command = { "rg", "--files", "--hidden", "-g", "!.git" }
	end

	telescope.find_files(opts)
end

-- Helper function to check if a file should be considered for caching
function M.should_cache_file(filepath)
    -- If it's in cache_only_files, always cache
    if vim.tbl_contains(state.cache_only_files, filepath) then
        logger.log(filepath .. " is in cache-only files")
        return true
    end
    
    -- Check if file is open in a buffer
    local bufnr = vim.fn.bufnr(filepath)
    if bufnr == -1 then
        -- File not in buffer, safe to cache
        logger.log(filepath .. " not in buffer, safe to cache")
        return true
    end
    
    -- Check modification time
    local mtime = vim.fn.getftime(filepath)
    local now = os.time()
    local diff = now - mtime
    
    -- If file hasn't been modified in 15 minutes, consider it for caching
    local should_cache = diff > (15 * 60)
    logger.log(string.format("%s last modified %d seconds ago, should%s cache", 
        filepath, diff, should_cache and "" or " not"))
    
    return should_cache
end

-- Get files organized by caching preference
function M.organize_files_for_caching()
    local files = state.files
    local cache_segments = {
        cache_only = {},
        cacheable = {},
        uncacheable = {}
    }
    
    for _, file in ipairs(files) do
        if vim.tbl_contains(state.cache_only_files, file) then
            table.insert(cache_segments.cache_only, file)
        elseif M.should_cache_file(file) then
            table.insert(cache_segments.cacheable, file)
        else
            table.insert(cache_segments.uncacheable, file)
        end
    end
    
    logger.log("Organized files for caching:", "DEBUG")
    logger.log(cache_segments)
    
    return cache_segments
end

return M
