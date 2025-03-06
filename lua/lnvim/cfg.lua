local M = {}
if M.is_loaded then
   return M
end
local constants = require("lnvim.constants")
local lcmd = require("lnvim.cmd")
local buffers = require("lnvim.ui.buffers")
local state = require("lnvim.state")
-- local LLM = require("lnvim.llm")

function M.debug_current_model()
   vim.print(M.current_model)
end

function M.get_project_root()
   local cwd = vim.fn.getcwd()
   local git_dir = vim.fn.finddir(".git", cwd .. ";")
   if git_dir ~= "" then
      return vim.fn.fnamemodify(git_dir, ":h")
   else
      return cwd
   end
end

function M.make_plugKey(name, mode, keys, func, opts)
   local full_name = constants.plugin_name .. name
   vim.keymap.set(mode, "<Plug>" .. full_name .. ";", func, opts)
   if state.keymap_prefix ~= "" then
      if mode ~= "i" then
         vim.keymap.set(mode, state.keymap_prefix .. keys, func, opts)
      else
         vim.keymap.set(mode, keys, func, opts)
      end
   end
end

local function validate_model(model)
   local required_fields = { "model_id", "model_type", "api_url", "api_key" }
   for _, field in ipairs(required_fields) do
      if not model[field] then
         if field == "api_key" and not (model["noauth"] or model["api_url"].match("localhost")) then
            error("Model configuration missing required field: " .. field)
         end
      end
   end
   if type(model.use_toolcalling) ~= "boolean" then
      model.use_toolcalling = false
   end
   return model
end

M.default_models = {
   {
      model_id = "claude-3-5-sonnet-20241022",
      model_type = "anthropic",
      api_url = "https://api.anthropic.com/v1/messages",
      api_key = "ANTHROPIC_API_KEY",
      use_toolcalling = false,
   },
   {
      model_id = "claude-3-7-sonnet-latest",
      model_type = "anthropic",
      api_url = "https://api.anthropic.com/v1/messages",
      api_key = "ANTHROPIC_API_KEY",
      use_toolcalling = false,
   },
   {
      model_id = "claude-3-5-sonnet-20240620",
      model_type = "anthropic",
      api_url = "https://api.anthropic.com/v1/messages",
      api_key = "ANTHROPIC_API_KEY",
      use_toolcalling = false,
   },
   {
      model_id = "claude-3-opus-20240229",
      model_type = "anthropic",
      api_url = "https://api.anthropic.com/v1/messages",
      api_key = "ANTHROPIC_API_KEY",
      use_toolcalling = false,
   },

   {
      model_id = "grok-2-1212",
      model_type = "openaicompat",
      api_url = "https://api.x.ai/v1/chat/completions",
      api_key = "XAI_API_KEY",
      use_toolcalling = false,
   },
   {
      model_id = "deepseek-chat",
      model_type = "openaicompat",
      api_key = "DEEPSEEK_API_KEY",
      api_url = "https://api.deepseek.com/v1/chat/completions",
      use_toolcalling = false,
   },
   {
      model_id = "deepseek-reasoner",
      model_type = "openaicompat",
      api_key = "DEEPSEEK_API_KEY",
      api_url = "https://api.deepseek.com/v1/chat/completions",
      use_toolcalling = false,
   },
   {
      model_id = "llama3.2:3b",
      model_type = "openaicompat",
      noauth = true,
      api_url = "http://localhost:11434/v1/chat/completions",
      use_toolcalling = false,
   },
   {
      model_id = "gemini-2.0-flash",
      model_type = "google",
      api_key = "GOOGLE_API_KEY",
      api_url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:streamGenerateContent",
      use_toolcalling = false,
   },
   {
      model_id = "gemini-2.0-pro-exp-02-05",
      model_type = "google",
      api_key = "GOOGLE_API_KEY",
      api_url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-pro-exp-02-05:streamGenerateContent",
      use_toolcalling = false,
   },
   {
      model_id = "huggingface.co/NousResearch/DeepHermes-3-Llama-3-8B-Preview-GGUF:latest", -- TODO: use real ollama name
      model_type = "openaicompat",
      noauth = true,
      api_url = "http://localhost:11434/v1/chat/completions",
      use_toolcalling = false,
      reasoning_prompt_override =
      "You are a deep thinking AI, you may use extremely long chains of thought to deeply consider the problem and deliberate with yourself via systematic reasoning processes to help come to a correct solution prior to answering. You should enclose your thoughts and internal monologue inside <think> </think> tags, and then provide your solution or response to the problem.",
   },
}

