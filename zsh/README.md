# zsh-vibecoded-shortcuts

Custom ZSH functions for productivity workflows.

## Installation

Add to your `~/.zshrc`:

```zsh
source "$HOME/dev/dotfiles/zsh/functions.zsh"
```

Then reload: `source ~/.zshrc`

## Structure

| File | Purpose |
|------|---------|
| `functions.zsh` | All shell functions and aliases (entry point) |
| `dashboard.zsh` | Tmux dashboard UI (sourced by functions.zsh) |
| `claude-ui-patterns.md` | Design notes on Claude Code's terminal UI patterns |

## Aliases

| Alias | Description |
|-------|-------------|
| `claude` | Claude Code with `--dangerously-skip-permissions` |

## Functions

### AI

| Command | Description |
|---------|-------------|
| `run <prompt>` | Natural language to bash — executes the command |
| `ask <prompt>` | Natural language to bash — prints only (preview) |

### Worktree Management

Worktrees are organized by project: `~/.ben-worktrees/<project-name>/<branch-name>`

| Command | Description |
|---------|-------------|
| `wt` | Interactive worktree switcher (fzf) + create new |
| `wt0` | Jump to base (main) worktree |
| `wtd` | Delete current worktree (checks for uncommitted changes) |
| `wtd!` | Force-delete current worktree |
| `wtls` | List all worktrees |
| `wtrename <name>` | Rename current worktree's branch + directory |

### Git

| Command | Description |
|---------|-------------|
| `gpush` | Push current branch to origin with `-u` |
| `pmain` | Pull `origin/main` into current branch |
| `save [msg]` | `add -A` + commit + push (defaults to "wip") |
| `gpr` | Create a PR via `gh pr create` |

### Tmux

Terminal-aware: uses Ghostty AppleScript for native tabs on macOS, `-CC` for iTerm2, plain tmux elsewhere.

| Command | Description |
|---------|-------------|
| `tmux2`..`tmux8` | Session with N tabs, each with 2 side-by-side panes |
| `tmuxp [name]` | Session with 2x2 pane grid |
| `tmuxa [name]` | Reattach to a session (reopens Ghostty tabs) |
| `tkill <name>` | Kill session + grouped sessions |

#### Ghostty Dashboard

When running in Ghostty, `tmux2`-`tmux8` and `tmuxa` open an interactive dashboard in the first tab:

```
  ╭─ tmux: myproject ──────────────────────────────
  │
  │  ●  0  zsh             2 panes  zsh
  │  ●  1  zsh             2 panes  zsh
  │
  ╰────────────────────────────────────────────────

    a add   d delete   r rename   q detach   x kill
```

| Key | Action |
|-----|--------|
| `a` | Add a new window + open Ghostty tab |
| `d` | Delete a window by index |
| `r` | Rename a window |
| `q` | Detach (keep session alive for `tmuxa`) |
| `x` | Kill entire session |
