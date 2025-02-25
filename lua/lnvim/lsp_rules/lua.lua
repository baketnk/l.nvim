local M = {}

local lsp_helpers = require("lnvim.utils.lsp")
function M.parse_identifiers(contents)
   local parser = vim.treesitter.get_string_parser(contents, "lua")
   local tree = parser:parse()[1]
   local root = tree:root()

   local symbols = {}

   local function visit_node(node, path, context)
      local node_type = node:type()

      if node_type == "function_declaration" or
          node_type == "local_function_declaration" or
          node_type == "assignment" or
          node_type == "dot_index_expression" then
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
            elseif name_node and name_node:type() == "dot_index_expression" then
               -- Handle  `function M.func_name()`
               local table_name = vim.treesitter.get_node_text(name_node:child(0), contents)
               local field_name = vim.treesitter.get_node_text(name_node:child(2), contents)
               local full_path = table_name .. "." .. field_name

               table.insert(symbols, {
                  name = field_name,
                  kind = "Function",
                  node = node,
                  text = vim.treesitter.get_node_text(node, contents),
                  path = full_path
               })
            end
         elseif node_type == "dot_index_expression" then
            -- Handle M.function_name = function() ... pattern
            local parent = node:parent()
            if parent and parent:type() == "assignment" then
               local table_name = vim.treesitter.get_node_text(node:child(0), contents)
               local field_name = vim.treesitter.get_node_text(node:child(2), contents)

               -- Check if the right side is a function
               local right = parent:named_child(1)
               if right and right:type() == "function_definition" then
                  local full_path = table_name .. "." .. field_name

                  table.insert(symbols, {
                     name = field_name,
                     kind = "Function",
                     node = parent,
                     text = vim.treesitter.get_node_text(parent, contents),
                     path = full_path
                  })
               end
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
      Function = 12, -- Function
      Variable = 13, -- Variable
   }
   local bufnr = vim.uri_to_bufnr(uri)

   -- Removed print statements for uri and identifiers

   local symbols = vim.lsp.buf_request_sync(bufnr,
      'textDocument/documentSymbol',
      params,
      1000
   )

   -- Improved error handling for LSP response
   if not symbols or #symbols == 0 then
      vim.notify("No response from LSP server for document symbols", vim.log.levels.ERROR)
      return callback(nil)
   end

   -- Debug output for the LSP response
   vim.print("LSP Symbol Response:", vim.inspect(symbols))

   local matches = {}

   local function search_symbols(symbol_list, parent_path)
      for _, symbol in ipairs(symbol_list or {}) do
         local current_path = parent_path and (parent_path .. "." .. symbol.name) or symbol.name
         -- Handle module prefix in symbol.name (e.g., "M.some_function" -> "some_function")
         local symbol_name = symbol.name:match("[^.]+$") or symbol.name -- Get last part after dot

         for _, identifier in ipairs(identifiers) do
            if identifier.is_module_function then
               -- Module function: match name and ensure path starts with "M."
               if symbol_name == identifier.name and current_path:match("^M%.") then
                  table.insert(matches, {
                     symbol = symbol,
                     path = current_path,
                     identifier = identifier
                  })
               end
            else
               -- Regular matching: try both name and path
               if symbol_name == identifier.name or current_path == identifier.path then
                  if symbol.kind == kind_map[identifier.kind] then
                     table.insert(matches, {
                        symbol = symbol,
                        path = current_path,
                        identifier = identifier
                     })
                  end
               end
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
      else
         vim.print("Invalid result structure:", vim.inspect(result))
      end
   end

   if #matches == 0 then
      -- More detailed error message
      vim.notify("Could not find matching symbols. Check the console for debug info.", vim.log.levels.ERROR)
      callback(nil)
   else
      lsp_helpers.show_symbol_picker(matches, callback)
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
