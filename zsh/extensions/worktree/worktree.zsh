# Git worktree helpers and commands.

typeset -g WT_EXTENSION_DIR="${${(%):-%x}:A:h}"
typeset -g WT_EXTENSION_ENTRYPOINT="$WT_EXTENSION_DIR/worktree.zsh"

source "$WT_EXTENSION_DIR/lib/config.zsh"
source "$WT_EXTENSION_DIR/lib/mru.zsh"
source "$WT_EXTENSION_DIR/lib/ui.zsh"
source "$WT_EXTENSION_DIR/lib/status.zsh"
source "$WT_EXTENSION_DIR/lib/actions.zsh"
source "$WT_EXTENSION_DIR/lib/settings.zsh"
source "$WT_EXTENSION_DIR/lib/commands.zsh"
