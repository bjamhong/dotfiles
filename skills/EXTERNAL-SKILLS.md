# External Skills

Registry of agent skills that are **not authored here** and **not vendored** —
they're installed on demand from upstream (via `npx`, a curl installer, etc.).
This is the "what I want available on a machine / in a project" list, distinct
from the hand-written skills under `skills/*/SKILL.md`.

Why track them separately:

- They update upstream frequently, so we deliberately **don't** copy them into
  dotfiles — vendoring would rot.
- But we still want a durable record of which ones we rely on, so a new machine
  or new project can pull the same set.

How they're used: most are fetched on demand by an orchestrator skill rather than
installed globally. For example, [`design-skills`](./design-skills/SKILL.md) runs
the install commands below at the start of frontend work and always pulls
`@latest`.

## Skills

### Frontend / UI design — pulled by `design-skills`

| Pack | Source | Install (latest) | Invoke |
|------|--------|------------------|--------|
| **impeccable** | `github.com/pbakaus/impeccable` (npm `impeccable`) | `npx -y impeccable@latest skills install` | `/impeccable <command>` |
| **ui-skills** | `github.com/ibelick/ui-skills` (npm `ui-skills`) | `npx -y ui-skills@latest add "baseline-ui fixing-accessibility fixing-motion-performance"` | `/baseline-ui`, `/fixing-accessibility`, `/fixing-motion-performance` |

We scope ui-skills to **three** skills on purpose — the pack ships more, but we
only want `baseline-ui`, `fixing-accessibility`, and `fixing-motion-performance`.
Do not install with `--all`.

Generic fallback (agentskills.io CLI): `npx -y skills add <owner>/<repo>` — note
this pulls a whole repo, so for ui-skills prefer the scoped command above.

## Notes

- **Install target:** these install per-project into the harness skills dir
  (`.agents/skills/`, `.claude/skills/`, …) and are meant to be gitignored in the
  consuming project, not committed.
- **Requirements:** network access + `npx` / node.
- **Adding one:** append a row with its source + install command, and note which
  orchestrator skill (if any) pulls it. If it isn't pulled by an orchestrator,
  say where/when it should be installed.
