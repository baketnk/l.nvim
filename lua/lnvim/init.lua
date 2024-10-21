local M = {}
-- module references
local cfg = require("lnvim.cfg")

function M.setup(_opts)
	cfg.setup(_opts)
	vim.cmd([[
        augroup LLMDockerCleanup
        autocmd!
        autocmd VimLeavePre * lua require('lnvim').cleanup()
        augroup END
    ]])
end
function M.cleanup()
	-- cleanup()
end
return M
