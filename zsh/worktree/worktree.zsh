# Git worktree helpers and commands

typeset -g WT_MRU_FILE_NAME='wt-mru.tsv'
typeset -gi WT_MRU_REFRESH_INTERVAL=30
typeset -gi WT_MRU_LAST_REFRESH_TS=0
typeset -g WT_MRU_LAST_PROBED_PWD=''
typeset -g WT_MRU_LAST_PROBED_ROOT=''
typeset -g WT_MRU_HOOKS_INSTALLED=0
typeset -ga WT_MRU_CACHE_PATHS
typeset -gA WT_MRU_CACHE_MAP

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

function _wt_ranked_worktrees() {
  local -a worktree_paths
  local wt_path=""
  local recent_ts=0
  local order_index=0
  local kind=""
  local kind_order=0
  local short_head=""
  local ref_label=""
  local display=""

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

    if [ -n "$ref_label" ]; then
      kind="branch"
      kind_order=0
      display="$wt_path  $short_head [$ref_label]"
    else
      kind="detached"
      kind_order=1
      ref_label="(detached HEAD)"
      display="$wt_path  $short_head $ref_label"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$kind_order" "$recent_ts" "$order_index" "$kind" "$wt_path" "$short_head" "$ref_label" "$display"
  done | sort -t $'\t' -k1,1n -k2,2nr -k3,3n | cut -f4-
}

