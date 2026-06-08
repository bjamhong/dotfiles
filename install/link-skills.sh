#!/bin/sh
# Link dotfiles skills into the locations each agent harness reads.
#
# Most harnesses (Codex, Pi, Cursor, Gemini, OpenCode, Copilot) read
# ~/.agents/skills, which we point at this repo's skills/ as a single
# whole-directory symlink.
#
# Claude Code is the odd one out: it reads ONLY ~/.claude/skills (it does not
# fall back to ~/.agents/skills), so we create one per-skill symlink there for
# each skill in the repo. Non-skill files (README.md, EXTERNAL-SKILLS.md, etc.)
# are skipped — a skill is a directory containing a SKILL.md.
#
# Idempotent: safe to re-run. Re-run after adding or removing a skill.

set -eu

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
SKILLS_SRC="$DOTFILES/skills"

if [ ! -d "$SKILLS_SRC" ]; then
  echo "error: $SKILLS_SRC not found" >&2
  exit 1
fi

# 1. Whole-dir symlink for harnesses that read ~/.agents/skills.
ln -sfn "$SKILLS_SRC" "$HOME/.agents/skills"
echo "linked ~/.agents/skills -> $SKILLS_SRC"

# 2. Per-skill symlinks for Claude Code (~/.claude/skills).
CLAUDE_SKILLS="$HOME/.claude/skills"
mkdir -p "$CLAUDE_SKILLS"

# 2a. Prune stale (dangling) links that point back into our skills source.
for link in "$CLAUDE_SKILLS"/*; do
  [ -L "$link" ] || continue
  target="$(readlink "$link")"
  case "$target" in
    *"/dotfiles/skills/"* | *"/.agents/skills/"*)
      if [ ! -e "$link" ]; then
        rm -f "$link"
        echo "pruned stale link $(basename "$link")"
      fi
      ;;
  esac
done

# 2b. Create/refresh a link for each real skill (a dir containing SKILL.md).
for dir in "$SKILLS_SRC"/*/; do
  [ -f "${dir}SKILL.md" ] || continue
  name="$(basename "$dir")"
  dest="$CLAUDE_SKILLS/$name"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    echo "skip $name: $dest exists and is not a symlink" >&2
    continue
  fi
  ln -sfn "$SKILLS_SRC/$name" "$dest"
  echo "linked ~/.claude/skills/$name"
done

echo "done. Restart your agent session to pick up newly linked skills."
