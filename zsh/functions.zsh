# ZSH extension loader.

typeset -g DOTFILES_ZSH_DIR="${0:A:h}"
typeset -g DOTFILES_ZSH_EXTENSIONS_DIR="$DOTFILES_ZSH_DIR/extensions"

source "$DOTFILES_ZSH_EXTENSIONS_DIR/claude/claude.zsh"
source "$DOTFILES_ZSH_EXTENSIONS_DIR/codex/codex.zsh"
source "$DOTFILES_ZSH_EXTENSIONS_DIR/env/loadenv.zsh"
source "$DOTFILES_ZSH_EXTENSIONS_DIR/md/md.zsh"
source "$DOTFILES_ZSH_EXTENSIONS_DIR/tmux/tmux.zsh"
source "$DOTFILES_ZSH_EXTENSIONS_DIR/worktree/worktree.zsh"