function _wt_picker_items() {
  _wt_theme_init

  local mode="${1:-main}"
  local kind=""
  local wt_path=""
  local short_head=""
  local ref_label=""
  local display=""
  local branch_rows=()
  local detached_rows=()
  local detached_count=0
  local name=""
  local display_path=""
  local name_width=26
  local ref_width=22
  local path_width=36
  local content_width=88
  local display_text=""

  if [ -n "${COLUMNS:-}" ] && [ "${COLUMNS:-0}" -gt 12 ]; then
    content_width=$(( COLUMNS - 16 ))
  fi

  if [ "$content_width" -lt 74 ]; then
    name_width=20
    ref_width=18
    path_width=24
  fi

  if [ "$content_width" -lt 58 ]; then
    name_width=16
    ref_width=14
    path_width=16
  fi

  while IFS=$'\t' read -r kind wt_path short_head ref_label display; do
    [ -z "$kind" ] && continue

    name="$(_wt_shorten_path "$(basename "$wt_path")" "$name_width")"
    display_path="$(_wt_shorten_path "${wt_path/#$HOME/~}" "$path_width")"
    display_text="${WT_C_ACCENT}$(printf '%-*s' "$name_width" "$name")${WT_C_RESET} ${WT_C_TITLE}$(printf '%-*s' "$ref_width" "$ref_label")${WT_C_RESET} ${short_head} ${WT_C_DIM}${display_path}${WT_C_RESET}"

    if [ "$kind" = "branch" ]; then
      branch_rows+=("${wt_path}"$'\t'"branch-item"$'\t'"${display_text}")
    else
      detached_rows+=("${wt_path}"$'\t'"detached-item"$'\t'"${display_text}")
      (( detached_count++ ))
    fi
  done < <(_wt_ranked_worktrees)

  if [ "$mode" = "detached" ]; then
    printf '%s\n' "${detached_rows[@]}"
    return
  fi

  printf '__CREATE__\tcreate\t%b+ Create new worktree%b\n' "$WT_C_ACCENT" "$WT_C_RESET"

  if [ "${#branch_rows[@]}" -gt 0 ]; then
    printf '%s\n' "${branch_rows[@]}"
  fi

  if [ "$detached_count" -gt 0 ]; then
    printf '__SEP__\tmeta\t \n'
    printf '__DETACHED__\tdetached-summary\t%bDetached HEADs%b (%s)  %b[Ctrl-D to open]%b\n' "$WT_C_TITLE" "$WT_C_RESET" "$detached_count" "$WT_C_DIM" "$WT_C_RESET"
  fi
}

function _wt_display_lines() {
  _wt_theme_init

  local kind=""
  local wt_path=""
  local short_head=""
  local ref_label=""
  local display=""
  local -a branch_rows
  local -a detached_rows
  local name=""
  local ref_display=""
  local header_line=""
  local row_line=""
  local content_width=74
  local name_width=24
  local ref_width=20
  local head_width=7
  local base_width=0
  local path_width=0
  local include_path=1
  local name_cell=""
  local ref_cell=""
  local head_cell=""
  local path_cell=""
  local name_text=""
  local ref_text=""

  if [ -n "${COLUMNS:-}" ] && [ "${COLUMNS:-0}" -gt 12 ]; then
    content_width=$(( COLUMNS - 6 ))
  fi

  if [ "$content_width" -lt 92 ]; then
    name_width=20
    ref_width=18
  fi

  if [ "$content_width" -lt 78 ]; then
    name_width=16
    ref_width=14
  fi

  base_width=$(( 2 + name_width + 1 + ref_width + 1 + head_width ))
  path_width=$(( content_width - base_width - 1 ))

  if [ "$path_width" -lt 18 ]; then
    include_path=0
    path_width=0
  fi

  branch_rows=()
  detached_rows=()

  if [ "$include_path" -eq 1 ]; then
    header_line="  $(printf '%-*s %-*s %-*s %s' "$name_width" 'Name' "$ref_width" 'Ref' "$head_width" 'HEAD' 'Path')"
  else
    header_line="  $(printf '%-*s %-*s %s' "$name_width" 'Name' "$ref_width" 'Ref' 'HEAD')"
  fi
  header_line="${WT_C_DIM}${header_line}${WT_C_RESET}"

  while IFS=$'\t' read -r kind wt_path short_head ref_label display; do
    [ -z "$kind" ] && continue

    name="$(basename "$wt_path")"
    if [ "$kind" = "branch" ]; then
      ref_display="[$ref_label]"
    else
      ref_display="$ref_label"
    fi

    name_text="$(_wt_shorten_path "$name" "$name_width")"
    ref_text="$(_wt_shorten_path "$ref_display" "$ref_width")"
    name_cell="$(printf '%-*s' "$name_width" "$name_text")"
    ref_cell="$(printf '%-*s' "$ref_width" "$ref_text")"
    head_cell="$(printf '%-*s' "$head_width" "$short_head")"

    if [ "$include_path" -eq 1 ]; then
      path_cell="$(_wt_shorten_path "${wt_path/#$HOME/~}" "$path_width")"
      row_line="  ${WT_C_ACCENT}${name_cell}${WT_C_RESET} ${WT_C_TITLE}${ref_cell}${WT_C_RESET} ${head_cell} ${WT_C_DIM}${path_cell}${WT_C_RESET}"
    else
      row_line="  ${WT_C_ACCENT}${name_cell}${WT_C_RESET} ${WT_C_TITLE}${ref_cell}${WT_C_RESET} ${head_cell}"
    fi

    if [ "$kind" = "branch" ]; then
      branch_rows+=("$row_line")
    else
      detached_rows+=("$row_line")
    fi
  done < <(_wt_ranked_worktrees)

  if [ "${#branch_rows[@]}" -gt 0 ]; then
    _wt_print_box 'Named Worktrees' "$header_line" "${branch_rows[@]}"
  else
    _wt_print_box 'Named Worktrees' "  ${WT_C_DIM}(none)${WT_C_RESET}"
  fi

  if [ "${#detached_rows[@]}" -gt 0 ]; then
    printf '\n'
    _wt_print_box 'Detached HEADs' "$header_line" "${detached_rows[@]}"
  fi
}

function _wt_theme_init() {
  typeset -g WT_C_TITLE=$'\033[1;38;2;215;119;87m'
  typeset -g WT_C_ACCENT=$'\033[38;2;122;162;247m'
  typeset -g WT_C_BORDER=$'\033[38;2;136;136;136m'
  typeset -g WT_C_DIM=$'\033[2m'
  typeset -g WT_C_RESET=$'\033[0m'
  typeset -g WT_BOX_TL='╭'
  typeset -g WT_BOX_TR='╮'
  typeset -g WT_BOX_BL='╰'
  typeset -g WT_BOX_BR='╯'
  typeset -g WT_BOX_H='─'
  typeset -g WT_BOX_V='│'
}

function _wt_repeat_char() {
  local char="$1"
  local count="$2"

  if [ -z "$count" ] || [ "$count" -le 0 ]; then
    return 0
  fi

  printf "%${count}s" '' | tr ' ' "$char"
}

function _wt_shorten_path() {
  local input_path="$1"
  local max_width="${2:-72}"
  local prefix_len=0
  local suffix_len=0

  input_path="${input_path/#$HOME/~}"
  if [ "${#input_path}" -le "$max_width" ]; then
    printf '%s\n' "$input_path"
    return
  fi

  if [ "$max_width" -le 9 ]; then
    printf '%s\n' "${input_path[1,$max_width]}"
    return
  fi

  prefix_len=$(( (max_width - 1) / 2 ))
  suffix_len=$(( max_width - prefix_len - 1 ))
  printf '%s…%s\n' "${input_path[1,$prefix_len]}" "${input_path[-$suffix_len,-1]}"
}

function _wt_strip_ansi() {
  emulate -L zsh
  setopt extendedglob

  local text="$1"
  text="${text//$'\033'\[[0-9;]##m/}"
  printf '%s\n' "$text"
}

function _wt_visible_width() {
  local stripped="$(_wt_strip_ansi "$1")"
  printf '%s\n' "${#stripped}"
}

function _wt_fit_box_line() {
  local line="$1"
  local max_width="$2"
  local visible_width="$(_wt_visible_width "$line")"

  if [ "$visible_width" -le "$max_width" ]; then
    printf '%s\n' "$line"
    return
  fi

  printf '%s\n' "$(_wt_shorten_path "$(_wt_strip_ansi "$line")" "$max_width")"
}

function _wt_print_box() {
  _wt_theme_init

  local title="$1"
  shift

  local -a lines
  local line=""
  local fitted_line=""
  local content_width=0
  local term_width="${COLUMNS:-80}"
  local max_content_width=76
  local line_width=0
  local pad_width=0
  local border_fill=0

  lines=("$@")
  content_width=${#title}

  for line in "${lines[@]}"; do
    line_width="$(_wt_visible_width "$line")"
    if [ "$line_width" -gt "$content_width" ]; then
      content_width="$line_width"
    fi
  done

  if [ "$term_width" -gt 10 ]; then
    max_content_width=$(( term_width - 6 ))
  fi

  if [ "$content_width" -gt "$max_content_width" ]; then
    content_width="$max_content_width"
  fi

  border_fill=$(( content_width - ${#title} - 1 ))
  if [ "$border_fill" -lt 0 ]; then
    border_fill=0
  fi

  printf '%b  %s%s %b%s%b %s%s%b\n' \
    "$WT_C_BORDER" \
    "$WT_BOX_TL" \
    "$WT_BOX_H" \
    "$WT_C_TITLE" \
    "$title" \
    "$WT_C_BORDER" \
    "$(_wt_repeat_char "$WT_BOX_H" "$border_fill")" \
    "$WT_BOX_TR" \
    "$WT_C_RESET"

  for line in "${lines[@]}"; do
    fitted_line="$(_wt_fit_box_line "$line" "$content_width")"
    line_width="$(_wt_visible_width "$fitted_line")"
    pad_width=$(( content_width - line_width ))
    if [ "$pad_width" -lt 0 ]; then
      pad_width=0
    fi
    printf '%b  %s %b%s%s%b %s%b\n' \
      "$WT_C_BORDER" \
      "$WT_BOX_V" \
      "$WT_C_RESET" \
      "$fitted_line" \
      "$(_wt_repeat_char ' ' "$pad_width")" \
      "$WT_C_BORDER" \
      "$WT_BOX_V" \
      "$WT_C_RESET"
  done

  printf '%b  %s%s%s%b\n' \
    "$WT_C_BORDER" \
    "$WT_BOX_BL" \
    "$(_wt_repeat_char "$WT_BOX_H" $(( content_width + 2 )))" \
    "$WT_BOX_BR" \
    "$WT_C_RESET"
}

function _wt_help_section_line() {
  _wt_theme_init
  printf '%b%s%b\n' "$WT_C_TITLE" "$1" "$WT_C_RESET"
}

function _wt_help_command_line() {
  _wt_theme_init

  local command_text="$1"
  local description="$2"
  local command_width="${3:-34}"
  local pad_width=$(( command_width - ${#command_text} ))

  if [ "$pad_width" -lt 2 ]; then
    pad_width=2
  fi

  printf '  %b%s%b%s%b%s%b\n' \
    "$WT_C_ACCENT" \
    "$command_text" \
    "$WT_C_RESET" \
    "$(_wt_repeat_char ' ' "$pad_width")" \
    "$WT_C_DIM" \
    "$description" \
    "$WT_C_RESET"
}

function _wt_help_example_line() {
  _wt_theme_init
  printf '  %b%s%b\n' "$WT_C_ACCENT" "$1" "$WT_C_RESET"
}

function _wt_help() {
  _wt_theme_init
  local -a lines

  lines=(
    "$(_wt_help_section_line 'Commands')"
    "$(_wt_help_command_line 'wt' 'Interactive worktree switcher / creator')"
    "$(_wt_help_command_line 'wt help' 'Show this help')"
    "$(_wt_help_command_line 'wt settings' 'Open interactive repo worktree settings')"
    "$(_wt_help_command_line 'wt settings show' 'Show static worktree settings view')"
    "$(_wt_help_command_line 'wt settings env <on|off>' 'Toggle .env / .env.local sync')"
    "$(_wt_help_command_line 'wt settings copy <...>' 'Manage extra copied paths')"
    "$(_wt_help_command_line 'wtls' 'List all worktrees')"
    "$(_wt_help_command_line 'wt0' 'Jump to the base worktree')"
    "$(_wt_help_command_line 'wtd' 'Delete the current managed worktree')"
    "$(_wt_help_command_line 'wtd!' 'Force-delete the current managed worktree')"
    ''
    "$(_wt_help_section_line 'Picker')"
    '  Named worktrees show first.'
    '  Detached HEAD worktrees sit behind a section row.'
    "  ${WT_C_ACCENT}Ctrl-D${WT_C_RESET} toggles between the main and detached-only views from anywhere."
    ''
    "$(_wt_help_section_line 'Examples')"
    "$(_wt_help_example_line 'wt')"
    "$(_wt_help_example_line 'wtls')"
    "$(_wt_help_example_line 'wt0')"
    "$(_wt_help_example_line 'wtd')"
    "$(_wt_help_example_line 'wt settings')"
    "$(_wt_help_example_line 'wt settings env off')"
    "$(_wt_help_example_line 'wt settings copy add notes screenshots')"
    "$(_wt_help_example_line 'wt settings copy remove notes')"
  )

  _wt_print_box 'wt' "${lines[@]}"
}

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

function wtd() {
  local wt_root="$(git rev-parse --show-toplevel 2>/dev/null)"
  local main_worktree="$(_wt_main_worktree)"
  local managed_dir="$(_wt_managed_dir)"
  local branch_name="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"

  if [ -z "$wt_root" ] || [ -z "$main_worktree" ]; then
    echo "Not in a git repository"
    return 1
  fi

  if [ "$wt_root" = "$main_worktree" ] || ! _wt_is_managed_worktree "$wt_root"; then
    echo "Not in a managed worktree"
    return 1
  fi

  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    echo "Worktree has uncommitted or untracked changes. Use 'wtd!' to force delete."
    return 1
  fi

  cd "$main_worktree" || return 1
  git worktree remove "$wt_root" 2>/dev/null || {
    git worktree prune
    rm -rf "$wt_root"
  }
  git branch -D "$branch_name" 2>/dev/null
  _wt_remove_path_recent "$wt_root" >/dev/null 2>&1

  local cleanup_message=""
  if [ -n "$managed_dir" ] && [ -d "$managed_dir" ] && rmdir "$managed_dir" 2>/dev/null; then
    cleanup_message=" Removed empty $(basename "$managed_dir")."
  fi

  echo "Removed worktree + branch '$branch_name', returned to $main_worktree.$cleanup_message"
}

function wtd!() {
  local wt_root="$(git rev-parse --show-toplevel 2>/dev/null)"
  local main_worktree="$(_wt_main_worktree)"
  local managed_dir="$(_wt_managed_dir)"
  local branch_name="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"

  if [ -z "$wt_root" ] || [ -z "$main_worktree" ]; then
    echo "Not in a git repository"
    return 1
  fi

  if [ "$wt_root" = "$main_worktree" ] || ! _wt_is_managed_worktree "$wt_root"; then
    echo "Not in a managed worktree"
    return 1
  fi

  cd "$main_worktree" || return 1
  git worktree remove --force "$wt_root" 2>/dev/null || {
    git worktree prune
    rm -rf "$wt_root"
  }
  git branch -D "$branch_name" 2>/dev/null
  _wt_remove_path_recent "$wt_root" >/dev/null 2>&1

  local cleanup_message=""
  if [ -n "$managed_dir" ] && [ -d "$managed_dir" ] && rmdir "$managed_dir" 2>/dev/null; then
    cleanup_message=" Removed empty $(basename "$managed_dir")."
  fi

  echo "Removed worktree + branch '$branch_name', returned to $main_worktree.$cleanup_message"
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

function _wt_settings_status() {
  _wt_theme_init

  case "$1" in
    true|on|enabled)
      printf '%bON%b\n' "$WT_C_ACCENT" "$WT_C_RESET"
      ;;
    *)
      printf '%bOFF%b\n' "$WT_C_DIM" "$WT_C_RESET"
      ;;
  esac
}

function _wt_settings_show() {
  _wt_theme_init

  local env_enabled="$(_wt_copy_env_enabled)"
  local customized="$(_wt_copy_paths_customized)"
  local copy_path=""
  local has_paths=0
  local -a lines

  lines=(
    "$(_wt_help_section_line 'Repo Settings')"
    "  ${WT_C_ACCENT}env files${WT_C_RESET}          $(_wt_settings_status "$env_enabled")"
    "  ${WT_C_ACCENT}custom copy paths${WT_C_RESET}  $(_wt_settings_status "$customized")"
    ''
    "$(_wt_help_section_line 'Copied Paths')"
  )

  while IFS= read -r copy_path; do
    [ -z "$copy_path" ] && continue
    lines+=("  ${WT_C_ACCENT}•${WT_C_RESET} ${copy_path}")
    has_paths=1
  done < <(_wt_get_copy_paths)

  if [ "$has_paths" -eq 0 ]; then
    lines+=("  ${WT_C_DIM}(none)${WT_C_RESET}")
  fi

  lines+=('')
  lines+=("${WT_C_DIM}Run ${WT_C_ACCENT}wt settings${WT_C_DIM} interactively, or use ${WT_C_ACCENT}wt settings show${WT_C_DIM} for this static view.${WT_C_RESET}")

  _wt_print_box 'wt settings' "${lines[@]}"
}

function _wt_settings_picker_items() {
  _wt_theme_init

  local env_enabled="$(_wt_copy_env_enabled)"
  local copy_path=""
  local display_path=""

  printf 'toggle-env\taction\t%b%s%b  %b.env + .env.local%b\n' \
    "$WT_C_ACCENT" \
    "$([ "$env_enabled" = "true" ] && printf '●' || printf '○')" \
    "$WT_C_RESET" \
    "$WT_C_TITLE" \
    "$WT_C_RESET"

  while IFS= read -r copy_path; do
    [ -z "$copy_path" ] && continue
    display_path="$(_wt_shorten_path "$copy_path" 40)"
    printf 'copy:%s\tcopy-path\t%b●%b  %s\n' \
      "$copy_path" \
      "$WT_C_ACCENT" \
      "$WT_C_RESET" \
      "$display_path"
  done < <(_wt_get_copy_paths)

  printf 'add-copy\taction\t%b+%b  Add copied path\n' "$WT_C_ACCENT" "$WT_C_RESET"
  printf 'clear-copy\taction\t%b×%b  Clear copied paths\n' "$WT_C_DIM" "$WT_C_RESET"
  printf 'reset-copy\taction\t%b↺%b  Reset copied paths to defaults\n' "$WT_C_TITLE" "$WT_C_RESET"
}

function _wt_settings_add_copy_path() {
  _wt_theme_init

  local new_path=""
  local normalized=""
  local copy_path_item=""
  local -a current_paths
  local -A seen_paths

  if [ ! -r /dev/tty ]; then
    return 0
  fi

  printf '\n%bPath to copy:%b ' "$WT_C_ACCENT" "$WT_C_RESET" > /dev/tty
  IFS= read -r new_path < /dev/tty || return 0
  printf '\n' > /dev/tty

  if [ -z "$new_path" ]; then
    return 0
  fi

  normalized="$(_wt_normalize_copy_path "$new_path")" || return 0
  current_paths=("${(@f)$(_wt_get_copy_paths)}")

  for copy_path_item in "${current_paths[@]}"; do
    seen_paths[$copy_path_item]=1
  done

  if [ -z "${seen_paths[$normalized]}" ]; then
    current_paths+=("$normalized")
    _wt_set_copy_paths "${current_paths[@]}" || return 1
  fi
}

function _wt_settings_remove_copy_path() {
  local path_to_remove="$1"
  local copy_path_item=""
  local normalized=""
  local -a current_paths updated_paths
  local -A remove_lookup

  current_paths=("${(@f)$(_wt_get_copy_paths)}")
  updated_paths=()
  remove_lookup[$path_to_remove]=1

  for copy_path_item in "${current_paths[@]}"; do
    normalized="$(_wt_normalize_copy_path "$copy_path_item")" || continue
    if [ -z "${remove_lookup[$normalized]}" ]; then
      updated_paths+=("$normalized")
    fi
  done

  _wt_set_copy_paths "${updated_paths[@]}" || return 1
}

function _wt_settings_apply_item() {
  local item_id="$1"

  case "$item_id" in
    toggle-env)
      if [ "$(_wt_copy_env_enabled)" = "true" ]; then
        git config --local ben.worktree.copyEnvFiles false || return 1
      else
        git config --local ben.worktree.copyEnvFiles true || return 1
      fi
      ;;
    add-copy)
      _wt_settings_add_copy_path || return 1
      ;;
    clear-copy)
      _wt_set_copy_paths || return 1
      ;;
    reset-copy)
      _wt_reset_copy_paths || return 1
      ;;
    copy:*)
      _wt_settings_remove_copy_path "${item_id#copy:}" || return 1
      ;;
  esac
}

function _wt_settings_panel_margin() {
  local term_columns="${COLUMNS:-$(tput cols 2>/dev/null || echo 100)}"
  local target_width=74
  local margin=0

  if [ "$term_columns" -gt $(( target_width + 4 )) ]; then
    margin=$(( (term_columns - target_width) / 2 ))
  fi

  if [ "$margin" -lt 0 ]; then
    margin=0
  fi

  echo "$margin"
}

function _wt_settings_interactive() {
  _wt_theme_init

  if ! command -v fzf &>/dev/null; then
    _wt_settings_show
    return 0
  fi

  local repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
  local loader="${functions_source[_wt_settings_interactive]}"
  local panel_margin="$(_wt_settings_panel_margin)"
  local reload_cmd=""
  local apply_cmd=""

  if [ -z "$repo_root" ] || [ -z "$loader" ]; then
    _wt_settings_show
    return 0
  fi

  reload_cmd="source ${(q)loader} >/dev/null 2>&1; cd ${(q)repo_root} || exit 1; _wt_settings_picker_items"
  apply_cmd="source ${(q)loader} >/dev/null 2>&1; cd ${(q)repo_root} || exit 1; _wt_settings_apply_item {1}"

  printf '%s' "$(_wt_settings_picker_items)" | fzf \
    --ansi \
    --height='~14' \
    --min-height=12 \
    --layout=reverse \
    --padding=1,1 \
    --margin="1,${panel_margin},1,${panel_margin}" \
    --border=rounded \
    --border-label=' wt settings ' \
    --border-label-pos=2 \
    --header='Enter: toggle/apply  Esc: close' \
    --header-border=rounded \
    --header-label=' keys ' \
    --header-label-pos=2 \
    --info=hidden \
    --no-input \
    --cycle \
    --track \
    --highlight-line \
    --with-shell='zsh -fc' \
    --bind="enter:execute-silent(${apply_cmd})+reload(${reload_cmd})" \
    --color='border:#888888,label:#d77757,header:#b9c0c8,prompt:#d77757,pointer:#4eba65,info:#b1b9f9,spinner:#d77757,marker:#4eba65,fg:#d9dde3,gutter:-1' \
    --delimiter=$'\t' \
    --with-nth=3.. \
    --id-nth=1 >/dev/null
}

function _wt_settings() {
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Not in a git repository"
    return 1
  fi

  local subcommand="${1:-}"
  if [ "$#" -gt 0 ]; then
    shift
  fi

  if [ -z "$subcommand" ]; then
    if [ -t 0 ] && [ -t 1 ] && command -v fzf &>/dev/null; then
      _wt_settings_interactive
    else
      _wt_settings_show
    fi
    return $?
  fi

  case "$subcommand" in
    show)
      _wt_settings_show
      ;;
    env)
      case "$1" in
        on)
          git config --local ben.worktree.copyEnvFiles true || return 1
          echo "Enabled .env and .env.local syncing for this repo."
          ;;
        off)
          git config --local ben.worktree.copyEnvFiles false || return 1
          echo "Disabled .env and .env.local syncing for this repo."
          ;;
        *)
          echo "Usage: wt settings env <on|off>"
          return 1
          ;;
      esac
      ;;
    copy)
      local action="${1:-list}"
      if [ "$#" -gt 0 ]; then
        shift
      fi

      case "$action" in
        list)
          _wt_settings show
          ;;
        add)
          if [ "$#" -eq 0 ]; then
            echo "Usage: wt settings copy add <path> [path...]"
            return 1
          fi

          local -a updated_paths
          local -A seen_paths
          local copy_path_item=""
          local normalized=""

          updated_paths=()
          while IFS= read -r copy_path_item; do
            [ -z "$copy_path_item" ] && continue
            normalized="$(_wt_normalize_copy_path "$copy_path_item")" || continue
            if [ -z "${seen_paths[$normalized]}" ]; then
              updated_paths+=("$normalized")
              seen_paths[$normalized]=1
            fi
          done < <(_wt_get_copy_paths)

          for copy_path_item in "$@"; do
            normalized="$(_wt_normalize_copy_path "$copy_path_item")" || continue
            if [ -z "${seen_paths[$normalized]}" ]; then
              updated_paths+=("$normalized")
              seen_paths[$normalized]=1
            fi
          done

          _wt_set_copy_paths "${updated_paths[@]}" || return 1
          echo "Copy paths updated."
          ;;
        remove|rm|delete)
          if [ "$#" -eq 0 ]; then
            echo "Usage: wt settings copy remove <path> [path...]"
            return 1
          fi

          local -a current_paths updated_paths paths_to_remove
          local -A remove_lookup
          local copy_path_item=""
          local normalized=""

          current_paths=("${(@f)$(_wt_get_copy_paths)}")
          updated_paths=()
          paths_to_remove=()

          for copy_path_item in "$@"; do
            normalized="$(_wt_normalize_copy_path "$copy_path_item")" || continue
            paths_to_remove+=("$normalized")
            remove_lookup[$normalized]=1
          done

          for copy_path_item in "${current_paths[@]}"; do
            normalized="$(_wt_normalize_copy_path "$copy_path_item")" || continue
            if [ -z "${remove_lookup[$normalized]}" ]; then
              updated_paths+=("$normalized")
            fi
          done

          _wt_set_copy_paths "${updated_paths[@]}" || return 1
          echo "Copy paths updated."
          ;;
        set)
          _wt_set_copy_paths "$@" || return 1
          echo "Copy paths set."
          ;;
        clear)
          _wt_set_copy_paths || return 1
          echo "Cleared all copied paths for this repo."
          ;;
        reset)
          _wt_reset_copy_paths
          echo "Reset copy paths to defaults."
          ;;
        *)
          echo "Usage: wt settings copy <list|add|remove|set|clear|reset> [paths...]"
          return 1
          ;;
      esac
      ;;
    *)
      echo "Usage: wt settings <show|env|copy>"
      return 1
      ;;
  esac
}

