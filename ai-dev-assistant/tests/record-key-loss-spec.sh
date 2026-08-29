#!/usr/bin/env bash
# record-key-loss-spec.sh — a rewrite of a gate record cannot silently drop what the last write
# recorded, and the refusal can fail.
#
# THE DEFECT THIS DEFENDS AGAINST. Every write replaces the whole record. That suits one writer
# and not the way these records are produced: an orchestrator writes, an agent it dispatched
# writes, a later pass corrects one field. Each assembles a payload from what it knows, and a
# writer that never saw an earlier key omits it. The rename is atomic, so nothing is corrupt --
# the record is just quietly shorter, with no error and no diff.
#
# Three collisions on one record in a single session went undetected. They were caught because a
# person re-read the file after each write, and the remedy adopted was a convention: use one
# writer. That holds until someone forgets.
#
# The comparison is one-directional and top-level only. A key set grows or holds. Corrections to
# values and to nested contents are untouched, and a deliberate removal passes --allow-key-loss.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
W="${PLUGIN_ROOT}/scripts/gate-audit-write.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }
[ -f "$W" ] || { printf 'FAIL: %s missing\n' "$W" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { printf 'FAIL: jq required\n' >&2; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mktask() { mktemp -d "$T/task.XXXXXX"; }

# write <folder> <payload> [flag] -> sets RC and ERR
write() {
  d="$1"; pl="$2"; shift 2
  set +e
  ERR=$(bash "$W" "$d" pre-analysis "$pl" "$@" 2>&1 >/dev/null); RC=$?
  set -e
}
rc_is() { [ "$RC" = "$1" ] && pass_check "$2" || fail_check "$2 (rc=$RC, wanted $1)"; }
err_has() { printf '%s' "$ERR" | grep -qF -- "$1" && pass_check "$2" || fail_check "$2 (stderr lacked: $1)"; }
key_present() { jq -e --arg k "$1" '.gate_specific | has($k)' "$2/_pre-analysis.json" >/dev/null 2>&1 \
  && pass_check "$3" || fail_check "$3"; }

# The writer takes the BARE gate_specific content and wraps it in the envelope itself.
FULL='{"decision":"keep_flat","confidence":"high","code_read":true,"notes":"first pass"}'
SHORT='{"decision":"keep_flat","confidence":"high","code_read":true}'

d=$(mktask); write "$d" "$FULL"
rc_is 0 "the first write of a record succeeds"

write "$d" "$SHORT"
rc_is 2 "a second write that drops a key is refused"
err_has "REFUSED" "the refusal says so plainly"
err_has "notes" "the refusal names the key that would be lost"
err_has "merge your changes onto it" "the refusal says what to do instead"
key_present notes "$d" "the record on disk still has the key the refused write would have dropped"

write "$d" "$FULL"
rc_is 0 "rewriting the same key set succeeds"

GROWN='{"decision":"keep_flat","confidence":"high","code_read":true,"notes":"second pass","extra":1}'
write "$d" "$GROWN"
rc_is 0 "a write that adds a key succeeds"
key_present extra "$d" "the added key is on disk"

# A correction changes values and nested contents. That must not read as a loss.
NESTED_A='{"decision":"keep_flat","confidence":"high","code_read":true,"notes":"n","extra":1,"nested":{"a":1,"b":2}}'
NESTED_B='{"decision":"split","confidence":"low","code_read":false,"notes":"n","extra":1,"nested":{"a":9}}'
write "$d" "$NESTED_A"; rc_is 0 "a nested object can be added"
write "$d" "$NESTED_B"
rc_is 0 "changing values and shrinking a NESTED object is a correction, not a loss"

write "$d" "$SHORT" --allow-key-loss
rc_is 0 "a deliberate removal passes with --allow-key-loss"
err_has "deliberate" "the deliberate removal is still announced on stderr"

d2=$(mktask); write "$d2" "$SHORT" --allow-key-loss
rc_is 0 "the flag is harmless on a first write"

echo "----"
if [ "$FAIL" -eq 0 ]; then echo "record-key-loss-spec: all assertions passed"; else
  echo "record-key-loss-spec: FAILURES"; fi
exit "$FAIL"
