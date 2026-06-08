#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bugbot-sentinel.sh [PR_NUMBER_OR_URL_OR_BRANCH] [--interval SECONDS]

Waits for GitHub PR checks, then reports whether Cursor Bugbot left comments on
the current PR head. This script does not edit files, commit, push, or reply.

Exit codes:
  0  Checks completed and no current-head Bugbot comments were found.
  2  Current-head Bugbot comments were found; Codex should inspect and fix.
  4  Checks failed or gh could not complete the check watch.
USAGE
}

interval=10
pr_arg=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval)
      if [[ $# -lt 2 ]]; then
        echo "bugbot-sentinel: --interval requires a value" >&2
        exit 64
      fi
      interval="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -n "$pr_arg" ]]; then
        echo "bugbot-sentinel: only one PR argument is supported" >&2
        exit 64
      fi
      pr_arg="$1"
      shift
      ;;
  esac
done

if ! command -v gh >/dev/null 2>&1; then
  echo "bugbot-sentinel: gh CLI is required" >&2
  exit 127
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "bugbot-sentinel: gh is not authenticated; run gh auth login" >&2
  exit 4
fi

repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
if [[ -z "$repo" ]]; then
  echo "bugbot-sentinel: could not resolve current GitHub repository" >&2
  exit 4
fi

if [[ -n "$pr_arg" ]]; then
  pr_json="$(gh pr view "$pr_arg" --json number,headRefOid,url --jq '[.number, .headRefOid, .url] | @tsv')"
else
  pr_json="$(gh pr view --json number,headRefOid,url --jq '[.number, .headRefOid, .url] | @tsv')"
fi

IFS=$'\t' read -r pr_number head_oid pr_url <<<"$pr_json"
if [[ -z "$pr_number" || -z "$head_oid" ]]; then
  echo "bugbot-sentinel: could not resolve PR number/head" >&2
  exit 4
fi

echo "bugbot-sentinel: repo=$repo pr=#$pr_number head=$head_oid"
echo "bugbot-sentinel: $pr_url"
echo "bugbot-sentinel: waiting for PR checks..."

set +e
gh pr checks "$pr_number" --watch --interval "$interval"
checks_status=$?
set -e

head_date="$(gh api "repos/$repo/commits/$head_oid" --jq '.commit.committer.date' 2>/dev/null || true)"

review_comments="$(
  gh api --paginate "repos/$repo/pulls/$pr_number/comments" \
    --jq ".[] | select(.user.login == \"cursor[bot]\" and .commit_id == \"$head_oid\") | \"review-comment\t\" + (.path // \"\") + \":\" + ((.line // .original_line // 0) | tostring) + \"\t\" + (.html_url // \"\")" \
    2>/dev/null || true
)"

review_bodies="$(
  gh api --paginate "repos/$repo/pulls/$pr_number/reviews" \
    --jq ".[] | select(.user.login == \"cursor[bot]\" and .commit_id == \"$head_oid\" and ((.body // \"\") | length > 0)) | \"review\t\" + (.state // \"\") + \"\t\" + (.html_url // \"\")" \
    2>/dev/null || true
)"

issue_comments=""
if [[ -n "$head_date" ]]; then
  issue_comments="$(
    gh api --paginate "repos/$repo/issues/$pr_number/comments" \
      --jq ".[] | select(.user.login == \"cursor[bot]\" and .updated_at >= \"$head_date\") | \"issue-comment\t\" + (.updated_at // \"\") + \"\t\" + (.html_url // \"\")" \
      2>/dev/null || true
  )"
fi

bugbot_hits="$(printf '%s\n%s\n%s\n' "$review_comments" "$review_bodies" "$issue_comments" | sed '/^[[:space:]]*$/d')"

if [[ -n "$bugbot_hits" ]]; then
  echo "bugbot-sentinel: Cursor Bugbot left comments on or after this head:"
  printf '%s\n' "$bugbot_hits"
  exit 2
fi

if [[ "$checks_status" -ne 0 ]]; then
  echo "bugbot-sentinel: PR checks did not complete cleanly; gh pr checks exited $checks_status" >&2
  exit 4
fi

echo "bugbot-sentinel: checks completed and no current-head Bugbot comments were found"
exit 0
