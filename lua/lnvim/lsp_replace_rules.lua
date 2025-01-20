local M = {}
local buffers = require("lnvim.ui.buffers")
local editor = require("lnvim.ui.editor")

-- Filetype specific rules
M.replace_rules = {
    lua = require("lnvim.lsp_rules.lua"),
    python = require("lnvim.lsp_rules.python"),
    zig = require("lnvim.lsp_rules.zig"),
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
                    "%s%s [%s](%d) %s", 
                    string.rep("  ", indent), 
                    symbol.name,
                    kind_name,
                    kind_num,
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
