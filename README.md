# l.nvim
l.nvim is a Neovim plugin that integrates large language models (LLMs) into your editing workflow.

Stability warning: Development is currently when I feel like it. I try not to break `master` but user beware.

## Features

- Chat with LLMs directly from your editor
- Execute shell commands and add their output to the prompt
- Add files from your repo into your chat automatically.
- Built-in project-level chat logging, system prompt.
- LSP aware replacement. select the chat codeblock, activate the binding, choose where to replace functions in your file.

(Read the entire README for details, there's a lot of stuff in here)

## Installation

I use lazy.nvim. It's pretty straightforward if you want defaults, see customization if you want overrides.

New: You need `nvim-treesitter` for the LSP replacement to work. Don't forget to `:TSInstall <lang>` for your language's grammar. Currently only works for Zig, more languages by request or as I get to them.

```
  {
    "baketnk/l.nvim",
    dependencies = {
        "nvim-treesitter"
    },
    opts = {}
  }
```

## Configuration

You can configure l.nvim by passing options to the setup function:

```lua
require('lnvim').setup({
	keymap_prefix = "<Leader>;",
	open_drawer_on_setup = true,
})
```

### Configuration Variables

1. **`models`**: A list of model configurations to use instead of the default models.
2. **`additional_models`**: A list of additional model configurations to append to the default models.
3. **`autocomplete`**: Configuration for autocomplete settings, including:
   - `max_tokens`: Maximum number of tokens for autocomplete.
   - `temperature`: Temperature setting for autocomplete.
4. **`autocomplete_model`**: Configuration for the autocomplete model. (WIP)
5. **`wtf_model`**: The model to use for the "wtf" functionality. (WIP)
6. **`default_prompt_path`**: Path to the default system prompt file. (default: `~/.local/share/lnvim`)
7. **`keymap_prefix`**: Prefix for keybindings (default is `<Leader>;`).
8. **`llm_log_path`**: Path to store LLM logs. (defaults to `./.lnvim/logs`)
9. **`open_drawer_on_setup`**: Boolean to determine if the plugin layout should be opened on setup.

### Default Model Configurations

You can either override this list with `opts.models` or just add additional models with `opts.additional_models`. 

```lua
{
    model_id = "hermes3", -- passed directly to the backend
    model_type = "openaicompat", -- anthropic, openaicompat
    api_url = "http://localhost:11434/v1/chat/completions", -- specify the exact URL, not just /v1
    api_key = "PROVIDER_API_KEY", -- name of key/token env var
    noauth = false, -- set to true to disable token usage (e.g. local)
    use_toolcalling = false, -- WIP
},
```

## Keymappings

1. **`YankCodeBlock`**
   - **Keybinding**: `<Leader>;y`
   - **Description**: Yank code block.

2. **`SetSystemPrompt`**
   - **Keybinding**: `<Leader>;s`
   - **Description**: Set system prompt.

3. **`SetPromptFile`**
   - **Keybinding**: `<Leader>;f`
   - **Description**: Select prompt files.

4. **`EnumerateProjectFiles`**
   - **Keybinding**: `<Leader>;F`
   - **Description**: Enumerate project files. (WIP)

5. **`LspIntrospect`**
   - **Keybinding**: `<Leader>;/`
   - **Description**: LSP Introspection.

6. **`Next`**
   - **Keybinding**: `<Leader>;j`
   - **Description**: Next code block.

7. **`Prev`**
   - **Keybinding**: `<Leader>;k`
   - **Description**: Previous code block.

8. **`OpenClose`**
   - **Keybinding**: `<Leader>;;`
   - **Description**: Toggle drawer.

9. **`LLMChat`**
   - **Keybinding**: `<Leader>;l`
   - **Description**: Chat with LLM. (submits current chat)

10. **`ReplaceFile`**
    - **Keybinding**: `<Leader>;r`
    - **Description**: Replace entire file with code.

11. **`SmartReplaceCodeblock`**
    - **Keybinding**: `<Leader>;R`
    - **Description**: Smart replace code block.

12. **`SelectToPrompt`**
    - **Keybinding**: `<Leader>;p` (in visual mode)
    - **Description**: Copy selection to end of prompt.

13. **`SelectToPromptWrap`**
    - **Keybinding**: `<Leader>;P` (in visual mode)
    - **Description**: Copy selection to end of prompt in codeblock.

14. **`SelectModel`**
    - **Keybinding**: `<Leader>;m`
    - **Description**: Select LLM model.

15. **`ClearAllBuffers`**
    - **Keybinding**: `<Leader>;dg`
    - **Description**: Clear chat & file buffers.

16. **`ClearDiffBuffer`**
    - **Keybinding**: `<Leader>;dd`
    - **Description**: Clear chat buffer.

17. **`ClearFilesList`**
    - **Keybinding**: `<Leader>;df`
    - **Description**: Clear files buffer.

18. **`FocusMain`**
    - **Keybinding**: `<Leader>;i`
    - **Description**: Focus main window.

19. **`ToggleToolUsage`**
    - **Keybinding**: `<Leader>;t`
    - **Description**: Toggle tool usage. (WIP)

20. **`ShellToPrompt`**
    - **Keybinding**: `<Leader>;p`
    - **Description**: Run shell command and add output to prompt.

21. **`ApplyDiff`**
    - **Keybinding**: `<Leader>;a`
    - **Description**: Apply diff to buffer. (WIP/Broken)

22. **`StreamSelected`**
    - **Keybinding**: `<Leader>;w` (in visual mode)
    - **Description**: Stream selected text through qask. (WIP/Undocumented)

23. **`DumpSymbols`**
    - **Keybinding**: `<Leader>;S`
    - **Description**: Dump LSP symbols to buffer. (Debugging)


## Contributing

Contributions are welcome, feel free to submit issues or PRs.

## Sponsors

For fun project at this point, if I leave the day job may look into this route.

## License

MIT

