# Custom ZSH Functions

# Claude Code with auto-accept permissions
alias claude='claude --dangerously-skip-permissions'

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

# Helper: create a new worktree from current HEAD
function _gwt_create() {
  echo -n "New branch name: "
  read new_branch
  if [ -z "$new_branch" ]; then
    echo "Cancelled"
    return 1
  fi

  local source_dir="$(git rev-parse --show-toplevel)"
  local main_worktree="$(git worktree list --porcelain | head -1 | cut -d' ' -f2)"
  local project_name="$(basename "$main_worktree")"
  local wt_name="${new_branch//\//-}"
  local project_dir="$HOME/.ben-worktrees/$project_name"
  local wt_path="$project_dir/$wt_name"

  # Check if branch already exists
  if git show-ref --verify --quiet "refs/heads/$new_branch"; then
    echo "Branch '$new_branch' already exists"
    return 1
  fi

  # Check if directory already exists
  if [ -d "$wt_path" ]; then
    echo "Directory '$wt_path' already exists"
    return 1
  fi

  mkdir -p "$project_dir"
  git worktree add -b "$new_branch" "$wt_path" HEAD && \
  # Symlink all .env files preserving directory structure
  (cd "$source_dir" && find . -name '.env*' -type f ! -path '*/.venv/*' ! -path '*/node_modules/*') | while read f; do
    mkdir -p "$wt_path/$(dirname "$f")"
    ln -s "$source_dir/$f" "$wt_path/$f" && echo "Symlinked $f"
  done
  cd "$wt_path"
}

# Delete current worktree and return to main repo
# Usage: wtd (run from within a worktree)
function wtd() {
  local current_dir="$(pwd)"
  local wt_root="$(git rev-parse --show-toplevel)"
  local main_worktree="$(git worktree list --porcelain | head -1 | cut -d' ' -f2)"
  local branch_name="$(git rev-parse --abbrev-ref HEAD)"

  # Check if we're in a worktree (not the main one)
  if [ "$current_dir" = "$main_worktree" ] || [[ "$current_dir" != *"/.ben-worktrees/"* ]]; then
    echo "Not in a .ben-worktrees worktree"
    return 1
  fi

  # Safety check: ensure wt_root is within .ben-worktrees
  if [[ -z "$wt_root" ]] || [[ "$wt_root" != *"/.ben-worktrees/"* ]]; then
    echo "Safety check failed: worktree root '$wt_root' is not in .ben-worktrees"
    return 1
  fi

  # Check for uncommitted changes
  if ! git diff --quiet HEAD 2>/dev/null; then
    echo "Worktree has uncommitted changes. Use 'wtd!' to force delete."
    return 1
  fi

  # Change to main worktree first, then remove
  cd "$main_worktree" || return 1
  git worktree remove "$wt_root" 2>/dev/null || {
    # If remove fails, prune stale entries and delete directory manually
    git worktree prune
    rm -rf "$wt_root"
  }
  git branch -D "$branch_name" 2>/dev/null
  echo "Removed worktree + branch '$branch_name', returned to $main_worktree"
}

# Force delete worktree (even with uncommitted changes)
function wtd!() {
  local current_dir="$(pwd)"
  local wt_root="$(git rev-parse --show-toplevel)"
  local main_worktree="$(git worktree list --porcelain | head -1 | cut -d' ' -f2)"
  local branch_name="$(git rev-parse --abbrev-ref HEAD)"

  if [ "$current_dir" = "$main_worktree" ] || [[ "$current_dir" != *"/.ben-worktrees/"* ]]; then
    echo "Not in a .ben-worktrees worktree"
    return 1
  fi

  if [[ -z "$wt_root" ]] || [[ "$wt_root" != *"/.ben-worktrees/"* ]]; then
    echo "Safety check failed: worktree root '$wt_root' is not in .ben-worktrees"
    return 1
  fi

  cd "$main_worktree" || return 1
  git worktree remove --force "$wt_root" 2>/dev/null || {
    git worktree prune
    rm -rf "$wt_root"
  }
  git branch -D "$branch_name" 2>/dev/null
  echo "Removed worktree + branch '$branch_name', returned to $main_worktree"
}

