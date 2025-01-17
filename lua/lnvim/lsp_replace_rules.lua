local M = {}
local buffers = require("lnvim.ui.buffers")
local editor = require("lnvim.ui.editor")

-- Filetype specific rules
M.replace_rules = {
    zig = {
        parse_identifier = function(contents)
    -- Look for different types of declarations
    -- Function
    local fn_name = contents:match("pub%s+fn%s+([%w_]+)%s*%(") or
                   contents:match("fn%s+([%w_]+)%s*%(")
    if fn_name then
        return {
            name = fn_name,
            kind = "Function"  -- Matches SymbolKind.Function
        }
    end

    -- Test declaration
    local test_name = contents:match('test%s+"([^"]+)"') or
                    contents:match("test%s+'([^']+)'")
    if test_name then
        return {
            name = test_name,
            kind = "Method"  -- ZLS uses Method for tests as seen in document_symbol.zig
        }
    end

    -- Variable declarations
    local var_name = contents:match("pub%s+var%s+([%w_]+)%s*=")
    if var_name then
        return {
            name = var_name,
            kind = "Variable"
        }
    end

    -- Constants - need to check what follows the declaration
    local const_name = contents:match("pub%s+const%s+([%w_]+)%s*=%s*")
    if const_name then
        if contents:match("pub%s+const%s+" .. const_name .. "%s*=%s*struct%s*{") then
            return { name = const_name, kind = "Constant" }
        elseif contents:match("pub%s+const%s+" .. const_name .. "%s*=%s*union%s*{") then
            return { name = const_name, kind = "Constant" }
        elseif contents:match("pub%s+const%s+" .. const_name .. "%s*=%s*enum%s*{") then
            return { name = const_name, kind = "Constant" }
        else
            -- Other constants (numbers, strings, etc.)
            return { name = const_name, kind = "Constant" }
        end
    end

    return nil
end,

find_symbol = function(uri, identifier, callback)
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
    vim.print("Looking for symbol:", vim.inspect(identifier))  -- Debug log

    local symbols = vim.lsp.buf_request_sync(bufnr, 
        'textDocument/documentSymbol', 
        params, 
        1000
    )

    local matches = {}

    local function search_symbols(symbol_list, parent_path)
        for _, symbol in ipairs(symbol_list or {}) do
            local current_path = parent_path and (parent_path .. "." .. symbol.name) or symbol.name

            if symbol.kind == kind_map[identifier.kind] and
               symbol.name == identifier.name then
                table.insert(matches, {
                    symbol = symbol,
                    path = current_path
                })
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
    elseif #matches == 1 then
        callback( matches[1].symbol )
    else
        -- Use telescope for selection
        local pickers = require "telescope.pickers"
        local finders = require "telescope.finders"
        local conf = require("telescope.config").values
        local actions = require "telescope.actions"
        local action_state = require "telescope.actions.state"

        pickers.new({}, {
            prompt_title = "Select Symbol Location",
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
                    actions.close(prompt_bufnr)
                    local selection = action_state.get_selected_entry()
                    if selection then
                       callback(selection.value.symbol)
                    else
                       callback(nil)
                    end
                end)
                return true
            end,
        }):find()
    end
end,


        replace_symbol = function(bufnr, original_range, new_text)
            vim.api.nvim_buf_set_text(
                bufnr,
                original_range.start.line,
                original_range.start.character,
                original_range['end'].line,
                original_range['end'].character,
                vim.split(new_text, "\n")
            )
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

    -- Parse the identifier from the code
    local identifier = handler.parse_identifier(table.concat(lines, "\n"))
    if not identifier then
        vim.notify("Could not find symbol to replace in codeblock", vim.log.levels.ERROR)
        return
    end

    print("Parsed identifier:", vim.inspect(identifier))  -- Debug log


    local main_buffer_uri = vim.uri_from_bufnr(main_buffer)
    handler.find_symbol(main_buffer_uri, identifier, function(symbol)
        if not symbol then
            vim.notify("Could not find original symbol: " .. identifier.name, vim.log.levels.ERROR)
            return
        end
        handler.replace_symbol(main_buffer, symbol.range, table.concat(lines, "\n"))
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
