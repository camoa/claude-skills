#!/usr/bin/env bash
# worktree-signals-spec.sh — a signal that fired on the framework's own footprint.
#
# `dirty_tree` counted every line of `git status --porcelain`, untracked files included, while
# the script's own contract said it meant "modified files matching another task's tracked files".
# One untracked file made it fire, made strength `high`, and recommended isolating the work in a
# worktree.
#
# The framework supplied that file itself. `install-task-rule` writes CLAUDE.md into the code
# repository and does not commit it, so a live run was told to take a worktree for a three-line
# config edit on the strength of a file this plugin had put there. A signal that fires on its own
# footprint is not evidence about the tree.
#
# The other half: the command body documented a one-argument call for a script that needs two,
# so a session following it verbatim got bash naming the positional parameter.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
K="$PLUGIN_ROOT/scripts/worktree-signals.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# A code repo and a project folder pointing at it.
REPO="$TMP/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
echo base > "$REPO/tracked.txt"
git -C "$REPO" add tracked.txt
git -C "$REPO" commit -qm base

PROJ="$TMP/proj"; mkdir -p "$PROJ"
printf '# Project: t\n**Code Path:** %s\n' "$REPO" > "$PROJ/project_state.md"

sig() { bash "$K" "$PROJ" sometask 2>/dev/null; }

# --- the live case: only an untracked file --------------------------------------------

echo "rule" > "$REPO/CLAUDE.md"          # exactly what install-task-rule leaves behind
OUT=$(sig)
[ "$(printf '%s' "$OUT" | jq -r '.signal_details.dirty_tree.fired')" = "false" ] \
  && pass_check "an untracked file alone does not fire the tree signal" \
  || fail_check "an untracked file fired the signal, as the framework's own CLAUDE.md did"

[ "$(printf '%s' "$OUT" | jq -r .strength)" = "none" ] \
  && pass_check "an untracked file alone does not recommend a worktree" \
  || fail_check "a worktree was recommended on the strength of one untracked file"

[ "$(printf '%s' "$OUT" | jq -r '.signal_details.dirty_tree.untracked_files')" = "1" ] \
  && pass_check "the untracked file is still counted and visible" \
  || fail_check "the untracked file vanished from the record instead of being reported"

# --- a genuinely dirty tree still fires ------------------------------------------------

echo changed >> "$REPO/tracked.txt"
OUT=$(sig)
[ "$(printf '%s' "$OUT" | jq -r '.signal_details.dirty_tree.fired')" = "true" ] \
  && pass_check "an uncommitted change to a tracked file fires the signal" \
  || fail_check "real uncommitted work no longer fires the signal"

[ "$(printf '%s' "$OUT" | jq -r .strength)" = "high" ] \
  && pass_check "real uncommitted work still reads as high strength" \
  || fail_check "real uncommitted work stopped recommending a worktree"

[ "$(printf '%s' "$OUT" | jq -r '.signal_details.dirty_tree.modified_tracked_files')" = "1" ] \
  && pass_check "the tracked count is what the signal is based on" \
  || fail_check "the tracked count does not match what fired"

# A staged change is uncommitted work too.
git -C "$REPO" add tracked.txt
[ "$(sig | jq -r '.signal_details.dirty_tree.fired')" = "true" ] \
  && pass_check "a staged change counts as uncommitted work" \
  || fail_check "staging a change made the signal stop seeing it"

# --- a clean tree ----------------------------------------------------------------------

git -C "$REPO" commit -qm change
rm -f "$REPO/CLAUDE.md"
OUT=$(sig)
[ "$(printf '%s' "$OUT" | jq -r .strength)" = "none" ] \
  && pass_check "a clean tree recommends nothing" \
  || fail_check "a clean tree recommended a worktree"
printf '%s' "$OUT" | jq empty >/dev/null 2>&1 \
  && pass_check "output is valid JSON" \
  || fail_check "output is not valid JSON"

# --- the error a person reads ----------------------------------------------------------

set +e
ERR=$(bash "$K" "$PROJ" 2>&1 >/dev/null); RC=$?
set -e
[ "$RC" -eq 1 ] && pass_check "a one-argument call exits 1" || fail_check "a one-argument call exited $RC"
case "$ERR" in
  *"line "*) fail_check "the one-argument error still shows bash internals: $ERR" ;;
  usage:*)   pass_check "the one-argument error is a usage line and nothing else" ;;
  *)         fail_check "the one-argument error does not start with a usage line: $ERR" ;;
esac

# --- the command body's call must be runnable -------------------------------------------

# The bug was here, not in the script: implement.md documented a one-argument call.
CMD="$PLUGIN_ROOT/commands/implement.md"
if grep -q 'worktree-signals\.sh "<project_folder>" "<task_name>"' "$CMD"; then
  pass_check "the command body documents both arguments"
else
  fail_check "the command body's documented call does not pass both arguments, so following it fails"
fi

# The contract in the script header has to describe what the code does.
if grep -q 'uncommitted changes to TRACKED files' "$K"; then
  pass_check "the documented signal matches what the code counts"
else
  fail_check "the header describes a signal the code does not compute"
fi

printf '\n'
[ "$FAIL" -eq 0 ] && { printf 'worktree-signals-spec: all checks passed\n'; exit 0; }
printf 'worktree-signals-spec: FAILURES\n' >&2; exit 1
