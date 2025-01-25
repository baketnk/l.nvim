local M = {}






-- check if it's available
local has_exec = "" -- which eleaf




function M.call_eleaf(args)
   if not has_exec then
      vim.notify_once("eleaf not available", vim.log.levels.ERROR, {})
      return
   end
end



return M
