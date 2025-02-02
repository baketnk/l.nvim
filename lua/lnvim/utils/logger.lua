-- utils/logger.lua (new file)
local M = {}


M.debug_mode = false

function M.setup()
    local state = require("lnvim.state")
    local log_dir = state.project_lnvim_dir .. "/debug_logs"
    if vim.fn.isdirectory(log_dir) == 0 then
        vim.fn.mkdir(log_dir, "p")
    end
    M.log_file = log_dir .. "/cache_debug.log"
end

-- Add toggle function
function M.toggle_debug_mode()
    M.debug_mode = not M.debug_mode
    local status = M.debug_mode and "enabled" or "disabled"
    vim.notify("Developer debug logging " .. status, vim.log.levels.INFO)
end

-- Add development logging function
function M.dev_log(message, category)
    if not M.debug_mode then
        return
    end

    if not M.log_file then
        M.setup()
    end

    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local log_line = string.format("[%s] [%s] %s\n",
        timestamp,
        category or "DEV",
        type(message) == "string" and message or vim.inspect(message)
    )

    local file = io.open(M.log_file, "a")
    if file then
        file:write(log_line)
        file:close()
    end
end

function M.log(message, level)
    if not M.log_file then
        M.setup()
    end
    
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local log_line = string.format("[%s] [%s] %s\n", 
        timestamp, 
        level or "INFO", 
        type(message) == "string" and message or vim.inspect(message)
    )
    
    local file = io.open(M.log_file, "a")
    if file then
        file:write(log_line)
        file:close()
    end
end

return M
