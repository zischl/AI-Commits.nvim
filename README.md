# AI-Commits.nvim

AI-powered conventional git commit message generator for Neovim, using Google Gemini.
Altho it's only for gemini rn, will add others later.

## Features

- Generates clean, conventional git commit messages based on staged changes (`git diff --staged`).
- Analyzes recent commit history to match your repository's conventions and style.
- Streams responses directly into your active git commit buffer in real-time.
- **Global / Lazygit Support**: If invoked from a terminal, Lazygit, or code buffer where no `gitcommit` buffer is open, it automatically opens a floating window with the generated commit message!
- Uses Google Gemini API (default model: `gemini-2.5-flash`).

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
  keys = {
    { "<leader>gc", "<cmd>AICommit<cr>", desc = "Generate AI Commit Msg" },
  },
  opts = {
    model = "gemini-2.5-flash",
    temperature = 0.2,
    include_history = true,
    history_count = 3,
  },
}
```

## Configuration

Default options:

```lua
require("ai-commits").setup({
  model = "gemini-2.5-flash",
  temperature = 0.2,
  include_history = true,
  history_count = 3,
  prompt = [[
You are an expert developer. Generate a clean, conventional git commit message based on the staged changes.
If recent commit messages are provided below, analyze them to see if this commit is related and match the repository's writing style, scope conventions, and tone.
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
2. Press `<leader>gc` or run `:AICommit` from anywhere (Lazygit, terminal, or any buffer).
   - If you are inside a `gitcommit` buffer, the generated message streams into your current buffer.
   - If invoked from anywhere else, a **floating window** pops up and streams the AI commit message. Press `q`, `Q` or `<Esc>` to close the floating window.

## License

MIT
