# Claude Code UI & CLI Design Patterns

Notes on how Claude Code approaches terminal UI — applicable patterns for building CLI tools.

## Rendering: No Flicker

The #1 lesson. Claude Code rewrote their renderer from scratch to reduce flickering by ~85%.

### Synchronized Output (DEC mode 2026)

Wrap draw cycles in `CSI ? 2026 h` (begin) / `CSI ? 2026 l` (end). The terminal buffers everything between these markers and renders atomically. Supported by Ghostty, iTerm2, Kitty, WezTerm.

In bash/zsh, this translates to:
```bash
printf '\033[?2026h'   # begin synchronized update
# ... all your drawing ...
printf '\033[?2026l'   # end synchronized update
```

This single technique eliminates most visual tearing in refresh loops.

### Cell-Level Diffing > Full Redraws

Claude Code diffs the previous frame against the new frame at the character-cell level and only emits ANSI sequences for changed cells. For a bash dashboard, the equivalent is:
- Build the full frame in a string variable first
- Only `clear` + rewrite when content actually changed
- Or better: use cursor positioning (`\033[<row>;<col>H`) to overwrite specific lines

### Static vs Dynamic Regions

Claude Code splits output into:
- **Static**: completed messages, rendered once, never re-rendered
- **Dynamic**: the live input area, status bar, streaming text

For a refresh loop, this means: don't redraw parts of the screen that haven't changed. Only refresh the data region.

## Input: Non-blocking with Timeout

Claude Code uses raw mode stdin with React's event loop. The bash equivalent for an interactive dashboard:

```bash
read -sk1 -t2 key   # zsh: single key, 2s timeout
```

This gives you both auto-refresh (timeout expires → redraw) and instant response to keypresses. The key insight: **input and rendering share the same loop**, not separate threads.

### Two-Tier Interrupt

- First ctrl-c: cancel current operation (soft)
- Second ctrl-c: exit entirely (hard)

For a dashboard, map this to:
- `q` → detach (safe, keep state)
- `x` → kill (destructive, confirm first)

## Layout: Open-Sided Borders

Claude Code's most distinctive visual pattern: boxes with `borderRight: false` and often `borderBottom: false`. This creates section dividers rather than enclosed boxes.

```
╭─ section title ──────────────────────
│
│  content here
│  more content
│
╰──────────────────────────────────────
```

Why this works:
- Easier to implement (no right-side padding calculations with ANSI)
- Feels lighter and more modern than full boxes
- Content can flow naturally without width constraints

### Round Box Characters (Primary Style)

```
╭ ─ ╮   (top: U+256D, U+2500, U+256E)
│   │   (sides: U+2502)
╰ ─ ╯   (bottom: U+2570, U+2500, U+256F)
```

## Color: Theme with ANSI Fallback

Claude Code has 5 themes but the key pattern is: **design for truecolor, degrade to ANSI-16**.

### Core Palette (Dark Theme)

| Role        | RGB                  | ANSI-16 Fallback |
|-------------|----------------------|-------------------|
| Brand       | `rgb(215,119,87)`    | bright red (91)   |
| Border      | `rgb(136,136,136)`   | white (37)        |
| Success     | `rgb(78,186,101)`    | bright green (92) |
| Error       | `rgb(255,107,128)`   | bright red (91)   |
| Warning     | `rgb(255,193,7)`     | bright yellow (93)|
| Info/Action | `rgb(177,185,249)`   | bright blue (94)  |
| Dim         | `\033[2m`            | `\033[2m`         |

### In Practice (bash/zsh)

```bash
# Truecolor
local C_BRAND=$'\033[38;2;215;119;87m'
local C_GREEN=$'\033[38;2;78;186;101m'
local C_BORDER=$'\033[38;2;136;136;136m'
local C_DIM=$'\033[2m'
local C_BOLD=$'\033[1m'
local C_R=$'\033[0m'
```

## Symbols

| Symbol | Unicode | Usage |
|--------|---------|-------|
| `❯`    | U+276F  | pointer / selection |
| `✔`    |         | success / completed |
| `✘`    | U+2718  | error / failure |
| `●`    | U+25CF  | list item / active |
| `…`    | U+2026  | truncation |
| `ℹ`    | U+2139  | informational |

Spinner frames: `⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏` (braille dots)

## Terminal Lifecycle

### Cursor Management

```bash
tput civis    # hide cursor (during dashboard rendering)
tput cnorm    # show cursor (before prompts + on exit)
```

Always restore cursor in cleanup — use `trap` to ensure this.

### No Alternate Screen Buffer

Claude Code deliberately stays on the main screen buffer (no `tput smcup`). Reason: users need native scrollback, Cmd+F search, and text selection. The tradeoff is you have to manage scrollback yourself, but the UX is better.

### Cleanup Pattern

```bash
trap 'tput cnorm 2>/dev/null; ... ; return 0' INT
```

Always restore: cursor visibility, terminal modes, child processes. Kill grouped tmux sessions, temp files, etc.

## Performance Heuristics for Shell Scripts

1. **Don't spawn subprocesses in the render loop** if avoidable. Each `$(...)` is a fork. Pre-compute what you can.
2. **Cap refresh rate** — 2s is fine for a dashboard. Don't go below 500ms in bash.
3. **Build the frame in a variable**, then print once — avoids partial rendering.
4. **Use `printf` over `echo`** — more portable, better escape handling.
5. **Synchronized output** eliminates the remaining visual artifacts.

## Streaming Output Without Layout Thrash

Claude Code targets token-by-token rendering. Key patterns:
- **Throttle renders** to a fixed frame budget (they use ~16ms / 60fps)
- **Batch state updates** — multiple tokens arriving in one event loop tick produce one render
- **Separate static from live content** — only re-render the active region

For bash, this means: if you're tailing a log or streaming output, write new lines directly without clearing/redrawing the entire screen.
