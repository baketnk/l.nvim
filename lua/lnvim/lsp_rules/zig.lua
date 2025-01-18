local M = {}

M.parse_identifiers = function(contents)
    local parser = vim.treesitter.get_string_parser(contents, "zig")
    local tree = parser:parse()[1]
    local root = tree:root()

    local symbols = {}

    local function visit_node(node, path, context)
    print("Visiting node:", node:type(), "with path:", path, "context:", context)  -- Debug log
    local node_type = node:type()
    if node_type == "function_declaration" or 
       node_type == "test_declaration" or 
       node_type == "variable_declaration" or 
       node_type == "constant_declaration" then
        
        local name_node = node:named_child(0)
        if name_node and name_node:type() == "identifier" then
            local name = vim.treesitter.get_node_text(name_node, contents)
            local kind = "Unknown"
            
            if node_type == "function_declaration" then
                kind = "Function"
            elseif node_type == "test_declaration" then
                kind = "Method"
            elseif node_type == "variable_declaration" then
                kind = "Variable"
            elseif node_type == "constant_declaration" then
                kind = "Constant"
            end
            
            -- Get the entire text of the node
            local node_text = vim.treesitter.get_node_text(node, contents)
            
            -- Construct the full path
            local full_path = path ~= "" and (path .. "." .. name) or name
            
            table.insert(symbols, { 
                name = name, 
                kind = kind, 
                node = node, 
                text = node_text, 
                path = full_path 
            })
        end
    end
    
    -- Check for container nodes
    if node_type == "struct_declaration" or node_type == "union_declaration" or node_type == "enum_declaration" then
        local parent = node:parent()
        local parent_type = parent:type()
        local container_name = ""
        
        -- Traverse up the tree until we find a variable_declaration or constant_declaration
        while parent and parent_type ~= "variable_declaration" and parent_type ~= "constant_declaration" do
            parent = parent:parent()
            if parent then
                parent_type = parent:type()
            end
        end
        
        if parent and (parent_type == "variable_declaration" or parent_type == "constant_declaration") then
            local name_node = parent:named_child(0)
            if name_node and name_node:type() == "identifier" then
                container_name = vim.treesitter.get_node_text(name_node, contents)
            end
        end
        
        local new_path = path ~= "" and (path .. "." .. container_name) or container_name
        local new_context = context .. "." .. container_name
        
        for child in node:iter_children() do
            visit_node(child, new_path, new_context)  -- Use new_path and new_context here
        end
        return  -- Don't process children twice
    end

    -- Handle other node types that might contain symbols
    if node_type == "block" or node_type == "source_file" then
        for child in node:iter_children() do
            visit_node(child, path, context)  -- Use path and context here
        end
        return
    end

    -- Handle nodes that don't need further processing
    if node_type == "comment" or node_type == "string_literal" or node_type == "number_literal" then
        return
    end

    -- Default case: process children
    for child in node:iter_children() do
        visit_node(child, path, context)  -- Use path and context here
    end
end

-- Initial call
  visit_node(root, "", "")

    return symbols
end



M.find_symbols = function(uri, identifiers, callback)
            local params = {
                textDocument = { uri = uri },
            }
            local kind_map = {
                Function = 12,    -- Function
                Method = 6,       -- Used for tests
                Struct = 23,      -- Struct
                Union = 21,       -- Union
                Enum = 10,       -- Enum
                Constant = 14,    -- Constant
                Variable = 13,    -- Variable
                Field = 8,        -- Field
                EnumMember = 22   -- EnumMember
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
                        if (symbol.kind == kind_map[identifier.kind] or symbol.kind == kind_map["Constant"] ) and
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
