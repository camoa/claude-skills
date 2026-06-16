#!/usr/bin/env bash
# TDD spec for scripts/wo-merge-back.sh — deterministic local-merge kernel.
# Builds throwaway git repos with `git init` and exercises clean/conflict/precondition paths.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
export CLAUDE_PLUGIN_ROOT="$ROOT"
SUT="$ROOT/scripts/wo-merge-back.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# krun: run the SUT, capture OUT (stdout) and RC (exit code). stderr suppressed.
krun() { OUT="$(bash "$SUT" "$@" 2>/dev/null)"; RC=$?; }

fail_check() {
  FAIL=$((FAIL+1))
  echo "FAIL $1: $2"
  [ -n "${OUT:-}" ] && echo "  out: $OUT"
}
pass_check() { PASS=$((PASS+1)); }

# git_q: run git in a repo dir, quietly.
git_q() { git -C "$1" "${@:2}" >/dev/null 2>&1; }

# mkrepo: init a repo at $TMP/$1 with a base commit (file base.txt), integration branch checked out.
mkrepo() {
  local d="$TMP/$1"; mkdir -p "$d"
  git_q "$d" init
  git_q "$d" config user.email "test@example.com"
  git_q "$d" config user.name  "Test User"
  git_q "$d" checkout -b integration
  printf 'base\n' > "$d/base.txt"
  git_q "$d" add base.txt
  git_q "$d" commit -m "base"
  echo "$d"
}

# ---------------------------------------------------------------------------
# T1: disjoint files merge clean — wo-01 adds a.txt; integration adds b.txt → merged:true,
#     HEAD sha changes, a.txt present on integration, exit 0.
D="$(mkrepo t1)"
git_q "$D" checkout -b wo-01
printf 'aaa\n' > "$D/a.txt"; git_q "$D" add a.txt; git_q "$D" commit -m "wo-01 adds a"
git_q "$D" checkout integration
printf 'bbb\n' > "$D/b.txt"; git_q "$D" add b.txt; git_q "$D" commit -m "integration adds b"
HEAD_BEFORE="$(git -C "$D" rev-parse HEAD)"
krun "$D" wo-01
HEAD_AFTER="$(git -C "$D" rev-parse HEAD)"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.merged' <<<"$OUT")" = "true" ] \
  && [ "$(jq -r '.branch' <<<"$OUT")" = "wo-01" ] \
  && [ "$(jq -r '.reason' <<<"$OUT")" = "null" ] \
  && [ "$(jq -r '.sha'    <<<"$OUT")" = "$HEAD_AFTER" ] \
  && [ "$HEAD_AFTER" != "$HEAD_BEFORE" ] \
  && [ -f "$D/a.txt" ]; then
  pass_check "T1 disjoint clean merge: merged=true, HEAD advanced, a.txt present"
else
  fail_check "T1 disjoint clean merge" \
    "merged=$(jq -r '.merged' <<<"$OUT" 2>/dev/null) rc=$RC head_changed=$([ "$HEAD_AFTER" != "$HEAD_BEFORE" ] && echo yes || echo no) a_present=$([ -f "$D/a.txt" ] && echo yes || echo no)"
fi

