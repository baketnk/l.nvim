-- lua/lnvim/exa.lua
local M = {}
local Job = require("plenary.job")
local state = require("lnvim.state")
local buffers = require("lnvim.ui.buffers")
local logger = require("lnvim.utils.logger")
local LLM = require("lnvim.llm")

-- Default configuration
M.config = {
    api_key = os.getenv("EXA_API_KEY"),
    search_docs_path = state.project_lnvim_dir .. "/search_docs",
    default_options = {
        numResults = 10,
        contents = {
            text = true,  -- Get full page text
            highlights = {
                numSentences = 5,
                highlightsPerUrl = 1
            }
        }
    }
}

-- Helper function to get the last user message from the diff buffer
local function get_last_user_message()
    local lines = vim.api.nvim_buf_get_lines(buffers.diff_buffer, 0, -1, false)
    local message = {}
    local in_user_message = false
    
    for i = 1, #lines do
        local line = lines[i]
        if line:match("%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-user") then
            -- Clear previous message if we find a new user delimiter
            message = {}
            in_user_message = true
        elseif line:match("%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-assistant") then
            in_user_message = false
        elseif in_user_message then
            table.insert(message, line)
        end
    end
    
    return table.concat(message, "\n"):gsub("^%s*(.-)%s*$", "%1")
end

-- Helper to save content to file
local function save_content_to_file(content, filename)
    -- Ensure directory exists
    vim.fn.mkdir(M.config.search_docs_path, "p")
    
    local file = io.open(M.config.search_docs_path .. "/" .. filename, "w")
    if file then
        file:write(content)
        file:close()
        return true
    end
    return false
end

-- Function to summarize content using wtf_model
local function summarize_content(content, callback)
    if not state.wtf_model then
        logger.log("No wtf_model configured for summarization", "ERROR")
        return
    end

    -- Find the model configuration
    local model = nil
    for _, m in ipairs(state.models) do
        if m.model_id == state.wtf_model then
            model = m
            break
        end
    end

    if not model then
        logger.log("WTF model not found: " .. state.wtf_model, "ERROR")
        return
    end

    local prompt = "Please provide a brief summary of the following content:\n\n" .. content
    
    -- Use focused_query to get a direct response
    LLM.focused_query({
        model = model,
        system_prompt = "You are a helpful assistant. Provide clear, concise summaries.",
        prompt = prompt,
        on_complete = callback
    })
end

function M.search()
    local query = get_last_user_message()
    if query == "" then
        vim.notify("No query found in last user message", vim.log.levels.ERROR)
        return
    end

    -- Prepare request payload
    local payload = vim.tbl_deep_extend("force", {}, M.config.default_options, {
        query = query
    })

    -- Insert search header into buffer
    LLM.insert_assistant_delimiter("exa-search")
    LLM.write_string_at_llmstream("Search Results for: " .. query .. "\n\n")

    -- Make the API request
    Job:new({
        command = "curl",
        args = {
            "-s",
            "-X", "POST",
            "-H", "Content-Type: application/json",
            "-H", "x-api-key: " .. M.config.api_key,
            "-d", vim.json.encode(payload),
            "https://api.exa.ai/search"
        },
        on_exit = function(j, return_val)
            if return_val ~= 0 then
                vim.schedule(function()
                    vim.notify("Failed to fetch search results", vim.log.levels.ERROR)
                end)
                return
            end

            local result = table.concat(j:result(), "\n")
            local ok, decoded = pcall(vim.json.decode, result)
            
            if not ok then
                vim.schedule(function()
                    vim.notify("Failed to parse search results", vim.log.levels.ERROR)
                end)
                return
            end

            -- Process and display results
            vim.schedule(function()
                for i, result in ipairs(decoded.results) do
                    -- Create a sanitized filename
                    local filename = string.format("%d_%s.txt", 
                        i, 
                        result.title:gsub("[^%w]", "_"):sub(1, 50))
                    
                    -- Save content
                    if result.text then
                        save_content_to_file(result.text, filename)
                    end

                    -- Display result info
                    local result_text = string.format([[
%d. Title: %s
   URL: %s
   Author: %s
   Published: %s
   File: %s

]], i, result.title, result.url, result.author or "N/A", 
                        result.publishedDate or "N/A",
                        M.config.search_docs_path .. "/" .. filename)
                    
                    LLM.write_string_at_llmstream(result_text)

                    -- Start summarization
                    if result.text then
                        summarize_content(result.text, function(summary)
                            vim.schedule(function()
                                LLM.write_string_at_llmstream(string.format([[
Summary for Result #%d:
%s

]], i, summary))
                            end)
                        end)
                    end
                end

                LLM.print_user_delimiter()
            end)
        end
    }):start()
end

M._test = {
    summarize_content = function(content, callback)
        if not state.wtf_model then
            logger.log("No wtf_model configured for summarization", "ERROR")
            return
        end

        local model = nil
        for _, m in ipairs(state.models) do
            if m.model_id == state.wtf_model then
                model = m
                break
            end
        end

        if not model then
            logger.log("WTF model not found: " .. state.wtf_model, "ERROR")
            return
        end

        local prompt = "Please provide a brief summary of the following content:\n\n" .. content
        
        LLM.focused_query({
            model = model,
            system_prompt = "You are a helpful assistant. Provide clear, concise summaries.",
            prompt = prompt,
            on_complete = callback
        })
    end
}

return M
