# Worktree creation, deletion, switching, and Ghostty actions.

function _gwt_create() {
  _wt_theme_init

  local source_dir="$(git rev-parse --show-toplevel 2>/dev/null)"
  local managed_dir="$(_wt_managed_dir)"
  local wt_name=""
  local new_branch=""

  if [ -z "$source_dir" ] || [ -z "$managed_dir" ]; then
    echo "Not in a git repository"
    return 1
  fi

  if [ ! -r /dev/tty ]; then
    echo "Interactive terminal required to create a worktree"
    return 1
  fi

  printf '\n%bNew worktree name:%b ' "$WT_C_ACCENT" "$WT_C_RESET" > /dev/tty
  IFS= read -r wt_name < /dev/tty || {
    printf '\n' > /dev/tty
    echo "Cancelled"
    return 1
  }

  if [ -z "$wt_name" ]; then
    echo "Cancelled"
    return 1
  fi

  if [[ "$wt_name" == */* ]]; then
    echo "Worktree name cannot contain '/'"
    return 1
  fi

  local default_branch="$wt_name"
  printf '%bNew branch name [%s]:%b ' "$WT_C_ACCENT" "$default_branch" "$WT_C_RESET" > /dev/tty
  IFS= read -r new_branch < /dev/tty || {
    printf '\n' > /dev/tty
    echo "Cancelled"
    return 1
  }
  new_branch="${new_branch:-$default_branch}"

  local wt_path="$managed_dir/$wt_name"

  if git show-ref --verify --quiet "refs/heads/$new_branch"; then
    echo "Branch '$new_branch' already exists"
    return 1
  fi

  if [ -d "$wt_path" ]; then
    echo "Directory '$wt_path' already exists"
    return 1
  fi

  mkdir -p "$managed_dir" || return 1
  git fetch origin || {
    _wt_cleanup_managed_dir
    return 1
  }

  git worktree add -b "$new_branch" "$wt_path" origin/main || {
    _wt_cleanup_managed_dir
    return 1
  }

  _wt_sync_env_files "$source_dir" "$wt_path" || return 1
  _wt_sync_copy_paths "$source_dir" "$wt_path" || return 1

  cd "$wt_path"
}

function _wt_confirm() {
  local prompt="$1"
  local reply=""

  if [ ! -r /dev/tty ]; then
    return 1
  fi

  printf '\n%s [y/N]: ' "$prompt" > /dev/tty
  IFS= read -r reply < /dev/tty || {
    printf '\n' > /dev/tty
    return 1
  }
  printf '\n' > /dev/tty

  [[ "$reply" = [Yy] || "$reply" = [Yy][Ee][Ss] ]]
}

function _wt_delete_worktree_path() {
  local wt_root="$1"
  local force_delete="${2:-false}"
  local main_worktree="$(_wt_main_worktree)"
  local managed_dir="$(_wt_managed_dir)"
  local branch_name="$(git -C "$wt_root" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  local current_root="$(git rev-parse --show-toplevel 2>/dev/null)"
  local remove_args=()

  if [ -z "$wt_root" ] || [ -z "$main_worktree" ]; then
    echo "Not in a git repository"
    return 1
  fi

  if [ "$wt_root" = "$main_worktree" ] || ! _wt_is_managed_worktree "$wt_root"; then
    echo "Not in a managed worktree"
    return 1
  fi

  if [ "$force_delete" != "true" ] && [ -n "$(git -C "$wt_root" status --porcelain 2>/dev/null)" ]; then
    echo "Worktree has uncommitted or untracked changes. Use 'wtd!' to force delete."
    return 1
  fi

  if [ "$current_root" = "$wt_root" ]; then
    cd "$main_worktree" || return 1
  fi

  remove_args=()
  if [ "$force_delete" = "true" ]; then
    remove_args+=(--force)
  fi

  git -C "$main_worktree" worktree remove "${remove_args[@]}" "$wt_root" 2>/dev/null || {
    git -C "$main_worktree" worktree prune
    rm -rf "$wt_root"
  }

  if [ -n "$branch_name" ] && [ "$branch_name" != "HEAD" ]; then
    git -C "$main_worktree" branch -D "$branch_name" 2>/dev/null
  fi
  _wt_remove_path_recent "$wt_root" >/dev/null 2>&1

  local cleanup_message=""
  if [ -n "$managed_dir" ] && [ -d "$managed_dir" ] && rmdir "$managed_dir" 2>/dev/null; then
    cleanup_message=" Removed empty $(basename "$managed_dir")."
  fi

  echo "Removed worktree + branch '$branch_name', returned to $main_worktree.$cleanup_message"
}

function _wt_open_path_in_ghostty_tab() {
  local wt_path="$1"
  local shell_command=""

  if [ -z "$wt_path" ]; then
    return 1
  fi

  if ! command -v osascript >/dev/null 2>&1; then
    echo "Opening a new tab is only supported via Ghostty on macOS."
    return 1
  fi

  shell_command="cd ${(q)wt_path}"

  osascript <<APPLESCRIPT >/dev/null
tell application "Ghostty"
  activate
  if (count windows) = 0 then
    create window
  end if
  tell front window to create tab
  delay 0.1
  set t to selected tab of front window
  delay 0.1
  input text "${shell_command}" to t
end tell
APPLESCRIPT
}

function wtd() {
  local wt_root="$(git rev-parse --show-toplevel 2>/dev/null)"
  _wt_delete_worktree_path "$wt_root" false
}

function wtd!() {
  local wt_root="$(git rev-parse --show-toplevel 2>/dev/null)"
  _wt_delete_worktree_path "$wt_root" true
}

function wt0() {
  local main_worktree="$(_wt_main_worktree)"

  if [ -z "$main_worktree" ]; then
    echo "Not in a git repository"
    return 1
  fi

  cd "$main_worktree" || return 1
  echo "Switched to base worktree: $main_worktree"
}
