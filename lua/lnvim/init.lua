local M = {}
-- module references
local cfg = require("lnvim.cfg")
local state = require("lnvim.state")

-- local required_fields = { "model_id", "model_type", "api_url", "api_key" }
function M.add_model(model)
	table.insert(state.models, cfg.validate_model(model))
end

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
