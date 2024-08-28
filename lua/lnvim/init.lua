local M = {}

-- module references
local LLM = require("lnvim.llm")
local primitive = require("lnvim.utils.primitive")
local editor = require("lnvim.ui.editor")
local layout = require("lnvim.ui.layout")
local constants = require("lnvim.constants")
local cmd = require("lnvim.cmd")
local cfg = require("lnvim.cfg")

--- Set up l.nvim with the options table given.
--- @param _opts table
function M.setup(_opts)
	return cfg.setup()
end

return M
