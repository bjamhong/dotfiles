# Public wt commands and interactive picker loop.

function _wt_parse_picker_result() {
  local result="$1"
  local -a result_lines
  local key=""
  local selected=""

  result_lines=("${(@f)result}")

  case "${result_lines[1]}" in
    ctrl-d|ctrl-o|ctrl-s|ctrl-x)
      key="${result_lines[1]}"
      selected="${result_lines[2]}"
      ;;
    "")
      if [ "${#result_lines[@]}" -ge 2 ]; then
        selected="${result_lines[2]}"
      fi
      ;;
    *)
      selected="${result_lines[1]}"
      ;;
  esac

  printf '%s\n%s\n' "$key" "$selected"
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

  local picker_mode="main"
  local header_text=""
  local list_label=' named worktrees '
  local worktrees=""
  local result=""
  local parsed_result=""
  local -a parsed_lines
  local key=""
  local selected=""
  local wt_path=""
  local row_kind=""
  local detached_count=0

  while true; do
    worktrees="$(_wt_ranked_worktrees)"
    if [ -z "$worktrees" ]; then
      echo "Not in a git repository"
      return 1
    fi

    detached_count=0
    while IFS=$'\t' read -r row_kind _; do
      if [ "$row_kind" = "detached" ]; then
        (( detached_count++ ))
      fi
    done <<< "$worktrees"

    if [ "$picker_mode" = "detached" ]; then
      header_text='Enter: switch  Ctrl-D: back  Ctrl-X: delete  Ctrl-O: open tab  Ctrl-S: settings'
      list_label=' detached heads '
    else
      header_text='Enter: switch  Ctrl-D: detached  Ctrl-X: delete  Ctrl-O: open tab  Ctrl-S: settings'
      list_label=' named worktrees '
    fi

    result="$(printf '%s' "$(_wt_picker_items "$picker_mode" "$worktrees")" | fzf --ansi --expect=ctrl-d,ctrl-o,ctrl-s,ctrl-x --bind 'enter:accept,ctrl-d:accept,ctrl-o:accept,ctrl-s:accept,ctrl-x:accept' --height=70% --min-height=14 --layout=reverse --padding=1,1 --border=rounded --border-label=' wt ' --border-label-pos=2 --header="$header_text" --header-border=rounded --header-label=' keys ' --header-label-pos=2 --list-label="$list_label" --list-label-pos=2 --info=inline-right --color='border:#888888,label:#d77757,header:#b9c0c8,prompt:#d77757,pointer:#4eba65,info:#b1b9f9,spinner:#d77757,marker:#4eba65,fg:#d9dde3,gutter:-1' --prompt='worktree > ' --delimiter=$'\t' --with-nth=3.. --id-nth=1)"
    if [ -z "$result" ]; then
      return 0
    fi

    parsed_result="$(_wt_parse_picker_result "$result")"
    parsed_lines=("${(@f)parsed_result}")
    key="${parsed_lines[1]}"
    selected="${parsed_lines[2]}"

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

    if [ "$key" = "ctrl-s" ]; then
      _wt_settings_interactive
      continue
    fi

    if [ "$key" = "ctrl-o" ]; then
      if [ "$row_kind" = "branch-item" ] || [ "$row_kind" = "detached-item" ]; then
        _wt_open_path_in_ghostty_tab "$wt_path"
      fi
      continue
    fi

    if [ "$key" = "ctrl-x" ]; then
      if [ "$row_kind" = "branch-item" ] || [ "$row_kind" = "detached-item" ]; then
        if _wt_is_managed_worktree "$wt_path" && _wt_confirm "Delete $(basename "$wt_path")?"; then
          _wt_delete_worktree_path "$wt_path" false
        fi
      fi
      continue
    fi

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
