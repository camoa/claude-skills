#!/usr/bin/env bash
# task-rule-install-spec.sh — writing into a file the plugin does not own.
#
# The block goes into the user's own repository, where it lands in their diffs.
# Two properties matter more than the wording: a re-run must not append a second
# copy, and nothing outside the markers may ever be touched.

set -eu

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
K="${PLUGIN_ROOT}/scripts/task-rule-install.sh"
READER="${PLUGIN_ROOT}/scripts/project-state-read.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }
[ -x "$K" ] || { printf 'FAIL: %s not executable\n' "$K" >&2; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
REPO="$T/repo"; mkdir -p "$REPO"

# --- a dry check writes nothing ------------------------------------------------
OUT=$(bash "$K" --code-path "$REPO" --project demo --check)
[ "$(printf '%s' "$OUT" | jq -r .action)" = "write" ] \
  && pass_check "--check reports the write it would do" \
  || fail_check "--check must report the pending action"
[ ! -f "$REPO/CLAUDE.md" ] \
  && pass_check "--check creates no file" \
  || fail_check "--check must not write"

# --- install into a repo with an existing, hand-written CLAUDE.md --------------
printf '# House rules\n\n- never use tabs\n- BEM for custom classes\n' > "$REPO/CLAUDE.md"
BEFORE=$(wc -l < "$REPO/CLAUDE.md")
bash "$K" --code-path "$REPO" --project demo >/dev/null
grep -q 'never use tabs' "$REPO/CLAUDE.md" && grep -q 'BEM for custom classes' "$REPO/CLAUDE.md" \
  && pass_check "the user's existing rules survive the install" \
  || fail_check "installing must not disturb existing content"
grep -q 'ai-dev-assistant:scope' "$REPO/CLAUDE.md" \
  && pass_check "the installed block names the command that opens a task" \
  || fail_check "the block must name /scope"

# --- idempotency: the property that makes a refresh safe -----------------------
bash "$K" --code-path "$REPO" --project demo >/dev/null
bash "$K" --code-path "$REPO" --project demo >/dev/null
COPIES=$(grep -c 'ai-dev-assistant:task-rule:begin' "$REPO/CLAUDE.md")
[ "$COPIES" -eq 1 ] \
  && pass_check "three installs leave exactly one block" \
  || fail_check "re-running appended a second copy ($COPIES markers found)"
[ "$(printf '%s' "$(bash "$K" --code-path "$REPO" --project demo)" | jq -r .status)" = "refreshed" ] \
  && pass_check "a re-run reports refreshed, not installed" \
  || fail_check "a re-run must report refreshed"

# --- removal leaves the file as it was ----------------------------------------
bash "$K" --code-path "$REPO" --remove >/dev/null
AFTER=$(wc -l < "$REPO/CLAUDE.md")
grep -q 'never use tabs' "$REPO/CLAUDE.md" \
  && pass_check "removal keeps the user's own rules" \
  || fail_check "removal must not eat the user's content"
grep -q 'task-rule:begin' "$REPO/CLAUDE.md" \
  && fail_check "removal left the marker behind" \
  || pass_check "removal takes the whole block out"
[ "$AFTER" -eq "$BEFORE" ] \
  && pass_check "install then remove restores the original line count" \
  || fail_check "install+remove changed the file ($BEFORE -> $AFTER lines)"

# --- a missing code path is an error, never a write somewhere else -------------
[ "$(printf '%s' "$(bash "$K" --code-path "$T/nope" --check)" | jq -r .status)" = "error" ] \
  && pass_check "a non-existent code path is refused" \
  || fail_check "a non-existent code path must be refused"

# --- the three-state record ----------------------------------------------------
PROJ="$T/proj"; mkdir -p "$PROJ"
printf '# P\n' > "$PROJ/project_state.md"
[ "$(bash "$READER" "$PROJ" | jq -r '.taskRule')" = "null" ] \
  && pass_check "no line means nobody has been asked" \
  || fail_check "an absent Task Rule line must read as null"
printf '# P\n**Task Rule:** (none)\n' > "$PROJ/project_state.md"
[ "$(bash "$READER" "$PROJ" | jq -r '.taskRule.declined')" = "true" ] \
  && pass_check "a decline is recorded as a real answer" \
  || fail_check "(none) must read as declined"
printf '# P\n**Task Rule:** installed\n' > "$PROJ/project_state.md"
[ "$(bash "$READER" "$PROJ" | jq -r '.taskRule.declined')" = "false" ] \
  && pass_check "installed reads as answered and not declined" \
  || fail_check "installed must read as declined:false"
printf '# P\n**Task Rule:** sure ok\n' > "$PROJ/project_state.md"
OUT=$(bash "$READER" "$PROJ")
[ "$(printf '%s' "$OUT" | jq -r '.taskRule')" = "null" ] \
  && [ "$(printf '%s' "$OUT" | jq -r '[.warnings[].code] | index("task_rule_bad_value") // "none"')" != "none" ] \
  && pass_check "an unrecognised value warns rather than being coerced" \
  || fail_check "a bad Task Rule value must warn and read as unanswered"

if [ "$FAIL" -ne 0 ]; then
  printf '\nSome invariants FAILED for the task rule.\n' >&2
  exit 1
fi
printf '\nAll invariants pass for the task rule.\n'
exit 0
