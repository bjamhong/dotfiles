#!/usr/bin/env zsh

emulate -L zsh
setopt no_unset pipe_fail

SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/../worktree.zsh" >/dev/null 2>&1

function fail() {
  print -u2 -- "FAIL: $1"
  exit 1
}

function assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  if [ "$expected" != "$actual" ]; then
    fail "$label (expected '$expected', got '$actual')"
  fi
}

function assert_contains() {
  local needle="$1"
  local haystack="$2"
  local label="$3"

  if ! print -r -- "$haystack" | grep -F -- "$needle" >/dev/null; then
    fail "$label (missing '$needle')"
  fi
}

function assert_not_exists() {
  local path="$1"
  local label="$2"

  if [ -e "$path" ]; then
    fail "$label ($path still exists)"
  fi
}

function _test_strip_ansi() {
  perl -pe 's/\e\[[0-9;]*m//g'
}

function _test_setup_identity() {
  local repo="$1"

  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name test
}

function _test_init_remote_fixture() {
  local base="$1"

  git init --bare -q "$base/remote.git"
  git init -q "$base/src"
  _test_setup_identity "$base/src"
  git -C "$base/src" checkout -qb main
  print "init" > "$base/src/README.md"
  mkdir -p "$base/src/notes"
  print "note" > "$base/src/notes/a.txt"
  git -C "$base/src" add README.md notes/a.txt
  git -C "$base/src" commit -qm init
  git -C "$base/src" remote add origin "$base/remote.git"
  git -C "$base/src" push -qu origin main
  git -C "$base/remote.git" symbolic-ref HEAD refs/heads/main

  git clone -q "$base/remote.git" "$base/clone-a"
  git clone -q "$base/remote.git" "$base/clone-b"
  _test_setup_identity "$base/clone-a"
  _test_setup_identity "$base/clone-b"
}

function test_status_badges_for_dirty_tree() {
  local base="$(mktemp -d /tmp/wt-status.XXXXXX)"
  local badge_text=""
  local picker_text=""
  local wtls_text=""
  local meta_text=""
  local ranked_worktrees=""
  local -a meta

  _test_init_remote_fixture "$base"

  print "changed" >> "$base/clone-a/README.md"
  print "scratch" > "$base/clone-a/untracked.txt"

  cd "$base/clone-a" || return 1
  meta_text="$(_wt_status_meta_for_path "$base/clone-a")"
  meta=("${(@ps:\t:)meta_text}")
  assert_eq "1" "${meta[1]}" "tracked dirty flag"
  assert_eq "1" "${meta[2]}" "untracked dirty flag"
  assert_eq "0" "${meta[3]}" "conflicted flag"

  badge_text="$(_wt_status_badges_plain "${meta[@]}")"
  assert_contains "M" "$badge_text" "tracked badge"
  assert_contains "?" "$badge_text" "untracked badge"

  ranked_worktrees="$(_wt_ranked_worktrees)"
  picker_text="$(print -r -- "$(_wt_picker_items main "$ranked_worktrees")" | _test_strip_ansi)"
  assert_contains $'branch-item\t' "$picker_text" "picker branch row"
  assert_contains "clone-a" "$picker_text" "picker worktree row"

  wtls_text="$(print -r -- "$(_wt_display_lines "$ranked_worktrees")" | _test_strip_ansi)"
  assert_contains "State" "$wtls_text" "wtls state column"
  assert_contains "M ?" "$wtls_text" "wtls dirty badges"

  cd / || return 1
  rm -rf "$base"
}

function test_status_badges_for_ahead_and_behind() {
  local base="$(mktemp -d /tmp/wt-ahead-behind.XXXXXX)"
  local badge_text=""
  local meta_text=""
  local -a meta

  _test_init_remote_fixture "$base"

  print "local" >> "$base/clone-a/README.md"
  git -C "$base/clone-a" commit -qam "local change"

  print "remote" >> "$base/clone-b/README.md"
  git -C "$base/clone-b" commit -qam "remote change"
  git -C "$base/clone-b" push -q origin main

  git -C "$base/clone-a" fetch -q origin

  cd "$base/clone-a" || return 1
  meta_text="$(_wt_status_meta_for_path "$base/clone-a")"
  meta=("${(@ps:\t:)meta_text}")
  assert_eq "1" "${meta[4]}" "ahead count"
  assert_eq "1" "${meta[5]}" "behind count"

  badge_text="$(_wt_status_badges_plain "${meta[@]}")"
  assert_contains "↑1" "$badge_text" "ahead badge"
  assert_contains "↓1" "$badge_text" "behind badge"

  cd / || return 1
  rm -rf "$base"
}

function test_parse_picker_result_handles_blank_key_line() {
  local raw_result=$'\n__CREATE__\tcreate\t+ Create new worktree'
  local parsed="$(_wt_parse_picker_result "$raw_result")"
  local key="${parsed%%$'\n'*}"
  local selected="${parsed#*$'\n'}"
  selected="${selected%%$'\n'*}"

  assert_eq "" "$key" "blank key line"
  assert_eq $'__CREATE__\tcreate\t+ Create new worktree' "$selected" "selected row payload"
}

function test_delete_worktree_path_removes_branch_and_directory() {
  local base="$(mktemp -d /tmp/wt-delete.XXXXXX)"
  local managed_dir=""
  local wt_path=""

  _test_init_remote_fixture "$base"

  cd "$base/clone-a" || return 1
  managed_dir="$(_wt_managed_dir)"
  wt_path="$managed_dir/feature"

  git worktree add -q -b feature "$wt_path" HEAD
  _wt_delete_worktree_path "$wt_path" false >/dev/null

  assert_not_exists "$wt_path" "deleted worktree path"
  assert_not_exists "$managed_dir" "cleaned managed dir"

  if git -C "$base/clone-a" show-ref --verify --quiet refs/heads/feature; then
    fail "deleted worktree branch still exists"
  fi

  cd / || return 1
  rm -rf "$base"
}

function run_test() {
  local name="$1"
  shift

  "$@"
  print -- "ok - $name"
}

run_test "status badges for dirty tree" test_status_badges_for_dirty_tree
run_test "status badges for ahead/behind" test_status_badges_for_ahead_and_behind
run_test "parse picker result handles blank key line" test_parse_picker_result_handles_blank_key_line
run_test "delete worktree path removes branch and directory" test_delete_worktree_path_removes_branch_and_directory
