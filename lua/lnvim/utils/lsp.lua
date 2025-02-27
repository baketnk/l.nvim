local M = {}
-- Helper function to show a picker for symbol selection
function M.show_symbol_picker(matches, callback)
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    pickers.new({}, {
        prompt_title = "Select Symbols to Replace",
        finder = finders.new_table {
            results = matches,
            entry_maker = function(entry)
                -- Process source symbol
                local source_symbol = entry.identifier
                local source_path = source_symbol.path or source_symbol.name

                -- Truncate source symbol text if necessary
                local source_symbol_text = source_symbol.text or "Unknown source"
                if #source_symbol_text > 50 then
                    source_symbol_text = source_symbol_text:sub(1, 50) .. "..."
                end

                -- Process destination symbol
                local dest_symbol = entry.symbol
                local dest_range = dest_symbol.range
                local dest_range_str = string.format(
                    "(%d,%d)-(%d,%d)",
                    dest_range.start.line + 1,
                    dest_range.start.character + 1,
                    dest_range['end'].line + 1,
                    dest_range['end'].character + 1
                )
                local dest_kind_num = dest_symbol.kind
                local dest_kind_name = vim.lsp.protocol.SymbolKind[dest_kind_num] or "Unknown"

                -- Construct the display string
                local display = string.format(
                    "%s(...) -> %s [dest: %s, %s]",
                    source_path,
                    entry.path,
                    dest_range_str,
                    dest_kind_name
                )

                return {
                    value = entry,
                    display = display,
                    ordinal = entry.path,
                }
            end
        },
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                local selections = {}
                
                -- Get current selection
                local selection = action_state.get_selected_entry()
                if selection then
                    table.insert(selections, selection)
                end
                
                -- Try to get multi-selections if available
                local current_picker = action_state.get_current_picker(prompt_bufnr)
                if current_picker then
                    local multi_selections = current_picker:get_multi_selection()
                    if multi_selections and #multi_selections > 0 then
                        selections = multi_selections
                    end
                end
                
                -- Close the picker first to avoid the error
                actions.close(prompt_bufnr)
                
                -- Then call the callback with the selections
                if #selections > 0 then
                    callback(selections)
                else
                    vim.notify("No symbols selected", vim.log.levels.WARN)
                    callback(nil)
                end
            end)
            
            return true
        end,
        multi_select = true,
    }):find()
end


return M
