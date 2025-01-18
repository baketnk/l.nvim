local M = {}
local buffers = require("lnvim.ui.buffers")
local editor = require("lnvim.ui.editor")

-- Filetype specific rules
M.replace_rules = {
    zig = {
   parse_identifiers = function(contents)
            local parser = vim.treesitter.get_string_parser(contents, "zig")
            local tree = parser:parse()[1]
            local root = tree:root()

            local symbols = {}

            local function visit_node(node)
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
                        
                        table.insert(symbols, { name = name, kind = kind, node = node, text = node_text })
                    end
                end
                
                for child in node:iter_children() do
                    visit_node(child)
                end
            end

            visit_node(root)

            return symbols
        end,


        find_symbols = function(uri, identifiers, callback)
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
                            return {
                                value = entry,
                                display = entry.path,
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
        end,


        replace_symbols = function(bufnr, symbols, new_text)
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
    }
}


function M.replace_with_codeblock()
    local layout = require("lnvim.ui.layout").get_layout()
    local main_buffer = vim.api.nvim_win_get_buf(layout.main)
    local filetype = vim.bo[main_buffer].filetype
    local handler = M.replace_rules[filetype]

    if not handler then
        vim.notify("No replacement handler for filetype: " .. filetype, vim.log.levels.ERROR)
        return
    end

    -- Get current codeblock content
    local lines = editor.get_current_codeblock_contents(buffers.diff_buffer)
    if not lines or #lines == 0 then
        vim.notify("No codeblock selected", vim.log.levels.ERROR)
        return
    end

    -- Parse the identifiers from the code
    local identifiers = handler.parse_identifiers(table.concat(lines, "\n"))
    if not identifiers or #identifiers == 0 then
        vim.notify("Could not find symbols to replace in codeblock", vim.log.levels.ERROR)
        return
    end

    print("Parsed identifiers:", vim.inspect(identifiers))  -- Debug log

    local main_buffer_uri = vim.uri_from_bufnr(main_buffer)
    handler.find_symbols(main_buffer_uri, identifiers, function(symbols)
        if not symbols or #symbols == 0 then
            vim.notify("Could not find original symbols", vim.log.levels.ERROR)
            return
        end

        handler.replace_symbols(main_buffer, symbols, identifiers)
    end)
end


-- In lsp_replace_rules.lua
function M.dump_document_symbols_to_buffer()
    local layout = require("lnvim.ui.layout").get_layout()
    local main_buffer = vim.api.nvim_win_get_buf(layout.main)
    local uri = vim.uri_from_bufnr(main_buffer)

    -- Create a new buffer for symbols
    local symbols_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(symbols_buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(symbols_buf, 'bufhidden', 'wipe')
    vim.api.nvim_buf_set_name(symbols_buf, 'LSP Symbols')

    local params = {
        textDocument = { uri = uri },
    }

    vim.lsp.buf_request(main_buffer, 
        'textDocument/documentSymbol',
        params,
        function(err, result, ctx, config)
            if err then
                vim.api.nvim_buf_set_lines(symbols_buf, 0, -1, false, 
                    {"Error getting symbols:", vim.inspect(err)})
                return
            end

            local lines = {"LSP Document Symbols", "==================", ""}

            -- Helper function to format a symbol
            local function format_symbol(symbol, indent)
                local kind_num = symbol.kind
                local kind_name = vim.lsp.protocol.SymbolKind[kind_num] or "Unknown"

                local range = symbol.range
                local range_str = string.format(
                    "(%d,%d)-(%d,%d)", 
                    range.start.line + 1, 
                    range.start.character + 1,
                    range["end"].line + 1, 
                    range["end"].character + 1
                )

                return string.format(
                    "%s%s [%s] %s", 
                    string.rep("  ", indent), 
                    symbol.name,
                    kind_name,
                    range_str
                )
            end

            -- Recursive function to process nested symbols
            local function process_symbols(symbols, indent)
                for _, symbol in ipairs(symbols) do
                    table.insert(lines, format_symbol(symbol, indent))
                    if symbol.children then
                        process_symbols(symbol.children, indent + 1)
                    end
                end
            end

            process_symbols(result, 0)

            -- Set the buffer content
            vim.api.nvim_buf_set_lines(symbols_buf, 0, -1, false, lines)

            -- Switch the main window to this buffer
            vim.api.nvim_win_set_buf(layout.main, symbols_buf)
        end
    )
end

return M