# ---------------------------------------------------------------------------
# T2: conflicting same-file merge — base x.txt; wo-02 and integration change x.txt divergently
#     → merged:false, reason=merge_conflict, conflicts includes x.txt, HEAD UNCHANGED,
#       git status --porcelain empty (abort cleaned), exit 3.
D="$(mkrepo t2)"
printf 'original\n' > "$D/x.txt"; git_q "$D" add x.txt; git_q "$D" commit -m "add x"
git_q "$D" checkout -b wo-02
printf 'from-wo\n' > "$D/x.txt"; git_q "$D" add x.txt; git_q "$D" commit -m "wo edits x"
git_q "$D" checkout integration
printf 'from-integration\n' > "$D/x.txt"; git_q "$D" add x.txt; git_q "$D" commit -m "integration edits x"
HEAD_BEFORE="$(git -C "$D" rev-parse HEAD)"
krun "$D" wo-02
HEAD_AFTER="$(git -C "$D" rev-parse HEAD)"
PORCELAIN="$(git -C "$D" status --porcelain)"
if [ "$RC" -eq 3 ] \
  && [ "$(jq -r '.merged' <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.reason' <<<"$OUT")" = "merge_conflict" ] \
  && [ "$(jq -r '.sha'    <<<"$OUT")" = "$HEAD_BEFORE" ] \
  && [ "$(jq -r 'any(.conflicts[]; . == "x.txt")' <<<"$OUT")" = "true" ] \
  && [ "$HEAD_AFTER" = "$HEAD_BEFORE" ] \
  && [ -z "$PORCELAIN" ]; then
  pass_check "T2 conflict: merged=false, reason=merge_conflict, conflicts[x.txt], HEAD unchanged, tree clean, exit 3"
else
  fail_check "T2 conflict path" \
    "rc=$RC merged=$(jq -r '.merged' <<<"$OUT" 2>/dev/null) reason=$(jq -r '.reason' <<<"$OUT" 2>/dev/null) head_unchanged=$([ "$HEAD_AFTER" = "$HEAD_BEFORE" ] && echo yes || echo no) clean=$([ -z "$PORCELAIN" ] && echo yes || echo no) conflicts=$(jq -c '.conflicts' <<<"$OUT" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# T3: missing branch → exit 2, error=branch_not_found.
D="$(mkrepo t3)"
krun "$D" no-such-branch
if [ "$RC" -eq 2 ] \
  && [ "$(jq -r '.ok'    <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.error' <<<"$OUT")" = "branch_not_found" ]; then
  pass_check "T3 missing branch: exit 2, error=branch_not_found"
else
  fail_check "T3 missing branch" \
    "rc=$RC ok=$(jq -r '.ok' <<<"$OUT" 2>/dev/null) error=$(jq -r '.error' <<<"$OUT" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# T4: dirty integration tree → exit 2, error=dirty_tree, NO merge attempted (HEAD unchanged).
D="$(mkrepo t4)"
git_q "$D" checkout -b wo-04
printf 'aaa\n' > "$D/a.txt"; git_q "$D" add a.txt; git_q "$D" commit -m "wo adds a"
git_q "$D" checkout integration
printf 'uncommitted\n' > "$D/dirty.txt"   # untracked → dirty working tree
HEAD_BEFORE="$(git -C "$D" rev-parse HEAD)"
krun "$D" wo-04
HEAD_AFTER="$(git -C "$D" rev-parse HEAD)"
if [ "$RC" -eq 2 ] \
  && [ "$(jq -r '.ok'    <<<"$OUT")" = "false" ] \
  && [ "$(jq -r '.error' <<<"$OUT")" = "dirty_tree" ] \
  && [ "$HEAD_AFTER" = "$HEAD_BEFORE" ]; then
  pass_check "T4 dirty tree: exit 2, error=dirty_tree, no merge attempted"
else
  fail_check "T4 dirty tree" \
    "rc=$RC error=$(jq -r '.error' <<<"$OUT" 2>/dev/null) head_unchanged=$([ "$HEAD_AFTER" = "$HEAD_BEFORE" ] && echo yes || echo no)"
fi

# ---------------------------------------------------------------------------
# T5: already-merged / up-to-date branch → merged:true (clean no-op), exit 0, HEAD unchanged.
# DECISION: an already-contained branch is a clean no-op. `git merge --no-ff` reports
# "Already up to date." (exit 0, no merge commit, nothing to abort), so the kernel treats it as
# merged:true with the HEAD sha unchanged — the WO's commits are already present, which is success.
D="$(mkrepo t5)"
git_q "$D" checkout -b wo-05
printf 'aaa\n' > "$D/a.txt"; git_q "$D" add a.txt; git_q "$D" commit -m "wo adds a"
git_q "$D" checkout integration
git_q "$D" merge --no-ff --no-edit wo-05      # land it once
HEAD_BEFORE="$(git -C "$D" rev-parse HEAD)"
krun "$D" wo-05                                 # second merge: up-to-date no-op
HEAD_AFTER="$(git -C "$D" rev-parse HEAD)"
if [ "$RC" -eq 0 ] \
  && [ "$(jq -r '.merged' <<<"$OUT")" = "true" ] \
  && [ "$(jq -r '.reason' <<<"$OUT")" = "null" ] \
  && [ "$(jq -r '.sha'    <<<"$OUT")" = "$HEAD_AFTER" ] \
  && [ "$HEAD_AFTER" = "$HEAD_BEFORE" ]; then
  pass_check "T5 already-merged: merged=true no-op, HEAD unchanged, exit 0"
