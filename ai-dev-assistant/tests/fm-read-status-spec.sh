#!/usr/bin/env bash
# fm-read-status-spec.sh — a finished task and a never-started one read the same.
#
# fm_read returned the string "draft" in five places: four where the read had failed or the
# file carried no frontmatter, and once as the default for an absent key. The no-frontmatter
# path also returned `warnings: []`, so nothing in the object said a read had not happened.
# Observed on a task that had just passed review: `status: draft`, no warnings.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
K="$PLUGIN_ROOT/scripts/fm-read.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/plain"; printf '# Task\n\nno frontmatter here\n' > "$TMP/plain/task.md"
OUT=$(bash "$K" "$TMP/plain")
[ "$(printf '%s' "$OUT" | jq -r .status)" = "null" ] \
  && pass_check "a task with no frontmatter has an unknown status, not a draft one" \
  || fail_check "a finished task still reads as draft"
[ "$(printf '%s' "$OUT" | jq -r '.warnings|length')" -gt 0 ] \
  && pass_check "the absent frontmatter is warned about rather than passed over silently" \
  || fail_check "the one path that fabricated a status also reported no warnings"
[ "$(printf '%s' "$OUT" | jq -r .kind)" = "flat" ] \
  && pass_check "kind stays flat, which the file being read actually establishes" \
  || fail_check "kind stopped reporting the hierarchy the file does declare"

mkdir -p "$TMP/real"
printf -- '---\nid: local:x\nkind: flat\nstatus: in_progress\n---\n\n# Task\n' > "$TMP/real/task.md"
[ "$(bash "$K" "$TMP/real" | jq -r .status)" = "in_progress" ] \
  && pass_check "a recorded status is still read back" \
  || fail_check "a real status was lost"

OUT=$(bash "$K" "$TMP/nope")
[ "$(printf '%s' "$OUT" | jq -r .status)" = "null" ] && [ "$(printf '%s' "$OUT" | jq -r .kind)" = "null" ] \
  && pass_check "a folder that was never read reports neither a kind nor a status" \
  || fail_check "a failed read still returned a kind and a status it never saw"

# migrate-to-epic writes this value into a new epic's frontmatter. An unknown must not become
# a recorded one on the way through.
grep -q 'CURRENT_STATUS="in_progress"' "$PLUGIN_ROOT/scripts/migrate-to-epic.sh" \
  && pass_check "a null status is resolved before it is written into a real record" \
  || fail_check "migrate-to-epic would write the literal null into frontmatter"

printf '\n'
[ "$FAIL" -eq 0 ] && { printf 'fm-read-status-spec: all checks passed\n'; exit 0; }
printf 'fm-read-status-spec: FAILURES\n' >&2; exit 1
