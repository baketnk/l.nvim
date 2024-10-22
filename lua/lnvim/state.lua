local M = {}

local _state = {
	files = {},
	system_prompt = "",
	status = "Idle",
	current_model = nil,
	models = {},
	llm_log_path = nil,
	paste_mark = nil,
	-- Add these new fields
	autocomplete = {},
	autocomplete_model = {},
	max_prompt_length = nil,
	default_prompt_path = nil,
	project_root = nil,
	project_lnvim_dir = nil,
	keymap_prefix = nil,
	mark = nil,
}
-- List of keys that should trigger update_summary when changed
local update_triggers = {
	"files",
	"system_prompt",
	"status",
	"current_model",
}

-- DO NOT CALL FROM OUTSIDE THE MODEL. THIS IS CALLED WHEN UPDATING CERTAIN TRIGGER KEYS.
local function update_summary()
	local layout = require("lnvim.ui.layout")
	if layout.get_layout() then
		layout.update_summary()
	end
end

local state_proxy = {}
local state_mt = {
	__index = _state,
	__newindex = function(_, key, value)
		if _state[key] ~= value then
			_state[key] = value
			if vim.tbl_contains(update_triggers, key) then
				update_summary()
			end
		end
	end,
}

setmetatable(state_proxy, state_mt)

function M.get_summary()
	local file_count = 0
	local lsp_count = 0
	local has_file_list = ""
	for _, file in ipairs(_state.files) do
		if file:match("^@lsp:") then
			lsp_count = lsp_count + 1
		elseif file == "@project-file-list" then
			has_file_list = "File List, "
		else
			file_count = file_count + 1
		end
	end

	local system_prompt_preview = _state.system_prompt:sub(1, 50) .. (_state.system_prompt:len() > 50 and "..." or "")

	local model_info = _state.current_model and _state.current_model.model_id or "No model selected"

	return string.format(
		"Include: %s%d files, %d LSPs\n" .. "System: %s\n" .. "Status: %s\n" .. "Model: %s",
		has_file_list,
		file_count,
		lsp_count,
		system_prompt_preview,
		_state.status,
		model_info
	)
end

-- Expose the proxy object instead of the raw state
return setmetatable(M, {
	__index = state_proxy,
	__newindex = function(_, key, value)
		state_proxy[key] = value
	end,
})
