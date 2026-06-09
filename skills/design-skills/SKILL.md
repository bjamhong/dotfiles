---
name: design-skills
description: Use for ANY frontend, UI, or visual-design work — building, restyling, or reviewing components, pages, layouts, CSS/Tailwind, animations/motion, accessibility, responsive behavior, or visual polish. This skill does not contain design rules; it routes the work through curated, frequently-updated external UI skill packs (impeccable, ui-skills) at their latest version. Invoke it before designing UI from scratch.
---

# Design Skills (orchestrator)

This skill holds **no design rules of its own**. It routes frontend work through
the real design guidance — two curated, frequently-updated external skill packs
— when they are available globally. Never hand-roll design opinions when these
packs are available, and never copy their content into this file or into dotfiles
(they change often; vendoring would rot).

## The packs (the only thing hardcoded here — sub-commands are discovered, not listed)

| Pack | Source | Shape |
|------|--------|-------|
| **impeccable** | `github.com/pbakaus/impeccable` (npm `impeccable`) | One `/impeccable` skill with many commands (shape, craft, critique, audit, polish, animate, harden, …), 7 domain references, and an anti-pattern detector CLI. |
| **ui-skills** | `github.com/ibelick/ui-skills` (npm `ui-skills`) | Standalone skills, each invoked on its own. The pack ships many — we deliberately scope to **three**: `baseline-ui`, `fixing-accessibility`, `fixing-motion-performance`. Don't install the rest. |

Do **not** maintain a command list in this file. The packs add/rename commands;
always derive the current set from the installed source (step 2).

## Workflow

### 1. Check global availability first

Do **not** install skill packs into the target repository by default. These
packs are reusable agent tooling, not project source. First check whether the
global/user-level skills are already available through the active agent
runtime's normal skill discovery mechanism.

Look for these skill names, using whatever skill listing, loaded-skill metadata,
or user-level skill directory the current runtime provides:

- `impeccable`
- `baseline-ui`
- `fixing-accessibility`
- `fixing-motion-performance`

If they are installed, use those global copies. Do not run `npx ... install`
from the target project root just to refresh them.

If one or more are missing, ask the user before installing globally. A concise
question is enough: "The design skill pack is not installed globally; should I
install it in this agent's global/user skill store?" Only install after the user
approves or has explicitly asked for installation.

When installation is approved, install to the current runtime's global/user
skill location, not inside the project repository. The exact path is
runtime-specific; the active agent should know or discover it from its own
environment.

Use the package installers only from an out-of-repo temp/cache directory, then
copy or move the resulting skills into that runtime's global/user skill store if
the installer does not support an explicit global target. Never leave generated
skill folders in the target repo unless the user explicitly asks to vendor them.

For `ui-skills`, install only the three scoped skills, not the whole pack:

```bash
npx -y ui-skills@latest add "baseline-ui fixing-accessibility fixing-motion-performance"
```

For `impeccable`, prefer its installer if it can target the current runtime's
global/user skill location. If it only auto-detects project harness folders, run
it in a temporary directory and copy the generated `impeccable` skill into the
global/user skill store. After installing, the harness may need a skills reload
before native slash commands appear. If it doesn't pick them up this session,
use step 3's fallback.

### 2. Discover what each pack provides (read the source, not your memory)

- **impeccable** — read the installed `impeccable/SKILL.md` and its command index
  / `reference/` directory (or `npx impeccable --help`). Each command maps to a
  `reference/<command>.md` you can open directly.
- **ui-skills** — list the installed skills directory and read each `SKILL.md`
  frontmatter `description` to learn that skill's scope and trigger.

This is the point of the orchestrator: it tells you **how to inspect**, so the
list stays current without editing this file.

### 3. Invoke naturally

Prefer native invocation once the harness has loaded the packs:

- impeccable: `/impeccable <command> <target>` — e.g. `/impeccable audit blog`.
- ui-skills: `/baseline-ui`, `/fixing-accessibility <file>`,
  `/fixing-motion-performance <file>`, …

