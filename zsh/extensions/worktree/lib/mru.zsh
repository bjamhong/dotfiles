# Worktree MRU cache and shell hooks.

typeset -g WT_MRU_FILE_NAME='wt-mru.tsv'
typeset -gi WT_MRU_REFRESH_INTERVAL=30
typeset -gi WT_MRU_LAST_REFRESH_TS=0
typeset -g WT_MRU_LAST_PROBED_PWD=''
typeset -g WT_MRU_LAST_PROBED_ROOT=''
typeset -g WT_MRU_HOOKS_INSTALLED=0
typeset -ga WT_MRU_CACHE_PATHS
typeset -gA WT_MRU_CACHE_MAP

function _wt_now_epoch() {
  if [ -n "${EPOCHSECONDS:-}" ]; then
    printf '%s\n' "$EPOCHSECONDS"
  else
    date +%s
  fi
}

function _wt_git_common_dir() {
  local common_dir="$(git rev-parse --git-common-dir 2>/dev/null)"

  if [ -z "$common_dir" ]; then
    return 1
  fi

  if [[ "$common_dir" = /* ]]; then
    printf '%s\n' "$common_dir"
  else
    printf '%s\n' "${common_dir:A}"
  fi
}

function _wt_mru_file() {
  local common_dir="$(_wt_git_common_dir)"

  if [ -z "$common_dir" ]; then
    return 1
  fi

  printf '%s\n' "$common_dir/$WT_MRU_FILE_NAME"
}

function _wt_load_mru_cache() {
  local mru_file="$(_wt_mru_file)"
  local wt_path=""
  local recent_ts=""

  WT_MRU_CACHE_PATHS=()
  WT_MRU_CACHE_MAP=()

  if [ -z "$mru_file" ]; then
    return 0
  fi

  if [ ! -f "$mru_file" ]; then
    return 0
  fi

  while IFS=$'\t' read -r wt_path recent_ts; do
    [ -z "$wt_path" ] && continue

    if [[ ! "$recent_ts" == <-> ]]; then
      recent_ts=0
    fi

    if [ "${+WT_MRU_CACHE_MAP[$wt_path]}" -eq 0 ]; then
      WT_MRU_CACHE_PATHS+=("$wt_path")
    fi

    WT_MRU_CACHE_MAP[$wt_path]="$recent_ts"
  done < "$mru_file"
}

function _wt_write_loaded_mru_cache() {
  local mru_file="$(_wt_mru_file)"
  local mru_dir="${mru_file:h}"
  local tmp_file=""
  local wt_path=""
  local wrote_any=0

  if [ -z "$mru_file" ]; then
    return 0
  fi

  mkdir -p "$mru_dir" 2>/dev/null || return 0
  tmp_file="$(mktemp "$mru_dir/.wt-mru.XXXXXX" 2>/dev/null)" || return 0

  for wt_path in "${WT_MRU_CACHE_PATHS[@]}"; do
    if [ "${+WT_MRU_CACHE_MAP[$wt_path]}" -eq 0 ]; then
      continue
    fi

    printf '%s\t%s\n' "$wt_path" "${WT_MRU_CACHE_MAP[$wt_path]}" >> "$tmp_file" || {
      rm -f "$tmp_file"
      return 0
    }
    wrote_any=1
  done

  if [ "$wrote_any" -eq 1 ]; then
    mv "$tmp_file" "$mru_file" 2>/dev/null || rm -f "$tmp_file"
  else
    rm -f "$tmp_file"
    rm -f "$mru_file" 2>/dev/null || true
  fi
}

function _wt_prune_loaded_mru_cache() {
  local -A live_paths
  local -a kept_paths
  local wt_path=""
  local dirty=0

  for wt_path in "$@"; do
    live_paths[$wt_path]=1
  done

  kept_paths=()

  for wt_path in "${WT_MRU_CACHE_PATHS[@]}"; do
    if [ "${+live_paths[$wt_path]}" -eq 1 ]; then
      kept_paths+=("$wt_path")
    else
      unset "WT_MRU_CACHE_MAP[$wt_path]"
      dirty=1
    fi
  done

  WT_MRU_CACHE_PATHS=("${kept_paths[@]}")
  return "$dirty"
}

function _wt_mark_path_recent() {
  local wt_path="$1"
  local now_ts="${2:-$(_wt_now_epoch)}"

  [ -z "$wt_path" ] && return 0

  _wt_load_mru_cache

  if [ "${+WT_MRU_CACHE_MAP[$wt_path]}" -eq 0 ]; then
    WT_MRU_CACHE_PATHS+=("$wt_path")
  fi

  WT_MRU_CACHE_MAP[$wt_path]="$now_ts"
  _wt_write_loaded_mru_cache
}

function _wt_remove_path_recent() {
  local wt_path="$1"
  local -a kept_paths
  local cached_path=""

  [ -z "$wt_path" ] && return 0

  _wt_load_mru_cache

  if [ "${+WT_MRU_CACHE_MAP[$wt_path]}" -eq 0 ]; then
    return 0
  fi

  unset "WT_MRU_CACHE_MAP[$wt_path]"
  kept_paths=()

  for cached_path in "${WT_MRU_CACHE_PATHS[@]}"; do
    if [ "$cached_path" != "$wt_path" ]; then
      kept_paths+=("$cached_path")
    fi
  done

  WT_MRU_CACHE_PATHS=("${kept_paths[@]}")
  _wt_write_loaded_mru_cache
}

function _wt_current_worktree_root() {
  local wt_root=""

  if [ "$WT_MRU_LAST_PROBED_PWD" = "$PWD" ]; then
    printf '%s\n' "$WT_MRU_LAST_PROBED_ROOT"
    return 0
  fi

  wt_root="$(git rev-parse --show-toplevel 2>/dev/null)"
  WT_MRU_LAST_PROBED_PWD="$PWD"
  WT_MRU_LAST_PROBED_ROOT="$wt_root"

  printf '%s\n' "$wt_root"
}

function _wt_mark_current_worktree_recent() {
  local wt_root="$(_wt_current_worktree_root)"
  local now_ts="${1:-$(_wt_now_epoch)}"

  if [ -z "$wt_root" ]; then
    return 0
  fi

  _wt_mark_path_recent "$wt_root" "$now_ts"
}

function _wt_chpwd_hook() {
  local now_ts="$(_wt_now_epoch)"

  WT_MRU_LAST_PROBED_PWD=''
  WT_MRU_LAST_PROBED_ROOT=''
  WT_MRU_LAST_REFRESH_TS="$now_ts"
  _wt_mark_current_worktree_recent "$now_ts" >/dev/null 2>&1
}

function _wt_precmd_hook() {
  local now_ts=0

  if ! [[ -o interactive ]]; then
    return 0
  fi

  now_ts="$(_wt_now_epoch)"
  if [ $(( now_ts - WT_MRU_LAST_REFRESH_TS )) -lt "$WT_MRU_REFRESH_INTERVAL" ]; then
    return 0
  fi

  _wt_mark_current_worktree_recent "$now_ts" >/dev/null 2>&1
  WT_MRU_LAST_REFRESH_TS="$now_ts"
}

function _wt_install_hooks() {
  local now_ts="$(_wt_now_epoch)"

  typeset -gaU chpwd_functions precmd_functions

  if [ "$WT_MRU_HOOKS_INSTALLED" -eq 0 ]; then
    chpwd_functions+=(_wt_chpwd_hook)
    precmd_functions+=(_wt_precmd_hook)
    WT_MRU_HOOKS_INSTALLED=1
  fi

  WT_MRU_LAST_REFRESH_TS="$now_ts"
  _wt_mark_current_worktree_recent "$now_ts" >/dev/null 2>&1
}
