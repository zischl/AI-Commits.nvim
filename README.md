# AI-Commits.nvim

AI-powered conventional git commit message generator for Neovim, using Google Gemini.
Altho it's only for gemini rn, will add others later.

## Features

- Generates clean, conventional git commit messages based on staged changes (`git diff --staged`).
- Older commit messages can be utilized for even more context.
- Streams response directly into your active git commit buffer in real-time.
- Uses Google Gemini API (default model: `gemini-2.5-flash`).
- Easy setup with flexible configuration.

## Requirements

- Neovim >= 0.8
- `curl` installed and available in `$PATH`
- `GEMINI_API_KEY` set in your environment variables

## Installation

### With [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
  "zischl/AI-Commits.nvim",
  cmd = { "AICommit", "GitAICommit" },
  ft = "gitcommit",
  keys = {
    { "<leader>gc", "<cmd>AICommit<cr>", ft = "gitcommit", desc = "Generate AI Commit Msg" },
  },
  opts = {
    model = "gemini-2.5-flash",
    temperature = 0.2,
  },
}
```

## Configuration

Default options:

```lua
require("ai-commits").setup({
  model = "gemini-2.5-flash",
  temperature = 0.2,
  include_history = true, -- Include recent commit messages for context and style
  history_count = 10,     -- Number of recent commit messages to include
  prompt = [[
You are an expert developer. Generate a clean, conventional git commit message based on the staged changes.
If recent commit messages are provided below, analyze them to see if this commit is related and match the 
repository's writing style, scope conventions, and tone.
Strictly adhere to this format:
1. The first line must be a concise, single-line summary prefixing a dash and a space.
2. Followed by exactly one blank line.
3. Followed by a detailed dash plus space prefixed list explaining the specific changes.

Generate only the commit message text.
]],
})
```

## Usage

1. Stage your changes using `git add`.
2. Open a git commit message buffer (e.g. `git commit` or inside Neovim).
3. Run `:AICommit` or press `<leader>gc` to generate the commit message.

## License

MIT
