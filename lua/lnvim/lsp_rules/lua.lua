-- lsp_rules/lua.lua

local M = {}

-- Parse identifiers from Lua code
function M.parse_identifiers(contents)
    local parser = vim.treesitter.get_string_parser(contents, "lua")
    local tree = parser:parse()[1]
    local root = tree:root()

    local symbols = {}

    local function visit_node(node, path, context)
        local node_type = node:type()
        if node_type == "function_declaration" or
           node_type == "local_function_declaration" or
           node_type == "assignment" then

            if node_type == "function_declaration" or node_type == "local_function_declaration" then
                local name_node = node:named_child(0)
                if name_node and name_node:type() == "identifier" then
                    local name = vim.treesitter.get_node_text(name_node, contents)
                    local node_text = vim.treesitter.get_node_text(node, contents)
                    local full_path = path ~= "" and (path .. "." .. name) or name

                    table.insert(symbols, {
                        name = name,
                        kind = "Function",
                        node = node,
                        text = node_text,
                        path = full_path
                    })
                end
            elseif node_type == "assignment" then
                local left = node:named_child(0)
                local right = node:named_child(1)

                if left and left:type() == "variable_list" then
                    for child in left:iter_children() do
                        if child:type() == "identifier" then
                            local name = vim.treesitter.get_node_text(child, contents)
                            local node_text = vim.treesitter.get_node_text(node, contents)
                            local full_path = path ~= "" and (path .. "." .. name) or name

                            local kind = "Variable"
                            if right and right:type() == "function_definition" then
                                kind = "Function"
                            end

                            table.insert(symbols, {
                                name = name,
                                kind = kind,
                                node = node,
                                text = node_text,
                                path = full_path
                            })
                        end
                    end
                end
            end
        end

        -- Handle other node types that might contain symbols
        if node_type == "chunk" then
            for child in node:iter_children() do
                visit_node(child, path, context)
            end
            return
        end

        -- Handle nodes that don't need further processing
        if node_type == "comment" or node_type == "string" then
            return
        end

        -- Default case: process children
        for child in node:iter_children() do
            visit_node(child, path, context)
        end
    end

    -- Initial call
    visit_node(root, "", "")

    return symbols
end

-- Find symbols in the current buffer
function M.find_symbols(uri, identifiers, callback)
    local params = {
        textDocument = { uri = uri },
    }
    local kind_map = {
        Function = 12,  -- Function
        Variable = 13,  -- Variable
    }
    local bufnr = vim.uri_to_bufnr(uri)

    vim.print("LSP Request URI:", uri)  -- Debug log
    vim.print("Looking for symbols:", vim.inspect(identifiers))  -- Debug log

    local symbols = vim.lsp.buf_request_sync(bufnr,
        'textDocument/documentSymbol',
        params,
        1000
    )

    local matches = {}

    local function search_symbols(symbol_list, parent_path)
        for _, symbol in ipairs(symbol_list or {}) do
            local current_path = parent_path and (parent_path .. "." .. symbol.name) or symbol.name

            for _, identifier in ipairs(identifiers) do
                if symbol.kind == kind_map[identifier.kind] and
                   symbol.name == identifier.name then
                    table.insert(matches, {
                        symbol = symbol,
                        path = current_path,
                        identifier = identifier
                    })
                end
            end

            -- Recursively search children
            if symbol.children then
                search_symbols(symbol.children, current_path)
            end
        end
    end

    for _, result in ipairs(symbols or {}) do
        search_symbols(result.result)
    end

    if #matches == 0 then
        callback(nil)
    else
        -- Use telescope for selection
        local pickers = require "telescope.pickers"
        local finders = require "telescope.finders"
        local conf = require("telescope.config").values
        local actions = require "telescope.actions"
        local action_state = require "telescope.actions.state"

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
                    local current_picker = action_state.get_current_picker(prompt_bufnr)
                    local multi_selections = current_picker:get_multi_selection()
                    if #multi_selections > 0 then
                        callback(multi_selections)
                    else
                        local selection = action_state.get_selected_entry()
                        if selection then
                            callback({selection})
                        else
                            callback(nil)
                        end
                    end

                    actions.close(prompt_bufnr)
                end)
                return true
            end,
            multi_select = true,
        }):find()
    end
end

-- Replace symbols in the buffer
function M.replace_symbols(bufnr, symbols, new_text)
    table.sort(symbols, function(a, b)
        local range_a = a.value.symbol.range
        local range_b = b.value.symbol.range
        return range_a.start.line > range_b.start.line
    end)

    for _, symbol in ipairs(symbols) do
        if symbol and symbol.value and symbol.value.symbol and symbol.value.symbol.range then
            local range = symbol.value.symbol.range
            local identifier = symbol.value.identifier

            -- Find the corresponding text in the new_text
            local matching_symbol = nil
            for _, parsed_symbol in ipairs(new_text) do
                if parsed_symbol.name == identifier.name and parsed_symbol.kind == identifier.kind then
                    matching_symbol = parsed_symbol
                    break
                end
            end

            if matching_symbol then
                vim.api.nvim_buf_set_text(
                    bufnr,
                    range.start.line,
                    range.start.character,
                    range['end'].line,
                    range['end'].character,
                    vim.split(matching_symbol.text, "\n")
                )
            else
                vim.notify("Could not find matching symbol for replacement: " .. identifier.name, vim.log.levels.WARN)
            end
        else
            vim.notify("Invalid symbol structure: " .. vim.inspect(symbol), vim.log.levels.ERROR)
        end
    end
end

return M
