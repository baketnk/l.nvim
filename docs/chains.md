# l.nvim Chain Configuration

## Overview

Chains in `l.nvim` allow you to define a sequence of steps involving user inputs, LLM interactions, and shell commands. This modular approach enables complex workflows tailored to your development needs.

## Defining a Chain

Chains are defined in the `chains.lua` configuration file. Each chain consists of multiple steps, where each step can be of a different type.

### Step Types

- **User Input (`user_input`):** Prompts the user for input.
- **LLM Call (`llm`):** Sends a prompt to an LLM model and captures the response.
- **User Confirmation (`user_confirmation`):** Asks the user to approve or reject an action.
- **Bash Command (`bash`):** Executes a shell command.
- **Branch (`branch`):** Conditional execution of steps based on a condition.

### Example Chain Configuration

```lua
default_chain = {
  name = "Default Workflow",
  description = "A basic chain to guide coding tasks.",
  steps = {
    -- Steps definitions...
  },
}
```

## Executing a Chain

Use the `:LChainExecute` command to open a Telescope picker where you can select and execute a defined chain.

## Editing Chains

Edit the `chains.lua` file using the `:LChainEdit` command. After making changes, reload the configurations with `:LChainReload`.

## Example Use Case

1. **Select Context Documents:** Choose the relevant files/documents.
2. **Input Coding Task:** Enter the specific coding challenge.
3. **System Design:** An LLM designs the system and lists tasks.
4. **Code Generation:** Another LLM generates code based on tasks and context.
5. **Diff Generation:** A final LLM creates a unified diff of the changes.
6. **Approval:** Review and approve the diff.
7. **Apply Changes:** The diff is patched to your repository.
