local M = {}

M.parse_identifiers = function(contents)
    local parser = vim.treesitter.get_string_parser(contents, "python")
    local tree = parser:parse()[1]
    local root = tree:root()
    
    local symbols = {}
    local current_class = nil
    
    local function visit_node(node, path, context)
        local node_type = node:type()
        
        if node_type == "class_definition" then
            local name_node = node:field("name")[1]
            if name_node then
                current_class = vim.treesitter.get_node_text(name_node, contents)
                path = current_class
            end
        end
        
        if node_type == "function_definition" then
            local name_node = node:field("name")[1]
            if name_node then
                local name = vim.treesitter.get_node_text(name_node, contents)
                local node_text = vim.treesitter.get_node_text(node, contents)
                local full_path
                
                local parameters = node:field("parameters")[1]
                local is_method = false
                if parameters then
                    local first_param = parameters:named_child(0)
                    if first_param and vim.treesitter.get_node_text(first_param, contents) == "self" then
                        is_method = true
                    end
                end
                
                if is_method then
                    if current_class then
                        full_path = current_class .. "." .. name
                    else
                        full_path = "*." .. name
                    end
                    
                    table.insert(symbols, {
                        name = name,
                        kind = "Method",
                        node = node,
                        text = node_text,
                        path = full_path,
                        inferred_class = not current_class
                    })
                else
                    full_path = name
                    table.insert(symbols, {
                        name = name,
                        kind = "Function",
                        node = node,
                        text = node_text,
                        path = full_path
                    })
                end
            end
        elseif node_type == "class_definition" then
            local name_node = node:field("name")[1]
            if name_node then
                local name = vim.treesitter.get_node_text(name_node, contents)
                local node_text = vim.treesitter.get_node_text(node, contents)
                
                table.insert(symbols, {
                    name = name,
                    kind = "Class",
                    node = node,
                    text = node_text,
                    path = name
                })
            end
        elseif node_type == "assignment" then
            local left = node:child(0)
            if left and left:type() == "identifier" then
                local name = vim.treesitter.get_node_text(left, contents)
                local node_text = vim.treesitter.get_node_text(node, contents)
                local full_path = current_class and (current_class .. "." .. name) or name
                
                table.insert(symbols, {
                    name = name,
                    kind = "Variable",
                    node = node,
                    text = node_text,
                    path = full_path
                })
            end
        end
        
        for child in node:iter_children() do
            visit_node(child, path, context)
        end
        
        if node_type == "class_definition" then
            current_class = nil
        end
    end
    
    visit_node(root, "", "")
    return symbols
end

M.find_symbols = function(uri, identifiers, callback)
    local params = {
        textDocument = { uri = uri },
    }

    local kind_map = {
        Function = 12,
        Method = 6,
        Class = 5,
        Variable = 13
    }

    local bufnr = vim.uri_to_bufnr(uri)
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
                local match = false

                if identifier.inferred_class and identifier.kind == "Method" then
                    if symbol.kind == kind_map.Method and symbol.name == identifier.name then
                        match = true
                    end
                else
                    if symbol.kind == kind_map[identifier.kind] and symbol.name == identifier.name then
                        match = true
                    end
                end

                if match then
                    table.insert(matches, {
                        symbol = symbol,
                        path = current_path,
                        identifier = identifier
                    })
                end
            end

            if symbol.children then
                search_symbols(symbol.children, current_path)
            end
        end
    end

    for _, result in ipairs(symbols or {}) do
        if result.result then
            search_symbols(result.result)
        end
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

M.replace_symbols = function(bufnr, symbols, new_text)
    table.sort(symbols, function(a, b)
        local range_a = a.value.symbol.range
        local range_b = b.value.symbol.range
        return range_a.start.line > range_b.start.line
    end)

    for _, symbol in ipairs(symbols) do
        if symbol and symbol.value and symbol.value.symbol and symbol.value.symbol.range then
            local range = symbol.value.symbol.range
            local identifier = symbol.value.identifier

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
