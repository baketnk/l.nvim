local M = {}
local constants = require("lnvim.constants")
local modal = require("lnvim.ui.modal")
local state = require("lnvim.state")
local scandir = require('plenary.scandir')
local Path = require('plenary.path')
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local LLM = require('lnvim.llm')
-- memex_path: root dir for memex functions / save
-- memex_search_paths: { ... }

function M.new_note_modal()
    modal.modal_input({ prompt = "Enter note content:" }, function(content)
        modal.modal_input({ prompt = "Note name (leave empty to generate):" }, function(name_input)
            local name = table.concat(name_input, " ")
            if name == "" then
                -- Generate name using LLM
                local temp_file = vim.fn.tempname()
                vim.fn.writefile(content, temp_file)
                LLM.focused_query({
                    system_prompt = "Generate a concise, descriptive filename for this note. Respond ONLY with the filename, no extension or markdown.",
                    files = {temp_file},
                    on_complete = function(response)
                        name = response:gsub("[^%w_%-]", ""):sub(1, 50)
                        vim.fn.delete(temp_file)
                        M.store(name, content, {
                            tags = {"auto-generated"},
                            links = {}
                        })
                    end
                })
            else
                M.store(name, content, {
                    tags = {},
                    links = {}
                })
            end
        end)
    end)
end

M.generate_initial_search_path = function(path)
    
    
    -- Find all .lnvim directories recursively
    local found_dirs = scandir.scan_dir(path, {
        search_pattern = "%.lnvim$",
        depth = 100,
        add_dirs = true,
        only_dirs = true,
        silent = true
    })
    
    -- Always include the current project's .lnvim dir
    table.insert(found_dirs, state.project_lnvim_dir)
    
    -- Include memex_path if configured
    if state.memex_path then
        table.insert(found_dirs, state.memex_path)
    end
    
    -- Deduplicate and validate
    local seen = {}
    local valid_dirs = {}
    for _, dir in ipairs(found_dirs) do
        local real_dir = Path:new(dir):absolute()
        if not seen[real_dir] and vim.fn.isdirectory(real_dir) == 1 then
            table.insert(valid_dirs, real_dir)
            seen[real_dir] = true
        end
    end
    
    return valid_dirs
end

M.store = function(name, content, opts)
    opts = opts or {}
    name = name:gsub("%s+", "_")
               :gsub("[^%w-_]", "")
               :sub(1, 50)
               :lower()

    if name == "" or name == nil then
        name = os.date("%Y%m%d-%H%M%S")
    end
    local notes_dir = tostring(Path:new(state.memex_path or state.default_prompt_path, "notes"))
    
    -- Create directory if needed
    if vim.fn.isdirectory(notes_dir) == 0 then
        vim.fn.mkdir(notes_dir, "p")
    end
    
    -- Construct filename
    local filename = name:gsub("%s+", "_"):gsub("[^%w-_]", "") .. ".md"
    local full_path = tostring(Path:new(notes_dir, filename))
    vim.fn.system("touch " .. vim.fn.shellescape(full_path))
    
    -- Add metadata preamble
    local lines = {"---"}
    if opts.tags then
        table.insert(lines, "tags: " .. table.concat(opts.tags, ", "))
    end
    if opts.links then
        table.insert(lines, "links: " .. table.concat(opts.links, ", "))
    end
    table.insert(lines, "---\n")
    
    -- Ensure content is a table of strings
    if type(content) == "string" then
        content = vim.split(content, "\n")
    end
    
    -- Add content to lines
    vim.list_extend(lines, content)
    
    -- Write to file
    vim.fn.writefile(lines, full_path)
end

M.retrieve = function(name)
    local notes_dir = tostring(Path:new(state.memex_path or state.default_prompt_path, "notes"))
    local filename = name:gsub("%s+", "_"):gsub("[^%w-_]", "") .. ".md"
    local full_path = tostring(Path:new(notes_dir, filename))
    
    if vim.fn.filereadable(full_path) == 1 then
        local lines = vim.fn.readfile(full_path)
        local meta = {}
        local content = {}
        local in_meta = false
        
        for _, line in ipairs(lines) do
            if line:match("^---$") then
                in_meta = not in_meta
            elseif in_meta then
                local key, val = line:match("^([%w_]+):%s*(.+)$")
                if key and val then
                    if key == "tags" or key == "links" then
                        meta[key] = vim.split(val, "%s*,%s*")
                    else
                        meta[key] = val
                    end
                end
            else
                table.insert(content, line)
            end
        end
        
        return {
            metadata = meta,
            content = table.concat(content, "\n")
        }
    end
    return nil
