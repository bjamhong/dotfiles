# Worktree terminal UI helpers, picker rows, and help output.

function _wt_picker_items() {
  _wt_theme_init

  local mode="${1:-main}"
  local ranked_worktrees="${2:-$(_wt_ranked_worktrees)}"
  local kind=""
  local wt_path=""
  local short_head=""
  local ref_label=""
  local tracked_dirty=0
  local untracked_dirty=0
  local conflicted=0
  local ahead=0
  local behind=0
  local branch_rows=()
  local detached_rows=()
  local detached_count=0
  local name=""
  local badges=""
  local display_path=""
  local name_width=26
  local ref_width=22
  local state_width=13
  local path_width=0
  local content_width=88
  local base_width=0
  local display_text=""

  if [ -n "${COLUMNS:-}" ] && [ "${COLUMNS:-0}" -gt 12 ]; then
    content_width=$(( COLUMNS - 16 ))
  fi

  if [ "$content_width" -lt 88 ]; then
    name_width=20
    ref_width=18
    state_width=11
    path_width=24
  fi

  if [ "$content_width" -lt 68 ]; then
    name_width=16
    ref_width=14
    state_width=9
  fi

  base_width=$(( name_width + ref_width + 7 + state_width + 4 ))
  path_width=$(( content_width - base_width ))
  if [ "$path_width" -lt 16 ]; then
    path_width=16
  fi

  while IFS=$'\t' read -r kind wt_path short_head ref_label tracked_dirty untracked_dirty conflicted ahead behind; do
    [ -z "$kind" ] && continue

    name="$(_wt_shorten_path "$(basename "$wt_path")" "$name_width")"
    display_path="$(_wt_shorten_path "${wt_path/#$HOME/~}" "$path_width")"
    badges="$(_wt_status_badges_color "$tracked_dirty" "$untracked_dirty" "$conflicted" "$ahead" "$behind")"
    display_text="${WT_C_ACCENT}$(printf '%-*s' "$name_width" "$name")${WT_C_RESET} ${WT_C_TITLE}$(printf '%-*s' "$ref_width" "$ref_label")${WT_C_RESET} $(printf '%-7s' "$short_head") $(_wt_pad_visible_text "$badges" "$state_width") ${WT_C_DIM}${display_path}${WT_C_RESET}"

    if [ "$kind" = "branch" ]; then
      branch_rows+=("${wt_path}"$'\t'"branch-item"$'\t'"${display_text}")
    else
      detached_rows+=("${wt_path}"$'\t'"detached-item"$'\t'"${display_text}")
      (( detached_count++ ))
    fi
  done <<< "$ranked_worktrees"

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

  local ranked_worktrees="${1:-$(_wt_ranked_worktrees)}"
  local kind=""
  local wt_path=""
  local short_head=""
  local ref_label=""
  local tracked_dirty=0
  local untracked_dirty=0
  local conflicted=0
  local ahead=0
  local behind=0
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
  local state_width=12
  local base_width=0
  local path_width=0
  local include_path=1
  local name_cell=""
  local ref_cell=""
  local head_cell=""
  local state_cell=""
  local path_cell=""
  local name_text=""
  local ref_text=""
  local status_text=""

  if [ -n "${COLUMNS:-}" ] && [ "${COLUMNS:-0}" -gt 12 ]; then
    content_width=$(( COLUMNS - 6 ))
  fi

  if [ "$content_width" -lt 100 ]; then
    name_width=20
    ref_width=18
    state_width=10
  fi

  if [ "$content_width" -lt 84 ]; then
    name_width=16
    ref_width=14
    state_width=8
  fi

  base_width=$(( 2 + name_width + 1 + ref_width + 1 + head_width + 1 + state_width ))
  path_width=$(( content_width - base_width - 1 ))

  if [ "$path_width" -lt 18 ]; then
    include_path=0
    path_width=0
  fi

  branch_rows=()
  detached_rows=()

  if [ "$include_path" -eq 1 ]; then
    header_line="  $(printf '%-*s %-*s %-*s %-*s %s' "$name_width" 'Name' "$ref_width" 'Ref' "$head_width" 'HEAD' "$state_width" 'State' 'Path')"
  else
    header_line="  $(printf '%-*s %-*s %-*s %s' "$name_width" 'Name' "$ref_width" 'Ref' "$head_width" 'HEAD' 'State')"
  fi
  header_line="${WT_C_DIM}${header_line}${WT_C_RESET}"

  while IFS=$'\t' read -r kind wt_path short_head ref_label tracked_dirty untracked_dirty conflicted ahead behind; do
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
    status_text="$(_wt_status_badges_color "$tracked_dirty" "$untracked_dirty" "$conflicted" "$ahead" "$behind")"
    state_cell="$(_wt_pad_visible_text "$status_text" "$state_width")"

    if [ "$include_path" -eq 1 ]; then
      path_cell="$(_wt_shorten_path "${wt_path/#$HOME/~}" "$path_width")"
      row_line="  ${WT_C_ACCENT}${name_cell}${WT_C_RESET} ${WT_C_TITLE}${ref_cell}${WT_C_RESET} ${head_cell} ${state_cell} ${WT_C_DIM}${path_cell}${WT_C_RESET}"
    else
      row_line="  ${WT_C_ACCENT}${name_cell}${WT_C_RESET} ${WT_C_TITLE}${ref_cell}${WT_C_RESET} ${head_cell} ${state_cell}"
    fi

    if [ "$kind" = "branch" ]; then
      branch_rows+=("$row_line")
    else
      detached_rows+=("$row_line")
    fi
  done <<< "$ranked_worktrees"

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
  typeset -g WT_C_SUCCESS=$'\033[38;2;78;186;101m'
  typeset -g WT_C_WARN=$'\033[38;2;224;165;76m'
  typeset -g WT_C_DANGER=$'\033[38;2;224;97;97m'
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

function _wt_pad_visible_text() {
  local text="$1"
  local width="$2"
  local visible_width="$(_wt_visible_width "$text")"
  local pad_width=$(( width - visible_width ))

  if [ "$pad_width" -lt 0 ]; then
    pad_width=0
  fi

  printf '%s%s' "$text" "$(_wt_repeat_char ' ' "$pad_width")"
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
    '  Named worktrees show first; detached HEADs sit behind a section row.'
    "  ${WT_C_ACCENT}Enter${WT_C_RESET} switches to the selected worktree."
    "  ${WT_C_ACCENT}Ctrl-D${WT_C_RESET} toggles between the main and detached-only views."
    "  ${WT_C_ACCENT}Ctrl-X${WT_C_RESET} deletes the selected managed worktree."
    "  ${WT_C_ACCENT}Ctrl-O${WT_C_RESET} opens the selected worktree in a new Ghostty tab."
    "  ${WT_C_ACCENT}Ctrl-S${WT_C_RESET} opens ${WT_C_ACCENT}wt settings${WT_C_RESET}."
    '  State badges: M tracked changes, ? untracked files, ! conflicts, arrows ahead/behind.'
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
