# l.nvim
l.nvim is a Neovim plugin that integrates large language models (LLMs) into your editing workflow.

N.B.: The plugin interface will change randomly whenever I feel like updating. Lock your commit hash or be prepared for trouble!

## Features

- Interact with LLMs directly from your editor
- Apply AI-generated changes to your code
- Execute shell commands and add their output to the prompt
- Use prompt macros for quick and consistent interactions

## Installation

I use lazy.nvim. It's pretty straightforward if you want defaults, see customization if you want overrides.

```
  {
    "baketnk/l.nvim"
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



| Variable | Default Value |
|----------|---------------|

| autocomplete | {| |
| max_prompt_length | 16000| |
| default_prompt_path | os.getenv("HOME") .. "/.local/share/lnvim/"| |
| keymap_prefix | "<Leader>;"| |



### Default Model Configuration



| Model ID | Model Type | API URL | API Key | Use Toolcalling |
|----------|------------|---------|---------|-----------------|

| claude-3-5-sonnet-20240620 | anthropic | https://api.anthropic.com/v1/messages | ANTHROPIC_API_KEY | false |
| claude-3-opus-20240229 | anthropic | https://api.anthropic.com/v1/messages | ANTHROPIC_API_KEY | false |
| hermes-3-llama-3.1-405b-fp8 | openaicompat | https://api.lambdalabs.com/v1/chat/completions | LAMBDA_API_KEY | false |
| hermes3 | openaicompat | http://localhost:11434/v1/chat/completions |  | false |
| o1-mini | openaicompat | https://openrouter.ai/api/v1/chat/completions | OPENROUTER_API_KEY | false |
| o1-preview | openaicompat | https://openrouter.ai/api/v1/chat/completions | OPENROUTER_API_KEY | false |
| gpt-4o-mini | openaicompat | https://openrouter.ai/api/v1/chat/completions | OPENROUTER_API_KEY | false |
| x-ai/grok-2 | openaicompat | https://openrouter.ai/api/v1/chat/completions | OPENROUTER_API_KEY | false |



## Keymappings

- `<Leader>;y`: Yank code block
- `<Leader>;s`: Set system prompt
- `<Leader>;f`: Select prompt files
- `<Leader>;/`: LSP Introspection
- `<Leader>;j`: Next code block
- `<Leader>;k`: Previous code block
- `<Leader>;;`: Toggle drawer
- `<Leader>;l`: Chat with LLM
- `<Leader>;r`: Replace file with code
- `<Leader>;m`: Select LLM model
- `<Leader>;i`: Focus main window
- `<Leader>;t`: Toggle tool usage
- `<Leader>;a`: Apply diff to buffer
- `<Leader>;R`: Generate README.md

## License

MIT

