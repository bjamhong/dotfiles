# ZSH Dotfiles

Custom ZSH functions for terminal productivity.

## Structure

- `functions.zsh` - Entry point plus non-worktree shell functions
- `worktree/worktree.zsh` - Worktree helpers, UI, and `wt*` commands

## Key Concepts

### Worktree Organization

Managed worktrees are stored next to the main repo in `../<project-name>-worktrees/<worktree-name>`.

### Function Categories

1. **Worktree functions** (`wt`, `wt0`, `wtd`, `wtd!`, `wtls`) - Git worktree management
2. **Tmux functions** (`tmux4`, `tmuxa`) - iTerm2 tmux integration

## Adding New Functions

1. Add worktree-related functions to `worktree/worktree.zsh`; add other shell functions to `functions.zsh`
2. Update README.md with usage docs
3. Commit and push

## Conventions

- Functions should be self-contained
- Include usage help when arguments are missing
- Use local variables to avoid polluting global scope
- Check for collisions before creating branches/directories
- Use safety checks before destructive operations (e.g., wtd checks for uncommitted changes)