end

M.link_notes = function(a, b)
    local note_a = M.retrieve(a)
    local note_b = M.retrieve(b)
    
    if not note_a or not note_b then
        return false, "One or both notes not found"
    end
    
    -- Add links to metadata
    note_a.metadata.links = note_a.metadata.links or {}
    table.insert(note_a.metadata.links, b)
    
    note_b.metadata.links = note_b.metadata.links or {}
    table.insert(note_b.metadata.links, a)
    
    -- Save updated notes
    M.store(a, note_a.content, { links = note_a.metadata.links })
    M.store(b, note_b.content, { links = note_b.metadata.links })
    
    return true
end

M.search = function(query, opts)
    opts = opts or {}
    local Job = require('plenary.job')
    local results = {}
    
    local paths = M.generate_initial_search_path(opts.path or vim.fn.getcwd())
    local search_dirs = opts.search_paths or paths
    
    Job:new({
        command = "rg",
        args = {
            "--color=never",
            "--no-heading",
            "--with-filename",
            "--line-number",
            "--smart-case",
            "--hidden",
            query,
            unpack(search_dirs)
        },
        on_exit = function(j, return_val)
            if return_val == 0 then
                for _, line in ipairs(j:result()) do
                    local file, lnum, text = line:match("^([^:]+):(%d+):(.+)$")
                    if file then
                        table.insert(results, {
                            file = file,
                            lnum = tonumber(lnum),
                            text = text
                        })
                    end
                end
            end
        end
    }):sync()
    
    return results
end

function M.search_notes()
    local notes_dir = tostring(Path:new(state.memex_path or state.default_prompt_path, "notes"))
    
    -- Scan the notes directory for .md files
    local note_files = scandir.scan_dir(notes_dir, {
        hidden = true,
        add_dirs = false,
        depth = 1,
        search_pattern = "%.md$",
    })

    -- Create a table to hold file information
    local items = {}
    for _, file_path in ipairs(note_files) do
        -- Get the filename from the full path
        local filename = vim.fn.fnamemodify(file_path, ":t")
        
        -- Get the file's modification time
        local stat = vim.loop.fs_stat(file_path)
        if stat then
            table.insert(items, {
                value = file_path,  -- Full path for editing
                display = string.format("%s (%s)", 
                    filename:gsub("%.md$", ""),  -- Remove .md extension
                    os.date("%Y-%m-%d", stat.mtime.sec)  -- Format modification time
                ),
                ordinal = filename,  -- For sorting
                stat = stat,  -- Store stat for sorting
            })
        end
    end

    -- Sort items by modification time (most recent first)
    table.sort(items, function(a, b) 
        return a.stat.mtime.sec > b.stat.mtime.sec
    end)

    -- Create a Telescope picker to display the notes
    require("telescope.pickers").new({}, {
        prompt_title = "Memex Notes (Recent First)",
        finder = require("telescope.finders").new_table({
            results = items,
            entry_maker = function(entry) return entry end
        }),
        sorter = require("telescope.config").values.generic_sorter({}),
        previewer = false,
        attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                if selection then
                    vim.cmd("edit " .. selection.value)  -- Open the selected note
                end
            end)
            return true
        end
    }):find()
end

function M.insert_note()
    require("telescope.builtin").find_files({
        prompt_title = "Insert Memex Note",
        cwd = tostring(Path:new(state.memex_path or state.default_prompt_path, "notes")),
        attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                if selection then
                    local note = M.retrieve(selection.value:gsub("%.md$", ""))
                    if note then
                        local lines = {
                            "```md",
                            note.content,
                            "```"
                        }
                        vim.api.nvim_put(lines, "l", true, true)
                    end
                end
            end)
            return true
        end
    })
end

function M.global_search()
    modal.modal_input({ prompt = "Memex search query:" }, function(query)
        local results = M.search(table.concat(query, " "))
        -- Display results in quickfix list
        vim.fn.setqflist({}, ' ', {
            title = "Memex Search Results",
            items = vim.tbl_map(function(r)
                return {
                    filename = r.file,
                    lnum = r.lnum,
                    text = r.text
                }
            end, results)
        })
        vim.cmd("copen")
    end)
end




return M

