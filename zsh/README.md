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
| `functions.zsh` | Entry point for aliases and non-worktree shell functions |
| `worktree/worktree.zsh` | Worktree helpers, MRU cache, picker UI, and `wt*` commands |
| `dashboard.zsh` | Tmux dashboard UI (sourced by `functions.zsh`) |
| `claude-ui-patterns.md` | Design notes on Claude Code's terminal UI patterns |

## Aliases

| Alias | Description |
|-------|-------------|
| `claude` | Claude Code with `--dangerously-skip-permissions` |

## Command Wrappers

| Command | Description |
|---------|-------------|
| `codex` | Runs `codex --yolo ...` by default |

Use `command codex ...` to bypass the wrapper for a one-off non-yolo invocation.

## Functions

### AI

| Command | Description |
|---------|-------------|
| `run <prompt>` | Natural language to bash — executes the command |
| `ask <prompt>` | Natural language to bash — prints only (preview) |

### Worktree Management

Managed worktrees are created next to the main repo:
`../<project-name>-worktrees/<worktree-name>`

| Command | Description |
|---------|-------------|
| `wt` | Interactive worktree switcher (grouped, recent first within each section) + create new managed worktree |
| `wt help` | Show worktree command help |
| `wt settings` | Interactive per-repo worktree settings editor |
| `wt0` | Jump to base (main) worktree |
| `wtd` | Delete current managed worktree (checks for uncommitted and untracked changes) |
| `wtd!` | Force-delete current worktree |
| `wtls` | List all worktrees |

`wt` selection just changes directory into the selected worktree path.
The picker shows branch-attached worktrees first and detached-HEAD worktrees behind a separate section row.
Within each section, entries are ordered by MRU using a shared cache at
`$(git rev-parse --git-common-dir)/wt-mru.tsv`.
The cache is local-only, shared by all worktrees for the same repo, and is updated when:

1. `wt`, `wt0`, worktree creation, or `wtd` / `wtd!` change your active worktree
2. A local zsh shell starts in or `cd`s into a worktree
3. An interactive shell stays active in one worktree, throttled to once every 30 seconds

Stale cache entries are pruned automatically if a worktree disappears.
Press `Ctrl-D` from anywhere in the picker to open the detached-only view, and `Ctrl-D` there to return to the main list.
`wt settings` opens an interactive settings picker in a terminal: use the arrow keys to move, `Enter` to toggle/apply, and `Esc` to close.
Use `wt settings show` for the static boxed view.
When creating a new managed worktree, `wt` prompts for:

1. A worktree name used for the directory under `../<project-name>-worktrees/`
2. A branch name, defaulting to the worktree name

Creation flow:

1. `git fetch origin`
2. `git worktree add -b <branch> ../<project-name>-worktrees/<worktree-name> origin/main`
3. Symlink `.env` and `.env.local` into the new worktree if they exist and env syncing is enabled
4. Copy each configured extra path with `rsync` if it exists in the source repo
5. Print `Skipping missing path: ...` for configured extra paths that are absent in the source repo

If `wtd` or `wtd!` removes the last managed worktree, the empty `<project-name>-worktrees` directory is removed too.

Per-repo sync defaults:

1. `.env` and `.env.local` syncing is enabled
2. Extra copied paths default to `notes`

Per-repo settings are stored in the repo's local git config. Examples:

```zsh
# Open the interactive settings editor
wt settings

# Show the static settings view
wt settings show

# Turn env syncing off or on
wt settings env off
wt settings env on

# Add or remove copied paths for just this repo
wt settings copy add docs screenshots
wt settings copy remove notes

# Replace the copied-path list entirely
wt settings copy set notes scratch

# Copy nothing extra for this repo
wt settings copy clear

# Reset back to the default copied-path list (notes)
wt settings copy reset
```

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
