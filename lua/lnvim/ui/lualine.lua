local M = {}

local state = require("lnvim.state")

function M.lnvim_status()
	return state.status
end

return M
