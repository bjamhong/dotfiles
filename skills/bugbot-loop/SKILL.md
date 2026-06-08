---
name: bugbot-loop
description: Run an autonomous GitHub PR review loop for Cursor Bugbot. Use when the user asks to wait for Bugbot, watch Bugbot comments, address Cursor/Bugbot PR review findings, or keep iterating on a PR until Bugbot checks and comments are clean. The skill uses a sentinel script to wait efficiently, then Codex triages comments, implements valid routine fixes without asking, runs tests, pushes separate follow-up commits, and repeats until clean or genuinely blocked.
---

# Bugbot Loop

Use this skill to run a conservative Cursor Bugbot review loop for the current GitHub pull request.

## Workflow

1. Resolve the current PR and HEAD with `gh pr view --json number,headRefOid,url`.
2. Run `scripts/bugbot-sentinel.sh` from this skill in the foreground.
3. If the sentinel exits `0`, report that Bugbot is clean.
4. If the sentinel exits `2`, fetch current-head Cursor Bugbot comments with `gh`.
5. Read the relevant code and decide which comments are valid.
6. Implement warranted fixes only.
7. Run targeted tests and formatting checks.
8. Commit fixes as a separate follow-up commit. Do not amend existing commits.
9. Push the branch.
10. Re-run the sentinel against the new PR HEAD.
11. Continue until Bugbot is clean or a finding requires genuine human/product judgment.

## Sentinel

The script path is relative to this skill:

```bash
scripts/bugbot-sentinel.sh
```

From any repo, run it by absolute path if needed:

```bash
~/.agents/skills/bugbot-loop/scripts/bugbot-sentinel.sh
```

Exit codes:

- `0`: checks completed and no current-head Bugbot comments were found.
- `2`: current-head Bugbot comments were found and should be inspected.
- `4`: checks failed or `gh` could not complete the check watch.

The sentinel only waits and reports. It must not edit files, commit, push, merge, or reply on GitHub.

## Comment Fetching

After sentinel exit `2`, fetch comments for the current PR HEAD. Prefer `gh` because it preserves commit IDs and URLs.

Useful commands:

```bash
gh pr view --json number,headRefOid,url
gh api --paginate "repos/OWNER/REPO/pulls/PR/comments"
gh api --paginate "repos/OWNER/REPO/pulls/PR/reviews"
gh api --paginate "repos/OWNER/REPO/issues/PR/comments"
```

Only act on comments tied to the current `headRefOid`, or top-level Bugbot comments created after the current HEAD commit timestamp.

## Guardrails

- Do not blindly apply Bugbot suggestions.
- Do not ask for confirmation before routine fixes. Use senior engineering judgment and proceed autonomously when the issue and fix are clear.
- Ignore stale comments from older commits.
- Keep fixes scoped to valid Bugbot findings.
- Never auto-merge.
- Never force-push unless the user explicitly asks for amend/squash mode.
- Do not amend existing commits in this workflow.
- If a finding appears false-positive, verify from code. Do not modify code just to appease the bot. Continue the loop if no code change is needed, and include the false-positive note in the final summary.
- Stop only if the false-positive needs a GitHub reply, a human decision, or broader product/security/API judgment.
- Stop and ask if a finding requires changing product behavior, pricing/security policy, public API semantics, data-retention policy, or another meaningful tradeoff.
- Stop and summarize if tests fail for unclear or unrelated reasons.

## Commit And Push

When fixes are warranted, use a separate follow-up commit:

```bash
git commit -m "Fix Bugbot review findings"
git push
```

If the working tree contains unrelated user changes, preserve them and avoid including them in the commit.

## Summary

At the end, report:

- PR number and final HEAD SHA.
- Whether Bugbot is clean.
- Follow-up commits pushed.
- Tests run.
- Any comments intentionally left unresolved and why.
