# ZSH Dotfiles

Custom ZSH functions for terminal productivity.

## Structure

- `functions.zsh` - All custom shell functions

## Key Concepts

### Worktree Organization

Worktrees are stored in `~/.ben-worktrees/<project-name>/<branch-name>` to avoid collisions between projects.

### Function Categories

1. **Worktree functions** (`wt`, `wt0`, `wtd`, `wtd!`, `wtrename`, `wtls`) - Git worktree management
2. **Git shortcuts** (`gpush`, `gpr`, `pmain`, `save`) - Common git operations
3. **Tmux functions** (`tmux4`, `tmuxa`) - iTerm2 tmux integration

## Adding New Functions

1. Add the function to `functions.zsh`
2. Update README.md with usage docs
3. Commit and push

## Conventions

- Functions should be self-contained
- Include usage help when arguments are missing
- Use local variables to avoid polluting global scope
- Check for collisions before creating branches/directories
- Use safety checks before destructive operations (e.g., wtd checks for uncommitted changes)
