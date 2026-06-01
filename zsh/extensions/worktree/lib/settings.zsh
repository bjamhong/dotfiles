# Worktree settings UI and commands.

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
  local loader="$WT_EXTENSION_ENTRYPOINT"
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
