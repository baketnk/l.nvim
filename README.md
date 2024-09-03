# l.nvim
l.nvim is a Neovim plugin that integrates large language models (LLMs) into your editing workflow.

## Features

- Interact with LLMs directly from your editor
- Apply AI-generated changes to your code
- Execute shell commands and add their output to the prompt
- Use prompt macros for quick and consistent interactions

## Installation

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
	'your-username/l.nvim',
	config = function()
		require('lnvim').setup()
	end
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

## Keymappings

- `<Leader>;y`: Yank code block
- `<Leader>;s`: Set system prompt
- `<Leader>;f`: Select prompt files
- `<Leader>;j`: Next code block
- `<Leader>;k`: Previous code block
- `<Leader>;;`: Toggle drawer
- `<Leader>;l`: Chat with LLM
- `<Leader>;m`: Cycle LLM provider
- `<Leader>;r`: Replace file with code
- `<Leader>;i`: Focus main window
- `<Leader>;t`: Toggle tool usage
- `<Leader>;q`: Execute Prompt Macro
- `<Leader>;a`: Apply diff to buffer
- `<Leader>;R`: Generate README.md

## License

MIT

