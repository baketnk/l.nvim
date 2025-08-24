local M = {}
-- module references
local cfg = require("lnvim.cfg")
local state = require("lnvim.state")

local setup_called = false

-- local required_fields = { "model_id", "model_type", "api_url", "api_key" }
function M.add_model(model)
	if not setup_called then
		error("Call setup before calling add_model")
	else
		table.insert(state.models, cfg.validate_model(model))
	end
end

function M.setup(_opts)
	vim.print(setup_called)
	if setup_called then
		return
	end
	setup_called = true
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