function M.setup(_opts)
   local opts = _opts or {}

   M.is_loaded = true

   state.status = "Loading"

   -- Populate state instead of M
   state.models = {}
   for _, model in ipairs(opts.models or M.default_models) do
      table.insert(state.models, validate_model(model))
   end
   for _, model in ipairs(opts.additional_models or {}) do
      table.insert(state.models, validate_model(model))
   end

   state.autocomplete = opts.autocomplete or {
      max_tokens = 300,
      temperature = 0.3,
   }

   state.autocomplete_model = opts.autocomplete_model
       or
       {
          model_id = "deepseek-chat",
          model_type = "openaicompat",
          api_key = "DEEPSEEK_API_KEY",
          api_url = "https://api.deepseek.com/v1/chat/completions",
          use_toolcalling = false,
       }
   -- local autocomplete = require("lnvim.autocomplete")


   state.wtf_model = opts.wtf_model or "llama3.2:3b"
   local model_exists = vim.tbl_contains(
      vim.tbl_map(function(m) return m.model_id end, state.models),
      state.wtf_model
   )

   if not model_exists then
      vim.notify("wtf_model '" .. state.wtf_model .. "' not found in configured models", vim.log.levels.WARN)
      state.wtf_model = state.models[1].model_id
   end

   state.current_model = state.models[1]
   state.default_prompt_path = opts.default_prompt_path or os.getenv("HOME") .. "/.local/share/lnvim/"

   state.memex_path = opts.memex_path or (state.default_prompt_path .. "/memex")
   if vim.fn.isdirectory(state.memex_path) == 0 then
      vim.fn.mkdir(state.memex_path, "p")
      vim.fn.mkdir(state.memex_path .. "/notes", "p")
   end
   state.project_root = M.get_project_root()
   state.project_lnvim_dir = state.project_root .. "/.lnvim"
   if vim.fn.isdirectory(state.project_lnvim_dir) == 0 then
      vim.fn.mkdir(state.project_lnvim_dir, "p")
   end

   -- Copy the system_prompt file to the .lnvim folder
   local global_system_prompt_path = state.default_prompt_path .. "/system_prompt.txt"
   local project_system_prompt_path = state.project_lnvim_dir .. "/system_prompt.txt"
   if vim.fn.filereadable(global_system_prompt_path) == 0 then
      vim.fn.mkdir(state.default_prompt_path, "p")
      vim.fn.writefile({ "You are a helpful software engineering assistant." }, global_system_prompt_path)
   end

   if vim.fn.filereadable(project_system_prompt_path) == 0 then
      vim.fn.system("cp " .. global_system_prompt_path .. " " .. project_system_prompt_path)
   end
   state.project_system_prompt_path = project_system_prompt_path

   state.llm_log_path = state.project_lnvim_dir .. "/logs"

   -- Check for .gitignore file and add .lnvim directory to it
   local gitignore_path = state.project_root .. "/.gitignore"
   if vim.fn.filereadable(gitignore_path) == 1 then
      local gitignore_content = vim.fn.readfile(gitignore_path)
      local lnvim_entry = ".lnvim/"
      if not vim.tbl_contains(gitignore_content, lnvim_entry) then
         table.insert(gitignore_content, lnvim_entry)
         vim.fn.writefile(gitignore_content, gitignore_path)
      end
   end

   -- load the system prompt from global or proj
   local system_prompt_content = vim.fn.readfile(project_system_prompt_path)
   state.project_system_prompt_path = project_system_prompt_path
   state.system_prompt = system_prompt_content
   state.keymap_prefix = opts.keymap_prefix or "<Leader>;"
   state.mark = "T"

   vim.filetype.add({
      extension = {
         [constants.filetype_ext] = "markdown"
      }
   })

   vim.g.markdown_fenced_languages = {
      "html",
      "css",
      "javascript",
      "ruby",
      "python",
      "lua",
      "c",
   }

   lcmd.setup_filetype_ac()
   if opts.llm_log_path ~= nil then
      vim.api.nvim_create_autocmd({ "BufUnload", "VimLeavePre" }, {
         pattern = "*",
         callback = function(ev)
            if ev.buf == buffers.diff_buffer then
               require("lnvim.cmd").clear_buffers("diff")
            end
         end,
      })
   end
   M.make_plugKey("YankCodeBlock", "n", "y", lcmd.yank_codeblock, { desc = "Yank code block" })
   M.make_plugKey("SetSystemPrompt", "n", "s", lcmd.set_system_prompt, { desc = "Set system prompt" })
   M.make_plugKey("SetPromptFile", "n", "f", lcmd.select_files_for_prompt, { desc = "Select prompt files" })
   M.make_plugKey(
      "SetAllFiles",
      "n",
      "F",
      lcmd.select_all_files_for_prompt,
      { desc = "Select hidden/ignored files" }
   )
   M.make_plugKey("LspIntrospect", "n", "/", lcmd.lsp_introspect, { desc = "LSP Introspection" })
   M.make_plugKey("Next", "n", "j", lcmd.next_magic, { desc = "Next code block" })
   M.make_plugKey("Prev", "n", "k", lcmd.previous_magic, { desc = "Previous code block" })
   M.make_plugKey("OpenClose", "n", ";", lcmd.open_close, { desc = "Toggle drawer" })
   M.make_plugKey("LLMChat", "n", "l", lcmd.chat_with_magic, { desc = "Chat with LLM" })

   M.make_plugKey("SelectModel", "n", "m", lcmd.select_model, { desc = "Select LLM model" })

   -- M.make_plugKey("Autocomplete", "i", "<C-;>", autocomplete.call_autocomplete, { desc = "autocomplete" })
   -- M.make_plugKey("AutocompleteLine", "i", "<C-'>", autocomplete.insert_next_line, { desc = "AC insert line" })
   -- M.make_plugKey("AutocompleteAll", "i", "<C-p>", autocomplete.insert_whole_suggestion, { desc = "AC insert suggestion" })

   M.make_plugKey("ReplaceFile", "n", "r", lcmd.replace_file_with_codeblock, { desc = "Replace file with code" })
   M.make_plugKey("SmartReplaceCodeblock", "n", "R", lcmd.smart_replace_with_codeblock,
      {  desc = "Smart replace code block" })
   M.make_plugKey(
      "ClipboardReplace",
      "n",
      "e", -- rb for "replace from clipboard"
      require("lnvim.lsp_replace_rules").replace_with_clipboard,
      { desc = "Replace symbols using clipboard content" }
   )
   M.make_plugKey("SelectToPrompt", "x", "p", lcmd.selection_to_prompt, { desc = "copy selection to end of prompt" })
   M.make_plugKey(
      "SelectToPromptWrap",
      "v",
      "P",
      lcmd.selection_to_prompt_wrapped,
      { desc = "copy selection to end of prompt in codeblock" }
   )


   M.make_plugKey(

      "ToggleCaching",

      "n",

      "C", -- <Leader>;C

      function()
         state.prompt_cache.enabled = not state.prompt_cache.enabled

         local status_msg = "Prompt caching " .. (state.prompt_cache.enabled and "enabled" or "disabled")

         vim.notify(status_msg, vim.log.levels.INFO)
      end,

      { desc = "Toggle prompt caching" })

   M.make_plugKey(
      "CacheOnlyFiles",
      "n",
      "c",
      require("lnvim.cache").select_cache_only_files,
      { desc = "Select files for cache-only" }
   )
   M.make_plugKey("ClearCacheFiles", "n", "dc", function()
      lcmd.clear_buffers("c")
   end, { desc = "Clear cached files" })
   M.make_plugKey("ClearAllBuffers", "n", "dg", function()
      lcmd.clear_buffers("all")
   end, { desc = "Clear all buffers" })
   M.make_plugKey("ClearDiffBuffer", "n", "dd", function()
      lcmd.clear_buffers("d")
   end, { desc = "Clear diff buffer" })
   M.make_plugKey("ClearFilesList", "n", "df", function()
      lcmd.clear_buffers("f")
   end, { desc = "Clear files buffer" })

   M.make_plugKey("FocusMain", "n", "i", lcmd.focus_main_window, { desc = "Focus main window" })

   -- In cfg.lua's setup function:
   M.make_plugKey("MemexNewNote", "n", "n", require("lnvim.memex").new_note_modal, { desc = "Create new memex note" })
   M.make_plugKey("MemexSearchNotes", "n", "N", require("lnvim.memex").search_notes, { desc = "Search memex notes" })
   M.make_plugKey("MemexInsertNote", "n", "in", require("lnvim.memex").insert_note, { desc = "Insert memex note" })
   M.make_plugKey("MemexGlobalSearch", "n", "sn", require("lnvim.memex").global_search, { desc = "Search memex content" })

   M.make_plugKey(
      "ExaSearch",
      "n",
      "E", -- This will make it <Leader>;E
      require("lnvim.exa").search,
      { desc = "Search with Exa API" }
   )

   M.make_plugKey("ToggleToolUsage", "n", "t", require("lnvim.toolcall").tools_toggle, { desc = "Toggle tool usage" })
   M.make_plugKey(
      "ShellToPrompt",
      "n",
      "p",
      lcmd.shell_to_prompt,
      { desc = "Run shell command and add output to prompt" }
   )

   M.make_plugKey(
      "DumpSymbols",
      "n",
      "uS", -- or whatever key you prefer
      require("lnvim.lsp_replace_rules").dump_document_symbols_to_buffer,
      { desc = "Dump LSP symbols to buffer" }
   )

   -- Add development-related keymaps
   M.make_plugKey(
      "DevToggleDebug",
      "n",
      "ud", -- <Leader>;dd for "dev debug"
      require("lnvim.utils.logger").toggle_debug_mode,
      { desc = "Toggle developer debug logging" }
   )

   M.make_plugKey(
      "ToggleDiffPreview",
      "n",
      "ut", -- <Leader>;ut for "toggle diff preview"
      require("lnvim.lsp_replace_rules").toggle_diff_preview,
      { desc = "Toggle diff preview for replacements" }
   )

   M.make_plugKey(
      "DevOpenLogs",
      "n",
      "ul", -- <Leader>;dl for "dev logs"
      function()
         local state = require("lnvim.state")
         local log_dir = state.project_lnvim_dir .. "/debug_logs"
         vim.cmd("split " .. log_dir .. "/dev_debug.log")
      end,
      { desc = "Open developer debug logs" }
   )

   M.make_plugKey(
      "DevClearLogs",
      "n",
      "uc", -- <Leader>;dc for "dev clear"
      function()
         local state = require("lnvim.state")
         local log_file = state.project_lnvim_dir .. "/debug_logs/dev_debug.log"
         local file = io.open(log_file, "w")
         if file then
            file:close()
            vim.notify("Developer debug logs cleared", vim.log.levels.INFO)
         end
      end,
      { desc = "Clear developer debug logs" }
   )
   M.make_plugKey(
      "ToggleReasoning",
      "n",
      "ur", -- <Leader>;r
      function()
         state.use_reasoning = not state.use_reasoning
         local status = state.use_reasoning and "enabled" or "disabled"
         local model = state.current_model
         local has_override = model and model.reasoning_prompt_override and true or false
         local message = string.format("Reasoning mode %s%s",
            status,
            state.use_reasoning and has_override and
            " (using custom prompt for " .. model.model_id .. ")" or "")
         vim.notify(message, vim.log.levels.INFO)
      end,
      { desc = "Toggle reasoning mode" }
   )

   -- M.make_plugKey("GenerateReadme", "n", "R", lcmd.generate_readme, { desc = "Generate README.md" })
   if opts.open_drawer_on_setup then
      M.show_drawer()
   end

   vim.api.nvim_create_user_command("TestModal", function()
      require("lnvim.ui.modal").modal_input({ prompt = "Test Modal:" }, function(input)
         print("You entered: " .. input)
      end, function()
         print("Cancelled")
      end)
   end, {})

   state.status = "Idle"
end

return M
