# Worktree status metadata and ranking.

function _wt_status_meta_for_path() {
  local wt_path="$1"
  local status_output=""
  local line=""
  local tracked_dirty=0
  local untracked_dirty=0
  local conflicted=0
  local ahead=0
  local behind=0
  local ab_fields=()

  status_output="$(git -C "$wt_path" status --porcelain=v2 --branch --untracked-files=normal 2>/dev/null)" || {
    printf '0\t0\t0\t0\t0\n'
    return 0
  }

  while IFS= read -r line; do
    case "$line" in
      '# branch.ab '*)
        ab_fields=("${(s: :)line}")
        if [ "${#ab_fields[@]}" -ge 4 ]; then
          ahead="${ab_fields[3]#+}"
          behind="${ab_fields[4]#-}"
        fi
        ;;
      u\ *)
        conflicted=1
        ;;
      [12]\ *)
        tracked_dirty=1
        ;;
      \?\ *)
        untracked_dirty=1
        ;;
    esac
  done <<< "$status_output"

  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$tracked_dirty" \
    "$untracked_dirty" \
    "$conflicted" \
    "${ahead:-0}" \
    "${behind:-0}"
}

function _wt_status_badges_plain() {
  local tracked_dirty="${1:-0}"
  local untracked_dirty="${2:-0}"
  local conflicted="${3:-0}"
  local ahead="${4:-0}"
  local behind="${5:-0}"
  local -a badges

  badges=()

  if [ "$conflicted" -eq 1 ]; then
    badges+=("!")
  elif [ "$tracked_dirty" -eq 1 ]; then
    badges+=("M")
  fi

  if [ "$untracked_dirty" -eq 1 ]; then
    badges+=("?")
  fi

  if [ "${ahead:-0}" -gt 0 ]; then
    badges+=("↑${ahead}")
  fi

  if [ "${behind:-0}" -gt 0 ]; then
    badges+=("↓${behind}")
  fi

  if [ "${#badges[@]}" -eq 0 ]; then
    badges+=("clean")
  fi

  printf '%s\n' "${(j: :)badges}"
}

function _wt_status_badges_color() {
  _wt_theme_init

  local tracked_dirty="${1:-0}"
  local untracked_dirty="${2:-0}"
  local conflicted="${3:-0}"
  local ahead="${4:-0}"
  local behind="${5:-0}"
  local -a badges

  badges=()

  if [ "$conflicted" -eq 1 ]; then
    badges+=("${WT_C_DANGER}!${WT_C_RESET}")
  elif [ "$tracked_dirty" -eq 1 ]; then
    badges+=("${WT_C_WARN}M${WT_C_RESET}")
  fi

  if [ "$untracked_dirty" -eq 1 ]; then
    badges+=("${WT_C_SUCCESS}?${WT_C_RESET}")
  fi

  if [ "${ahead:-0}" -gt 0 ]; then
    badges+=("${WT_C_SUCCESS}↑${ahead}${WT_C_RESET}")
  fi

  if [ "${behind:-0}" -gt 0 ]; then
    badges+=("${WT_C_WARN}↓${behind}${WT_C_RESET}")
  fi

  if [ "${#badges[@]}" -eq 0 ]; then
    badges+=("${WT_C_DIM}clean${WT_C_RESET}")
  fi

  printf '%s\n' "${(j: :)badges}"
}

function _wt_ranked_worktrees() {
  local -a worktree_paths
  local wt_path=""
  local recent_ts=0
  local order_index=0
  local kind=""
  local kind_order=0
  local short_head=""
  local ref_label=""
  local tracked_dirty=0
  local untracked_dirty=0
  local conflicted=0
  local ahead=0
  local behind=0
  local status_meta_text=""
  local -a status_meta

  worktree_paths=("${(@f)$(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')}")

  if [ "${#worktree_paths[@]}" -eq 0 ]; then
    return 0
  fi

  _wt_load_mru_cache
  if ! _wt_prune_loaded_mru_cache "${worktree_paths[@]}"; then
    _wt_write_loaded_mru_cache
  fi

  for wt_path in "${worktree_paths[@]}"; do
    (( order_index++ ))
    recent_ts="${WT_MRU_CACHE_MAP[$wt_path]:-0}"
    short_head="$(git -C "$wt_path" rev-parse --short HEAD 2>/dev/null || echo '?')"
    ref_label="$(git -C "$wt_path" symbolic-ref --quiet --short HEAD 2>/dev/null)"
    status_meta_text="$(_wt_status_meta_for_path "$wt_path")"
    status_meta=("${(@ps:\t:)status_meta_text}")
    tracked_dirty="${status_meta[1]:-0}"
    untracked_dirty="${status_meta[2]:-0}"
    conflicted="${status_meta[3]:-0}"
    ahead="${status_meta[4]:-0}"
    behind="${status_meta[5]:-0}"

    if [ -n "$ref_label" ]; then
      kind="branch"
      kind_order=0
    else
      kind="detached"
      kind_order=1
      ref_label="(detached HEAD)"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$kind_order" \
      "$recent_ts" \
      "$order_index" \
      "$kind" \
      "$wt_path" \
      "$short_head" \
      "$ref_label" \
      "$tracked_dirty" \
      "$untracked_dirty" \
      "$conflicted" \
      "$ahead" \
      "$behind"
  done | sort -t $'\t' -k1,1n -k2,2nr -k3,3n | cut -f4-
}
