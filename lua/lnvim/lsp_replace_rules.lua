local M = {}
local buffers = require("lnvim.ui.buffers")
local editor = require("lnvim.ui.editor")
local modal = require("lnvim.ui.modal")

-- Filetype specific rules
M.replace_rules = {
   lua = require("lnvim.lsp_rules.lua"),
   python = require("lnvim.lsp_rules.python"),
   zig = require("lnvim.lsp_rules.zig"),
}

M.config = {
   show_diffs = true  -- Set to true by default, can be toggled
}

function M.generate_diff(original_lines, new_lines)
   -- Create temporary files for the diff
   local temp_original = vim.fn.tempname()
   local temp_modified = vim.fn.tempname()
   
   -- Write the content to the temporary files
   vim.fn.writefile(original_lines, temp_original)
   vim.fn.writefile(new_lines, temp_modified)
   
   -- Use external diff command with unified format
   local diff_cmd = "diff -u " .. vim.fn.shellescape(temp_original) .. " " .. vim.fn.shellescape(temp_modified)
   local diff_output = vim.fn.system(diff_cmd)
   
   -- Clean up temporary files
   vim.fn.delete(temp_original)
   vim.fn.delete(temp_modified)
   
   -- If there's no difference, provide a message
   if diff_output == "" then
      return "No differences found."
   end
   
   -- Process the diff output to replace temporary filenames with Original/Modified
   diff_output = diff_output:gsub("^%-%-%-[^\n]+", "--- Original")
   diff_output = diff_output:gsub("^%+%+%+[^\n]+", "+++ Modified", 1)
   
   -- Add a summary of line counts
   local summary = "# Original line count: " .. #original_lines .. "\n"
                 .. "# Modified line count: " .. #new_lines .. "\n\n"
   
   return summary .. diff_output
end


function M.toggle_diff_preview()
    M.config.show_diffs = not M.config.show_diffs
    local status = M.config.show_diffs and "enabled" or "disabled"
    vim.notify("Diff preview " .. status, vim.log.levels.INFO)
end

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
      if M.config.show_diffs then
   -- Get original content before replacement
   local original_lines = vim.api.nvim_buf_get_lines(main_buffer, 0, -1, false)

   -- Create a temporary buffer to simulate the changes
   local temp_buffer = vim.api.nvim_create_buf(false, true)
   vim.api.nvim_buf_set_lines(temp_buffer, 0, -1, false, original_lines)

   -- Apply the changes to the temporary buffer
   handler.replace_symbols(temp_buffer, symbols, identifiers)

   -- Get the modified content
   local modified_lines = vim.api.nvim_buf_get_lines(temp_buffer, 0, -1, false)

   -- Clean up the temporary buffer
   vim.api.nvim_buf_delete(temp_buffer, { force = true })

   -- Generate diff and show confirmation dialog
   local diff = M.generate_diff(original_lines, modified_lines)

   modal.modal_confirm({
      prompt = "Confirm symbol replacements?",
      diff_content = diff
   }, function(confirmed)
      if confirmed then
         -- Proceed with the actual replacement
         handler.replace_symbols(main_buffer, symbols, identifiers)
         vim.notify("Symbols replaced successfully", vim.log.levels.INFO)
      else
         vim.notify("Symbol replacement cancelled", vim.log.levels.INFO)
      end
   end)
else
   -- Directly perform the replacement without confirmation
   handler.replace_symbols(main_buffer, symbols, identifiers)
   vim.notify("Symbols replaced successfully", vim.log.levels.INFO)
end
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
               { "Error getting symbols:", vim.inspect(err) })
            return
         end

         local lines = { "LSP Document Symbols", "==================", "" }

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
