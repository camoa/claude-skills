#!/usr/bin/env bash
# Spec for save-session.sh's stdin handling.
#
# Reported live, repeatedly: "save-session.sh overran its timeout and went to background."
# It was never doing slow work — the file I/O finishes in hundredths of a second on a real
# task folder. It was blocking on `STDIN_JSON=$(cat)`.
#
# The script has two callers and only one of them feeds it. As a SessionEnd hook stdin
# carries the hook JSON and closes. Invoked as a command (/ai-dev-assistant:save-session)
# the descriptor can be open with nobody ever writing to it, and an unbounded read waits
# for input that never arrives until the caller's timeout kills it. Measured before the
# fix: exit 124, 0% CPU, killed at the cap.
#
# The read is now bounded by a bash builtin (no `timeout` dependency — this script is
# copied into user projects by /install-remembrance-hook, where PATH is not ours).
#
# Exit: 0 = all checks pass.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(dirname "$HERE")"
SUT="$ROOT/scripts/save-session.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; [ -n "${2:-}" ] && printf '  %s\n' "$2" >&2; }

[ -f "$SUT" ] || { echo "FAIL: $SUT missing" >&2; exit 1; }

# --- the case that was reported: stdin open, nobody ever writes ---
# The cap here is deliberately well above the script's own stdin budget, so a
# pass means the SCRIPT gave up, not that `timeout` cut it short.
SECONDS=0
SAVE_SESSION_STDIN_TIMEOUT=1 timeout 10 bash "$SUT" < <(sleep 30) >/dev/null 2>&1
RC=$?
ELAPSED=$SECONDS
if [ "$RC" -ne 124 ] && [ "$ELAPSED" -lt 8 ]; then
  ok "an open stdin nobody writes to returns on its own (rc=$RC, ${ELAPSED}s) instead of being killed"
else
  bad "an open stdin nobody writes to returns on its own" "rc=$RC elapsed=${ELAPSED}s (124 = killed by the cap)"
fi

# --- the hook case still works: JSON arrives and closes ---
OUT="$(printf '{"cwd":"/nonexistent/workspace/for/spec"}' | timeout 10 bash "$SUT" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ]; then
  ok "hook JSON on stdin is read and the script exits clean"
else
  bad "hook JSON on stdin is read and the script exits clean" "rc=$RC out=$OUT"
fi

# --- the command case with no input at all ---
timeout 10 bash "$SUT" < /dev/null >/dev/null 2>&1; RC=$?
if [ "$RC" -eq 0 ]; then
  ok "closed stdin exits clean and immediately"
else
  bad "closed stdin exits clean and immediately" "rc=$RC"
fi

# --- the mechanism is a builtin, because the script is copied into projects ---
if grep -qE 'read -r -d .. -t' "$SUT"; then
  ok "the read is bounded by the read builtin, not an external timeout"
else
  bad "the read is bounded by the read builtin, not an external timeout"
fi
if grep -q 'STDIN_JSON=$(cat' "$SUT"; then
  bad "the unbounded cat is back"
else
  ok "no unbounded cat on stdin remains"
fi

# --- the header no longer claims the script cannot overrun ---
if grep -q 'does bounded file I/O only and finishes far inside that budget' "$SUT"; then
  bad "the header still claims the script cannot exceed its budget"
else
  ok "the header no longer claims the script cannot exceed its budget"
fi

# --- the installed copy is pinned, and the command has to say so ---
# save-session.sh is copied into a project at install time so the hook does not
# depend on the plugin install path. That is deliberate, and it also means a fix
# shipped later never reaches an already-installed project until the command runs
# again. Nothing detects a stale copy — so the command has to name the upgrade case,
# not only the path-changed one.
IRH="$ROOT/commands/install-remembrance-hook.md"
if grep -q 'Re-run it after upgrading the plugin' "$IRH"; then
  ok "install-remembrance-hook says to re-run after a plugin upgrade, not only on a path change"
else
  bad "install-remembrance-hook says to re-run after a plugin upgrade, not only on a path change"
fi
if grep -q 'Nothing detects a stale copy' "$IRH"; then
  ok "the pinned copy is named as undetected rather than left implied"
else
  bad "the pinned copy is named as undetected rather than left implied"
fi

# --- the written primer is checked for placeholders the hand-substitution missed ---
if grep -q 'still has unfilled placeholder' "$IRH"; then
  ok "the written primer is checked for leftover placeholders"
else
  bad "the written primer is checked for leftover placeholders"
fi
if grep -q 'Do not report the install as done while that prints anything' "$IRH"; then
  ok "a half-filled primer blocks the done report"
else
  bad "a half-filled primer blocks the done report"
fi

# The check in the command must actually catch the template's placeholder shape.
TPL="$ROOT/templates/session-primer.md"
if [ -f "$TPL" ]; then
  FOUND="$(grep -oE '\{[a-z_]+\}' "$TPL" | sort -u | wc -l | tr -d ' ')"
  if [ "$FOUND" -ge 4 ]; then
    ok "the primer template's placeholders match the shape the check greps for ($FOUND found)"
  else
    bad "the primer template's placeholders match the shape the check greps for" "found=$FOUND"
  fi
else
  bad "templates/session-primer.md is missing"
fi

echo "----"
echo "save-session-stdin-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
