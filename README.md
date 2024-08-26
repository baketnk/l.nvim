# l.nvim - Neovim Plugin for AI-Assisted Coding

![image](https://repository-images.githubusercontent.com/847120613/b73bed30-4aa2-4fbf-9ffc-9c870915cb38)

l.nvim is a Neovim plugin that integrates AI-assisted coding functionality into your Neovim workflow. It provides features like chat-based code generation, codeblock navigation, and seamless integration with your existing Neovim setup.

## Features

- Chat with AI to generate code snippets and assist in coding tasks
- Navigate between codeblocks in your buffer
- Send codeblocks to a specific mark for easy editing
- Customize the AI system prompt for tailored responses
- Debounce mechanism to prevent excessive API calls

## Installation

To install l.nvim using lazy.nvim, add the following to your `lazy.nvim` configuration:

```lua
{
  "baketnk/l.nvim",
  config = function()
    require("lnvim").setup({
      -- your configuration options
    })
  end,
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary"
  }
}
```

## Configuration

l.nvim provides a `setup` function to customize the plugin behavior. Here are the available options:

- `default_prompt_path` (string): The default path to load prompts from (default: `os.getenv("HOME") .. "/.local/share/lnvim/"`).
- `keymap_prefix` (string): The prefix for lnvim keymaps (default: `<Leader>;;`).
- `mark` (string): The mark to use for sending codeblocks (default: `T`).
- `use_openai_compat` (boolean): Whether to use OpenAI compatibility mode (default: `nil`).
- `api_key_name` (string): The name of the environment variable containing the API key (required if `use_openai_compat` is `true`).

The name of the api key determines which provider is used. The default is the openai-like. Anthropic has been added as of 2024-08-25!

Example configuration:

```lua
require("l.nvim").setup({
  default_prompt_path = "~/.config/nvim/lnvim_prompts/",
  keymap_prefix = "<Leader>;",
  mark = "T",
  use_openai_compat = true,
  api_key_name = "OPENAI_API_KEY",
})
```

## Keymappings

l.nvim provides the following keymappings:

- `<Leader>;y`: Yank the current codeblock
- `<Leader>;s`: Set the system prompt
- `<Leader>;f`: Select files for pasting into the prompt
- `<Leader>;r`: Reimport the last selected files
- `<Leader>;j`: Go to the next codeblock
- `<Leader>;k`: Go to the previous codeblock
- `<Leader>;;`: open the LLM drawer, or run the LLM if the drawer is focused. 
- <Leader>;m: cycle through available providers (Anthropic, OpenAI-like)

## License

l.nvim is released under the MIT License.

## Contributing

Contributions to l.nvim are welcome! Please open an issue or submit a pull request on the GitHub repository.

If you have any comments or bugs or concerns please open an issue, actively developing this for myself but if it's useful to anyone else would love to assemble something.

## A Message From Your Local Consciousness

Hi, the above was entirely generated by Hermes 3, with some editing by me to remove references to a feature I wasn't sure shipped or not.

It's wild how good LLMs are getting. I truly hope we can own these tools as a species and not allow impossible-to-audit entities gatekeep this. With any luck, SB 1047 will make it more likely that things happen outside of California.

Find the others. The real people are out there.

## Acknowledgements

[yacineMTB](https://twitter.com/yacineMTB) for inspiring my own take on his [dingLlm.nvim](https://github.com/yacineMTB/dingllm.nvim) plugin, inspiring me to try nvim again and actually get it to take, and generally encouraging the timeline into actually making stuff