function wt() {
  case "$1" in
    help|-h|--help)
      _wt_help
      return 0
      ;;
    settings)
      shift
      _wt_settings "$@"
      return $?
      ;;
    "")
      ;;
    *)
      echo "Unknown wt subcommand: $1"
      echo
      _wt_help
      return 1
      ;;
  esac

  if ! command -v fzf &>/dev/null; then
    echo "fzf is required for interactive selection"
    return 1
  fi

  local worktrees="$(_wt_ranked_worktrees)"
  if [ -z "$worktrees" ]; then
    echo "Not in a git repository"
    return 1
  fi

  local picker_mode="main"
  local header_text="Ctrl-D: open detached HEADs"
  local list_label=' named worktrees '
  local result=""
  local -a result_lines
  local key=""
  local selected=""
  local wt_path=""
  local row_kind=""
  local detached_count=0

  while IFS=$'\t' read -r row_kind _; do
    if [ "$row_kind" = "detached" ]; then
      (( detached_count++ ))
    fi
  done <<< "$worktrees"

  while true; do
    if [ "$picker_mode" = "detached" ]; then
      header_text='Ctrl-D: back to named worktrees'
      list_label=' detached heads '
    else
      header_text='Ctrl-D: open detached HEADs'
      list_label=' named worktrees '
    fi

    result="$(printf '%s' "$(_wt_picker_items "$picker_mode")" | fzf --ansi --expect=ctrl-d --bind 'enter:accept,ctrl-d:accept' --height=70% --min-height=14 --layout=reverse --padding=1,1 --border=rounded --border-label=' wt ' --border-label-pos=2 --header="$header_text" --header-border=rounded --header-label=' keys ' --header-label-pos=2 --list-label="$list_label" --list-label-pos=2 --info=inline-right --color='border:#888888,label:#d77757,header:#b9c0c8,prompt:#d77757,pointer:#4eba65,info:#b1b9f9,spinner:#d77757,marker:#4eba65,fg:#d9dde3,gutter:-1' --prompt='worktree > ' --delimiter=$'\t' --with-nth=3.. --id-nth=1)"
    if [ -z "$result" ]; then
      return 0
    fi

    result_lines=("${(@f)result}")
    if [ "${result_lines[1]}" = "ctrl-d" ]; then
      key="ctrl-d"
      selected="${result_lines[2]}"
    elif [ -z "${result_lines[1]}" ] && [ "${#result_lines[@]}" -ge 2 ]; then
      key=""
      selected="${result_lines[2]}"
    else
      key=""
      selected="${result_lines[1]}"
    fi

    if [ "$key" = "ctrl-d" ]; then
      if [ "$picker_mode" = "main" ]; then
        if [ "$detached_count" -gt 0 ]; then
          picker_mode="detached"
        fi
      elif [ "$picker_mode" = "detached" ]; then
        picker_mode="main"
      fi
      continue
    fi

    if [ -z "$selected" ]; then
      continue
    fi

    wt_path="${selected%%$'\t'*}"
    row_kind="${selected#*$'\t'}"
    row_kind="${row_kind%%$'\t'*}"

    if [ "$wt_path" = "__CREATE__" ]; then
      _gwt_create
      return
    fi

    if [ "$row_kind" = "detached-summary" ] || [ "$wt_path" = "__SEP__" ]; then
      continue
    fi

    cd "$wt_path" || return 1
    echo "Switched to: $wt_path"
    return
  done
}

function wtls() {
  _wt_display_lines
}

_wt_install_hooks
