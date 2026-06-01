# ZSH Dotfiles

Development context for agents editing this directory.

## Entry Point

`functions.zsh` is the only file sourced directly from `~/.zshrc`. Keep it as a small loader that sources extension entrypoints.

Current loader order:

1. `extensions/claude/claude.zsh`
2. `extensions/codex/codex.zsh`
3. `extensions/env/loadenv.zsh`
4. `extensions/md/md.zsh`
5. `extensions/tmux/tmux.zsh`
6. `extensions/worktree/worktree.zsh`

## Extension Layout

- `extensions/claude/claude.zsh`: Claude Code aliases.
- `extensions/codex/codex.zsh`: Codex command wrappers.
- `extensions/env/loadenv.zsh`: local environment helpers.
- `extensions/md/md.zsh`: Markdown viewing aliases.
- `extensions/tmux/tmux.zsh`: tmux cleanup helpers.
- `extensions/worktree/worktree.zsh`: worktree extension entrypoint.

## Worktree Modules

Worktree internals live under `extensions/worktree/lib/`.

- `config.zsh`: repo settings, managed directory paths, env/copy sync.
- `mru.zsh`: MRU cache and shell hooks.
- `status.zsh`: Git status metadata and worktree ranking.
- `ui.zsh`: terminal UI helpers, picker rows, static list, help.
- `actions.zsh`: create, delete, switch, and Ghostty tab actions.
- `settings.zsh`: `wt settings` UI and subcommands.
- `commands.zsh`: public `wt` / `wtls` commands and picker loop.

Managed worktrees are stored next to the main repo in `../<project-name>-worktrees/<worktree-name>`.

## Editing Guidelines

- Add worktree-related code to the matching `extensions/worktree/lib/*.zsh` module.
- Add non-worktree shell helpers to a focused module under `extensions/`.
- Source new modules from `functions.zsh`.
- Keep installer-managed machine setup in `~/.zshrc` or `~/.zshrc.local`, not in tracked extensions.
- Include usage help when functions require arguments.
- Use local variables to avoid polluting global scope.
- Check for branch/directory collisions before creating worktrees.
- Keep safety checks before destructive operations.
- Update `README.md` when user-facing commands or install steps change.

## Verification

Run syntax checks:

```zsh
zsh -n zsh/functions.zsh zsh/extensions/**/*.zsh
```

Run worktree smoke tests:

```zsh
zsh zsh/extensions/worktree/tests/smoke.zsh
```
