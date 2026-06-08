# ZSH Dotfiles

Modular ZSH helpers loaded from `~/.zshrc`.

## Install

```zsh
source "$HOME/dotfiles/zsh/functions.zsh"
```

## Layout

- `functions.zsh` loads each extension.
- `extensions/claude` defines Claude Code aliases.
- `extensions/codex` defines Codex wrappers.
- `extensions/env` defines environment helpers.
- `extensions/md` defines Markdown viewing aliases.
- `extensions/tmux` defines tmux cleanup helpers.
- `extensions/worktree` defines Git worktree commands.

## Commands

| Command | Description |
|---------|-------------|
| `codex` | Runs `codex --yolo ...` by default |
| `loadenv` | Sources `.env.local` into the current shell |
| `md` | Views Markdown with `glow -p`, when `glow` is installed |
| `tkill <name>` | Kills a tmux session and grouped sessions |
| `wt` | Opens the interactive worktree picker |
| `wt0` | Switches to the base worktree |
| `wtd` | Deletes the current managed worktree |
| `wtd!` | Force-deletes the current managed worktree |
| `wtls` | Lists worktrees |

Run worktree tests with:

```zsh
zsh zsh/extensions/worktree/tests/smoke.zsh
```
