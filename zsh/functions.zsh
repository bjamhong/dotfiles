# Custom ZSH Functions

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
  for env_file in "$source_dir"/.env*(N); do
    ln -s "$env_file" "$wt_path/$(basename "$env_file")" && echo "Symlinked $(basename "$env_file")"
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

# Create tmux session with iTerm2 integration (-CC) and 2x2 grid
function tmux4() {
  local session_name="${1:-main}"
  local start_dir="${PWD}"

  # Create detached session with 4 panes, then apply tiled layout
  tmux new-session -d -s "$session_name" -c "$start_dir"
  tmux split-window -t "$session_name" -c "$start_dir"
  tmux split-window -t "$session_name" -c "$start_dir"
  tmux split-window -t "$session_name" -c "$start_dir"
  tmux select-layout -t "$session_name" tiled

  # Attach with iTerm2 integration
  tmux -CC attach -t "$session_name"
}

# Reattach to tmux session
# Usage: tmuxa [session_name]
function tmuxa() {
  local session_name="${1:-main}"
  tmux -CC attach -t "$session_name"
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
