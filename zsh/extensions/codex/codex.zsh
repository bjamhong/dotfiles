# Codex with YOLO mode by default.
# Use `command codex ...` to bypass this wrapper for one-off non-yolo runs.
function codex() {
  command codex --yolo "$@"
}
