# Custom ZSH Functions

# Claude Code with auto-accept permissions
alias claude='claude --dangerously-skip-permissions'

# Codex with YOLO mode by default.
# Use `command codex ...` to bypass this wrapper for one-off non-yolo runs.
function codex() {
  command codex --yolo "$@"
}

# Kill tmux session and its grouped sessions
# Usage: tkill <session_name>
function tkill() {
  local session_name="$1"
  if [ -z "$session_name" ]; then
    echo "Usage: tkill <session_name>"
    return 1
  fi
  # Kill grouped sessions (created by Ghostty tab integration)
  for s in $(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^${session_name}-g"); do
    tmux kill-session -t "$s" 2>/dev/null
  done
  tmux kill-session -t "$session_name" 2>/dev/null
}

typeset -g DOTFILES_ZSH_DIR="${0:A:h}"

# Load worktree helpers and UI from a dedicated subtree.
source "$DOTFILES_ZSH_DIR/worktree/worktree.zsh"

# Create tmux session with 2x2 grid
# Usage: tmuxp [session_name]
function tmuxp() {
  local session_name="${1:-main}"
  local start_dir="${PWD}"

  # Create detached session with 4 panes, then apply tiled layout
  tmux new-session -d -s "$session_name" -c "$start_dir"
  tmux split-window -t "$session_name" -c "$start_dir"
  tmux split-window -t "$session_name" -c "$start_dir"
  tmux split-window -t "$session_name" -c "$start_dir"
  tmux select-layout -t "$session_name" tiled

  if [[ "$TERM_PROGRAM" == "iTerm.app" ]]; then
    tmux -CC attach -t "$session_name"
  else
    tmux attach -t "$session_name"
  fi
}

# Load tmux dashboard (separate file for organization)
source "$DOTFILES_ZSH_DIR/dashboard.zsh"

# Create tmux session with N tabs, each with 2 side-by-side panes
# In Ghostty: each tmux window gets its own native Ghostty tab, first tab is a dashboard
# In iTerm2: uses -CC control mode for native tab integration
# Usage: _tmux_tabs <num_tabs> [session_name]
function _tmux_tabs() {
  local num_tabs="$1"
  local session_name="${2:-main}"
  local start_dir="${PWD}"

  # Create session with first window, split into 2 panes
  tmux new-session -d -s "$session_name" -c "$start_dir"
  tmux split-window -h -t "${session_name}:0" -c "$start_dir"

  # Create remaining windows, each with 2 panes (explicit window targeting)
  for i in $(seq 2 "$num_tabs"); do
    local widx=$(tmux new-window -t "$session_name" -c "$start_dir" -P -F '#{window_index}')
    tmux split-window -h -t "${session_name}:${widx}" -c "$start_dir"
  done

  # Get actual window indices
  local windows=($(tmux list-windows -t "$session_name" -F '#{window_index}'))
  tmux select-window -t "$session_name:${windows[1]}"

  if [[ "$TERM_PROGRAM" == "ghostty" ]] && command -v osascript &>/dev/null; then
    # Open native Ghostty tabs for ALL windows using grouped sessions
    for i in $(seq 1 $num_tabs); do
      local win_idx="${windows[$i]}"
      local linked="${session_name}-g${win_idx}"
      tmux new-session -d -t "$session_name" -s "$linked"
      tmux select-window -t "$linked:${win_idx}"

      osascript <<APPLESCRIPT
tell application "Ghostty"
  new tab in front window
  delay 0.3
  set t to focused terminal of selected tab of front window
  input text "TMUX= tmux attach -t ${linked}" to t
  send key "enter" to t
end tell
APPLESCRIPT
    done
    sleep 0.3
    # First tab becomes the dashboard
    _tmux_dashboard "$session_name"
  elif [[ "$TERM_PROGRAM" == "iTerm.app" ]]; then
    tmux -CC attach -t "$session_name"
  else
    tmux attach -t "$session_name"
  fi
}

# Generate tmux2 through tmux8 for N tabs with 2 panes each
for i in {2..8}; do
  eval "function tmux${i}() { _tmux_tabs $i \"\$1\"; }"
done

# Reattach to tmux session
# In Ghostty: reopens native tabs for each tmux window + dashboard
# Usage: tmuxa [session_name]
function tmuxa() {
  local session_name="${1:-main}"

  if [[ "$TERM_PROGRAM" == "ghostty" ]] && command -v osascript &>/dev/null; then
    # Clean up stale grouped sessions from previous attach
    for s in $(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^${session_name}-g"); do
      tmux kill-session -t "$s" 2>/dev/null
    done

    local windows=($(tmux list-windows -t "$session_name" -F '#{window_index}' 2>/dev/null))
    if [ ${#windows[@]} -eq 0 ]; then
      echo "Session '$session_name' not found"
      return 1
    fi

    # Open Ghostty tabs for ALL windows
    for i in $(seq 1 ${#windows[@]}); do
      local win_idx="${windows[$i]}"
      local linked="${session_name}-g${win_idx}"
      tmux new-session -d -t "$session_name" -s "$linked"
      tmux select-window -t "$linked:${win_idx}"

      osascript <<APPLESCRIPT
tell application "Ghostty"
  new tab in front window
  delay 0.3
  set t to focused terminal of selected tab of front window
  input text "TMUX= tmux attach -t ${linked}" to t
  send key "enter" to t
end tell
APPLESCRIPT
    done

    sleep 0.3
    # First tab becomes the dashboard
    _tmux_dashboard "$session_name"
  elif [[ "$TERM_PROGRAM" == "iTerm.app" ]]; then
    tmux -CC attach -t "$session_name"
  else
    tmux attach -t "$session_name"
  fi
}

# Natural language to bash — runs the command
# Usage: run list all files sorted by size
function run() { eval "$(echo "Output ONLY a single bash command, no markdown, no explanation: $*" | claude -p --tools '')"; }

# Natural language to bash — prints the command only
# Usage: ask how to find large files over 100mb
function ask() { echo "Output ONLY a single bash command, no markdown, no explanation: $*" | claude -p --tools ''; }
