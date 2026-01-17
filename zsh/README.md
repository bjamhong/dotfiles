# zsh-vibecoded-shortcuts

Custom ZSH functions for productivity workflows.

## Installation

Add to your `~/.zshrc`:

```zsh
source "$HOME/dev/dotfiles/zsh/functions.zsh"
```

Then reload: `source ~/.zshrc`

## Functions

### Worktree Management

Worktrees are organized by project: `~/.ben-worktrees/<project-name>/<branch-name>`

#### `wt`

Switch between worktrees or create a new one (requires fzf). New worktrees are created from current HEAD with `.env*` files symlinked.

```bash
wt  # Opens fzf picker - select a worktree or "+ Create new worktree"
```

#### `wt0`

Jump to the base (main) worktree from any worktree.

```bash
wt0  # Returns to the main repository
```

#### `wtd` / `wtd!`

Delete the current worktree and return to main repo.

```bash
wtd   # Safe delete (checks for uncommitted changes first)
wtd!  # Force delete (even with uncommitted changes)
```

#### `wtrename <new-name>`

Rename the current worktree's branch and directory.

```bash
wtrename feature/new-name  # Renames branch and moves directory
```

#### `wtls`

List all worktrees.

```bash
wtls  # Runs git worktree list
```

### Git Shortcuts

#### `gpush`

Push current branch to origin with upstream tracking.

```bash
gpush  # Pushes current branch to origin
```

#### `gpr`

Create a GitHub PR for the current branch (wrapper around `gh pr create`).

```bash
gpr                    # Create PR interactively
gpr --title "My PR"    # Pass arguments to gh pr create
```

#### `pmain`

Pull origin/main into the current branch.

```bash
pmain  # git pull origin main
```

#### `save [commit message]`

Stage all changes, commit, and push in one command.

```bash
save              # Commits as "wip" and pushes
save fixed bug    # Commits as "fixed bug" and pushes
```

### Tmux

#### `tmux4 [session_name]`

Creates a tmux session with iTerm2 integration (`-CC` flag) and a 2x2 grid of panes.

```bash
tmux4           # Creates session named "main"
tmux4 myproject # Creates session named "myproject"
```

#### `tmuxa [session_name]`

Reattach to a tmux session with iTerm2 integration.

```bash
tmuxa           # Attach to "main"
tmuxa myproject # Attach to "myproject"
```