**Harness-agnostic fallback (always works):** if the current session hasn't
surfaced the freshly installed skills as commands, just open the relevant
installed `SKILL.md` / `reference/*.md` and apply it directly — it's plain
markdown guidance. This makes the orchestrator work on pi, codex, and claude
regardless of which dir the installer targeted.

## Cadence — when to actually run them

Treat the packs as two different things with different frequencies. Do **not**
run review commands "whenever it feels right" — bind them to events.

**Guardrails — load once, hold for the whole session.** ui-skills `baseline-ui`
and impeccable's domain references are *constraints*, not actions. Load them at
the start of frontend work and keep them applied to every line of UI you write.
Don't re-invoke them repeatedly; internalize them.

**Review passes — run at checkpoints.** impeccable `critique` / `audit` /
`polish` and ui-skills `fixing-*` are discrete passes tied to lifecycle events:

- **Entry** (every frontend session): run step 1 (global availability check), load
  `baseline-ui`, and for any non-trivial new UI run impeccable `shape` before
  building. **Add the exit review (below) to your task list now** so it survives
  the mid-build flow and isn't forgotten.
- **Per unit**: after finishing a self-contained unit (a page, a component
  cluster), run a quick impeccable `audit` on just that unit and fix findings.
- **Exit (MUST)**: before reporting any UI work as done — and before any
  commit/PR — run impeccable `critique` + `audit`, fix what they surface, then
  `polish`. Do not call UI work "complete" until this has run; if findings are
  intentionally deferred, say so explicitly.

**Don't over-run.** One clean pass per unit is enough — don't re-audit unchanged
code, and skip the heavy review for trivial copy or one-line tweaks (but still
honor `baseline-ui`).

**Keep calibrating (back-of-mind).** The checkpoints above are defaults, not a
fixed script. As natural checkpoints in the development cycle arrive, keep a
running judgment about whether you're running the *right* commands at the *right*
rate, and adjust:

- Dial **up** when the surface is visual-heavy, novel, complex, or changing fast;
  dial **down** on stable, simple, or trivial areas.
- Match the command *mix* to the moment — don't fall into running the same one or
  two commands by habit while ignoring others that fit the current task better.
- Watch both failure modes: reviewing too rarely (design drift accumulates
  unnoticed) and too often (noise, wasted passes, re-checking unchanged code).

Aim for the cadence and selection that fit where you actually are in the cycle —
neither ceremonial nor neglectful.

> These are instructions, so compliance is model-dependent: they raise the odds,
> they don't guarantee. The only *hard* enforcement is a harness hook (e.g. a
> Claude Code `Stop` / `PostToolUse` hook that blocks completion until the audit
> ran). Hooks are Claude-only and not portable to pi/codex, so this skill leans
> on the checkpoints above for cross-harness behavior.

## Which to reach for (high level — confirm specifics by reading the packs)

- **Building / restyling UI** → impeccable `shape` to plan, then `craft` to build;
  keep ui-skills `baseline-ui` constraints applied throughout as guardrails.
- **Review / quality gate before shipping** → impeccable `critique` (UX) +
  `audit` (a11y / performance / responsive) + `polish`; run impeccable's
  anti-pattern detector.
- **Targeted fixes** → ui-skills `fixing-accessibility`,
  `fixing-motion-performance`; impeccable `harden`, `optimize`, `typeset`,
  `layout`, `animate`, `colorize` as the specific issue dictates.

Don't pick from this list blindly — open each pack's current command index
(step 2) and choose what actually fits the task.

## Rules

- Use globally installed packs when present; ask before installing or refreshing
  missing packs.
- Never install or refresh skill packs from the target project root unless the
  user explicitly asks to vendor project-local skills.
- Never copy pack content into this skill or into dotfiles.
- Let the packs own the design opinions; this skill only ensures agents check
  for them, ask before changing installation state, and use them when available.
