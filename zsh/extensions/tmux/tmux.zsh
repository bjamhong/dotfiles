# Kill a tmux session and its grouped sessions.
# Usage: tkill <session_name>
function tkill() {
  local session_name="$1"

  if [ -z "$session_name" ]; then
    echo "Usage: tkill <session_name>"
    return 1
  fi

  # Kill grouped sessions created by the old Ghostty tab integration.
  for s in $(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^${session_name}-g"); do
    tmux kill-session -t "$s" 2>/dev/null
  done

  tmux kill-session -t "$session_name" 2>/dev/null
}