# Jump to base (main) worktree
# Usage: wt0
function wt0() {
  local main_worktree="$(git worktree list --porcelain | head -1 | cut -d' ' -f2)"

  if [ -z "$main_worktree" ]; then
    echo "Not in a git repository"
    return 1
  fi

  cd "$main_worktree" || return 1
  echo "Switched to base worktree: $main_worktree"
}

# Switch to another worktree or create new (requires fzf)
# Usage: wt
function wt() {
  if ! command -v fzf &>/dev/null; then
    echo "fzf is required for interactive selection"
    return 1
  fi

  local worktrees="$(git worktree list 2>/dev/null)"
  if [ -z "$worktrees" ]; then
    echo "Not in a git repository"
    return 1
  fi

  local options="+ Create new worktree
$worktrees"
  local selected="$(echo "$options" | fzf --height=40% --reverse --prompt="Worktree: ")"
  if [ -z "$selected" ]; then
    return 0
  fi

  if [[ "$selected" == "+ Create new worktree" ]]; then
    _gwt_create
    return
  fi

  local wt_path="$(echo "$selected" | awk '{print $1}')"
  cd "$wt_path" || return 1
  echo "Switched to: $wt_path"
}

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
source "${0:A:h}/dashboard.zsh"

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

# Push current branch to origin with upstream tracking
# Usage: gpush
function gpush() {
  local branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"

  if [ -z "$branch" ]; then
    echo "Not in a git repository"
    return 1
  fi

  if [ "$branch" = "HEAD" ]; then
    echo "Detached HEAD state - cannot push"
    return 1
  fi

  echo "Pushing $branch to origin..."
  git push -u origin "$branch"
}

# Pull main branch into current branch
# Usage: pmain
function pmain() {
  local branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"

  if [ -z "$branch" ]; then
    echo "Not in a git repository"
    return 1
  fi

  echo "Pulling origin/main into $branch..."
  git pull origin main
}

# Commit all changes and push
# Usage: save [commit message]
function save() {
  local message="${*:-wip}"

  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Not in a git repository"
    return 1
  fi

  git add -A && git commit -m "$message" && gpush
}

# List all worktrees
# Usage: wtls
function wtls() {
  git worktree list
}

# Rename current worktree branch and directory
# Usage: wtrename <new-name>
function wtrename() {
  local new_name="$1"

  if [ -z "$new_name" ]; then
    echo "Usage: wtrename <new-branch-name>"
    return 1
  fi

  local wt_root="$(git rev-parse --show-toplevel 2>/dev/null)"
  local current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  local main_worktree="$(git worktree list --porcelain | head -1 | cut -d' ' -f2)"
  local project_name="$(basename "$main_worktree")"

  # Check we're in a worktree
  if [[ -z "$wt_root" ]] || [[ "$wt_root" != *"/.ben-worktrees/"* ]]; then
    echo "Not in a .ben-worktrees worktree"
    return 1
  fi

  # Normalize new name for directory (replace / with -)
  local new_dir_name="${new_name//\//-}"
  local project_dir="$HOME/.ben-worktrees/$project_name"
  local new_wt_path="$project_dir/$new_dir_name"

  # Check if branch already exists
  if git show-ref --verify --quiet "refs/heads/$new_name"; then
    echo "Branch '$new_name' already exists"
    return 1
  fi

  # Check if directory already exists
  if [ -d "$new_wt_path" ]; then
    echo "Directory '$new_wt_path' already exists"
    return 1
  fi

  # Rename branch
  git branch -m "$new_name" || return 1

  # Move worktree directory
  git worktree move "$wt_root" "$new_wt_path" || {
    # Rollback branch rename on failure
    git branch -m "$current_branch"
    echo "Failed to move worktree"
    return 1
  }

  cd "$new_wt_path" || return 1
  echo "Renamed '$current_branch' -> '$new_name'"
  echo "Moved to $new_wt_path"
}

# Create PR for current branch
# Usage: gpr
function gpr() {
  gh pr create "$@"
}

# Natural language to bash — runs the command
# Usage: run list all files sorted by size
function run() { eval "$(echo "Output ONLY a single bash command, no markdown, no explanation: $*" | claude -p --tools '')"; }

# Natural language to bash — prints the command only
# Usage: ask how to find large files over 100mb
function ask() { echo "Output ONLY a single bash command, no markdown, no explanation: $*" | claude -p --tools ''; }
