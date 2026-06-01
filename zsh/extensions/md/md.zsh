# Read Markdown files with glow in pager mode by default.
if command -v glow >/dev/null 2>&1; then
  alias md='glow -p'
fi
