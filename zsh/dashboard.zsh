# Tmux Dashboard — interactive session management
# Claude Code-inspired terminal UI with synchronized output
#
# Features:
#   a — add window (+ Ghostty tab)
#   d — delete window
#   r — rename window
#   t — switch to another session
#   q — detach (keep session alive)
#   x — kill session

function _tmux_dashboard() {
  local session="$1"

  # ── Theme (Claude Code dark) ──
  local c_title=$'\033[1;38;2;215;119;87m'
  local c_border=$'\033[38;2;136;136;136m'
  local c_green=$'\033[38;2;78;186;101m'
  local c_red=$'\033[38;2;255;107;128m'
  local c_amber=$'\033[38;2;255;193;7m'
  local c_blue=$'\033[38;2;177;185;249m'
  local c_dim=$'\033[2m'
  local c_bold=$'\033[1m'
  local c_r=$'\033[0m'

  # ── Box drawing (round, left-side only) ──
  local TL="╭" BL="╰" H="─" V="│" BULLET="●"

  # Repeat character N times
  _hr() { printf "%0.s$1" $(seq 1 $2); }

  # ── Synchronized output helpers ──
  # Wrapping draw calls in DEC mode 2026 prevents tearing
  _sync_start() { printf '\033[?2026h'; }
  _sync_end()   { printf '\033[?2026l'; }

  # ── Kill grouped sessions for a given session ──
  _kill_grouped() {
    local target="$1"
    for s in $(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^${target}-g"); do
      tmux kill-session -t "$s" 2>/dev/null
    done
  }

  # ── Cleanup: kill current session entirely ──
  _dashboard_kill() {
    tput cnorm 2>/dev/null
    _kill_grouped "$session"
    tmux kill-session -t "$session" 2>/dev/null
  }

  # ── Close all Ghostty tabs except the first (dashboard) ──
  _close_ghostty_tabs() {
    osascript <<'APPLESCRIPT' 2>/dev/null
tell application "Ghostty"
  set w to front window
  repeat while (count of tabs of w) > 1
    close last tab of w
  end repeat
end tell
APPLESCRIPT
  }

  # ── Open Ghostty tabs for all windows in a session ──
  _open_ghostty_tabs() {
    local target="$1"
    local windows=($(tmux list-windows -t "$target" -F '#{window_index}' 2>/dev/null))
    for i in $(seq 1 ${#windows[@]}); do
      local win_idx="${windows[$i]}"
      local linked="${target}-g${win_idx}"
      tmux new-session -d -t "$target" -s "$linked"
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
  }

  trap "_dashboard_kill; echo ''; echo '  Session killed.'; return 0" INT
  tput civis 2>/dev/null

  local sep_w=50
  local prev_frame=""

  while tmux has-session -t "$session" 2>/dev/null; do
    # ── Build frame in variable (avoid partial draws) ──
    local frame=""
    frame+="\n"

    # Header
    local title="tmux: ${session}"
    local fill=$((sep_w - ${#title} - 3))
    frame+="  ${c_border}${TL}${H} ${c_title}${title}${c_r}${c_border} $(_hr "$H" $fill)${c_r}\n"
    frame+="  ${c_border}${V}${c_r}\n"

    # Window list
    local win_count=0
    while IFS=$'\t' read -r idx name panes cmd; do
      frame+="  ${c_border}${V}${c_r}  ${c_green}${BULLET}${c_r}  ${c_bold}${idx}${c_r}  $(printf '%-14s' "$name")  ${c_dim}${panes} panes${c_r}  ${c_dim}${cmd}${c_r}\n"
      (( win_count++ ))
    done < <(tmux list-windows -t "$session" -F $'#{window_index}\t#{window_name}\t#{window_panes}\t#{pane_current_command}' 2>/dev/null)

    if (( win_count == 0 )); then
      frame+="  ${c_border}${V}${c_r}  ${c_dim}no windows${c_r}\n"
    fi

    # Footer
    frame+="  ${c_border}${V}${c_r}\n"
    frame+="  ${c_border}${BL}$(_hr "$H" $sep_w)${c_r}\n"
    frame+="\n"
    frame+="    ${c_title}a${c_r} add   ${c_title}d${c_r} delete   ${c_title}r${c_r} rename   ${c_title}t${c_r} sessions   ${c_title}q${c_r} detach   ${c_amber}x${c_r} kill\n"
    frame+="\n"

    # ── Only redraw if frame changed ──
    if [[ "$frame" != "$prev_frame" ]]; then
      _sync_start
      clear
      printf "%b" "$frame"
      _sync_end
      prev_frame="$frame"
    fi

    # ── Input (2s timeout for auto-refresh) ──
    read -sk1 -t2 key 2>/dev/null || key=""

    case "$key" in
      a)
        # Add new tmux window + Ghostty tab
        local new_win
        new_win=$(tmux new-window -t "$session" -P -F '#{window_index}' -c "$PWD")
        tmux split-window -h -t "${session}:${new_win}" -c "$PWD"
        local linked="${session}-g${new_win}"
        tmux new-session -d -t "$session" -s "$linked"
        tmux select-window -t "$linked:${new_win}"
        osascript <<APPLESCRIPT
tell application "Ghostty"
  new tab in front window
  set t to focused terminal of selected tab of front window
  input text "TMUX= tmux attach -t ${linked}" to t
  send key "enter" to t
end tell
APPLESCRIPT
        prev_frame=""  # force redraw
        ;;
      d)
        tput cnorm 2>/dev/null
        printf "\r  ${c_red}delete window: ${c_r}"
        read -r widx
        tput civis 2>/dev/null
        if [ -n "$widx" ]; then
          tmux kill-window -t "${session}:${widx}" 2>/dev/null
          tmux kill-session -t "${session}-g${widx}" 2>/dev/null
        fi
        prev_frame=""
        ;;
      r)
        tput cnorm 2>/dev/null
        printf "\r  window index: "
        read -r widx
        printf "  new name: "
        read -r wname
        tput civis 2>/dev/null
        if [ -n "$widx" ] && [ -n "$wname" ]; then
          tmux rename-window -t "${session}:${widx}" "$wname" 2>/dev/null
        fi
        prev_frame=""
        ;;
      t)
        # Switch to another session
        tput cnorm 2>/dev/null

        # List top-level sessions (exclude -g grouped ones)
        local sessions=()
        while IFS= read -r s; do
          sessions+=("$s")
        done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -v -- '-g[0-9]*$')

        if (( ${#sessions[@]} <= 1 )); then
          printf "\n  ${c_dim}No other sessions${c_r}\n"
          sleep 1
          tput civis 2>/dev/null
          prev_frame=""
          continue
        fi

        # Display session list
        printf "\n"
        printf "  ${c_border}${TL}${H} ${c_title}sessions${c_r}${c_border} $(_hr "$H" 39)${c_r}\n"
        printf "  ${c_border}${V}${c_r}\n"
        for sname in "${sessions[@]}"; do
          local wcount=$(tmux list-windows -t "$sname" 2>/dev/null | wc -l | tr -d ' ')
          if [[ "$sname" == "$session" ]]; then
            printf "  ${c_border}${V}${c_r}  ${c_green}${BULLET}${c_r}  ${c_bold}%s${c_r}  ${c_dim}%s windows (current)${c_r}\n" "$sname" "$wcount"
          else
            printf "  ${c_border}${V}${c_r}  ${c_dim}●${c_r}  %s  ${c_dim}%s windows${c_r}\n" "$sname" "$wcount"
          fi
        done
        printf "  ${c_border}${V}${c_r}\n"
        printf "  ${c_border}${BL}$(_hr "$H" $sep_w)${c_r}\n"
        printf "\n  switch to: "
        read -r new_session

        tput civis 2>/dev/null

        # Validate and switch
        if [ -n "$new_session" ] && [[ "$new_session" != "$session" ]] && tmux has-session -t "$new_session" 2>/dev/null; then
          # Tear down current Ghostty tabs
          _kill_grouped "$session"
          sleep 0.2
          _close_ghostty_tabs

          # Open tabs for new session
          sleep 0.3
          _open_ghostty_tabs "$new_session"

          # Switch dashboard context
          session="$new_session"
        fi
        prev_frame=""
        ;;
      q)
        # Detach — leave tmux session alive
        tput cnorm 2>/dev/null
        echo ""
        printf "  ${c_dim}Detached. Reattach with: tmuxa ${session}${c_r}\n"
        return 0
        ;;
      x)
        tput cnorm 2>/dev/null
        printf "\r  ${c_amber}kill session '${session}'? [y/N]: ${c_r}"
        read -sk1 confirm
        if [[ "$confirm" == "y" ]]; then
          _dashboard_kill
          echo ""
          echo "  Session killed."
          return 0
        fi
        tput civis 2>/dev/null
        prev_frame=""
        ;;
    esac
  done

  tput cnorm 2>/dev/null
  echo "  Session '${session}' ended."
}