else
  fail_check "T5 already-merged no-op" \
    "rc=$RC merged=$(jq -r '.merged' <<<"$OUT" 2>/dev/null) head_unchanged=$([ "$HEAD_AFTER" = "$HEAD_BEFORE" ] && echo yes || echo no)"
fi

# ---------------------------------------------------------------------------
# T6: not a git work tree → exit 2, error=not_a_work_tree.
PLAIN="$TMP/t6_plain"; mkdir -p "$PLAIN"
krun "$PLAIN" some-branch
if [ "$RC" -eq 2 ] \
  && [ "$(jq -r '.error' <<<"$OUT")" = "not_a_work_tree" ]; then
  pass_check "T6 non-git dir: exit 2, error=not_a_work_tree"
else
  fail_check "T6 non-git dir" "rc=$RC error=$(jq -r '.error' <<<"$OUT" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# T7: missing args → exit 2, error=usage.
krun
if [ "$RC" -eq 2 ] && [ "$(jq -r '.error' <<<"$OUT")" = "usage" ]; then
  pass_check "T7 missing args: exit 2, error=usage"
else
  fail_check "T7 missing args" "rc=$RC error=$(jq -r '.error' <<<"$OUT" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# T8: branch name carrying shell metacharacters is inert (jq --arg; data-only) on the error path.
D="$(mkrepo t8)"
META='evil; rm -rf ~'
krun "$D" "$META"
if [ "$RC" -eq 2 ] \
  && [ "$(jq -r '.error' <<<"$OUT")" = "branch_not_found" ]; then
  pass_check "T8 metachar branch: inert, error=branch_not_found, exit 2"
else
  fail_check "T8 metachar branch" "rc=$RC error=$(jq -r '.error' <<<"$OUT" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# Structural assertions on the kernel source.
# S1: contains `merge --abort` (the safe conflict inverse).
if grep -q 'merge --abort' "$SUT"; then
  pass_check "S1 source contains 'merge --abort'"
else
  fail_check "S1 source contains 'merge --abort'" "not found"
fi

# S2: forbidden ops absent from EXECUTABLE lines — NO push, NO gh, NO reset --hard, NO --force.
# Full-line comments are stripped first: the kernel's docstring legitimately NAMES these ops as
# forbidden, so a raw grep would false-positive on the documentation of the very rule being tested.
CODE="$(grep -vE '^[[:space:]]*#' "$SUT")"
FORBIDDEN=0
grep -qE '\bpush\b'     <<<"$CODE" && { echo "  forbidden: push";         FORBIDDEN=1; }
grep -qE '\bgh\b'       <<<"$CODE" && { echo "  forbidden: gh";           FORBIDDEN=1; }
grep -qE 'reset --hard' <<<"$CODE" && { echo "  forbidden: reset --hard"; FORBIDDEN=1; }
grep -qE '\-\-force'    <<<"$CODE" && { echo "  forbidden: --force";      FORBIDDEN=1; }
if [ "$FORBIDDEN" -eq 0 ]; then
  pass_check "S2 forbidden ops absent (push/gh/reset --hard/--force)"
else
  fail_check "S2 forbidden ops absent" "a forbidden op string was found in $SUT"
fi

# ---------------------------------------------------------------------------
echo "----"
echo "wo-merge-back-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
