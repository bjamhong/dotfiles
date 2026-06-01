# Worktree repository settings and file sync helpers.

function _wt_main_worktree() {
  git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | head -1
}

function _wt_default_copy_paths() {
  echo "notes"
}

function _wt_copy_env_enabled() {
  local value="$(git config --local --type=bool --get ben.worktree.copyEnvFiles 2>/dev/null)"

  if [ -z "$value" ]; then
    echo "true"
  else
    echo "$value"
  fi
}

function _wt_copy_paths_customized() {
  local value="$(git config --local --type=bool --get ben.worktree.copyPathsCustomized 2>/dev/null)"

  if [ -z "$value" ]; then
    echo "false"
  else
    echo "$value"
  fi
}

function _wt_get_copy_paths() {
  if [ "$(_wt_copy_paths_customized)" = "true" ]; then
    git config --local --get-all ben.worktree.copyPath 2>/dev/null
  else
    _wt_default_copy_paths
  fi
}

function _wt_normalize_copy_path() {
  local copy_path="$1"

  copy_path="${copy_path#./}"
  copy_path="${copy_path%/}"

  if [ -z "$copy_path" ] || [ "$copy_path" = "." ]; then
    return 1
  fi

  echo "$copy_path"
}

function _wt_set_copy_paths() {
  local copy_path=""
  local normalized=""

  git config --local ben.worktree.copyPathsCustomized true || return 1
  git config --local --unset-all ben.worktree.copyPath 2>/dev/null || true

  for copy_path in "$@"; do
    normalized="$(_wt_normalize_copy_path "$copy_path")" || continue
    git config --local --add ben.worktree.copyPath "$normalized" || return 1
  done
}

function _wt_reset_copy_paths() {
  git config --local --unset ben.worktree.copyPathsCustomized 2>/dev/null || true
  git config --local --unset-all ben.worktree.copyPath 2>/dev/null || true
}

function _wt_managed_dir() {
  local main_worktree="$(_wt_main_worktree)"
  if [ -z "$main_worktree" ]; then
    return 1
  fi

  echo "$(dirname "$main_worktree")/$(basename "$main_worktree")-worktrees"
}

function _wt_is_managed_worktree() {
  local wt_root="$1"
  local managed_dir="$(_wt_managed_dir)"

  if [ -z "$managed_dir" ]; then
    return 1
  fi

  [[ -n "$wt_root" && "$wt_root" == "$managed_dir"/* ]]
}

function _wt_cleanup_managed_dir() {
  local managed_dir="$(_wt_managed_dir)"

  if [ -z "$managed_dir" ]; then
    return 1
  fi

  if [ -d "$managed_dir" ]; then
    rmdir "$managed_dir" 2>/dev/null
  fi
}

function _wt_sync_env_files() {
  local source_dir="$1"
  local wt_path="$2"
  local env_file=""

  if [ "$(_wt_copy_env_enabled)" != "true" ]; then
    return 0
  fi

  for env_file in .env .env.local; do
    if [ -f "$source_dir/$env_file" ] && [ ! -e "$wt_path/$env_file" ]; then
      ln -s "$source_dir/$env_file" "$wt_path/$env_file" || return 1
    fi
  done
}

function _wt_sync_copy_paths() {
  local source_dir="$1"
  local wt_path="$2"
  local raw_path=""
  local normalized=""

  while IFS= read -r raw_path; do
    [ -z "$raw_path" ] && continue

    normalized="$(_wt_normalize_copy_path "$raw_path")" || continue

    if [ -d "$source_dir/$normalized" ]; then
      mkdir -p "$wt_path/$normalized" || return 1
      rsync -a "$source_dir/$normalized/" "$wt_path/$normalized/" || return 1
    elif [ -e "$source_dir/$normalized" ]; then
      mkdir -p "$wt_path/$(dirname "$normalized")" || return 1
      rsync -a "$source_dir/$normalized" "$wt_path/$normalized" || return 1
    else
      echo "Skipping missing path: $normalized"
    fi
  done < <(_wt_get_copy_paths)
}
