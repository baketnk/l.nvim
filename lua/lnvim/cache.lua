-- cache.lua (new file)
local M = {}
local state = require("lnvim.state")
local logger = require("lnvim.utils.logger")

-- Cache-only files are stored separately from regular files
-- They will always be included in cached segments when possible
state.cache_only_files = state.cache_only_files or {}

function M.select_cache_only_files()
    local helpers = require("lnvim.utils.helpers")
    
    local function on_select(selected_files)
        state.cache_only_files = selected_files
        logger.log("Updated cache-only files: " .. vim.inspect(selected_files))
    end
    
    return helpers.select_files_for_prompt(false, false, on_select)
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
