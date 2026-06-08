# Skills

Tracked home for reusable agent skills.

The live local skills path is:

```text
~/.agents/skills
```

That path should be a symlink to this directory so local tools can keep using
their expected location while the skill source stays in dotfiles.

## External skills

Skills installed from upstream on demand (via `npx`, etc.) rather than authored
here are tracked in [`EXTERNAL-SKILLS.md`](./EXTERNAL-SKILLS.md). That file is the
source of truth for which external skill packs we want available, and how to
install them — it is intentionally not vendored, since those packs update often.
