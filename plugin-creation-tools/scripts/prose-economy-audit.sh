#!/usr/bin/env bash
# prose-economy-audit.sh — reports SKILL.md body line/word counts vs. the
# existing S10/S11 caps from commands/validate.md, sorted worst-first.
#
# /plugin-creation-tools:validate already flags an individual SKILL.md when it
# crosses the S10/S11 line-count thresholds — but only for the file(s) it's
# pointed at, and only as pass/fail findings mixed into a larger report. This
# script is a THIN, focused reporter: it walks every SKILL.md under a
# directory, reuses the same three thresholds validate already enforces, and
# prints one sorted table so an author (or a sweep across many plugins) can
# see the worst offenders at a glance. It does NOT reimplement or replace
# validate — run `/plugin-creation-tools:validate <plugin>` for the full gate.
#
# Thresholds (kept in sync with commands/validate.md S10/S11 — see this
# plugin's CONTRIBUTING.md "Drift to Watch"):
#   FAIL  >= 500 lines  (S10 error — hard ceiling)
#   WARN  >= 250 lines  (S10 warn  — extraction nudge)
#   INFO  > 150 lines   (S11 info  — conciseness nudge for frequently-loaded skills)
#   PASS  <= 150 lines
#
# Usage:  prose-economy-audit.sh <dir> [--warn-lines N] [--error-lines N] [--info-lines N]
#   <dir>            A plugin root, a skills/ folder, or any directory —
#                     every SKILL.md found recursively beneath it is audited.
#   --warn-lines N   Override the S10 warn threshold (default 250).
#   --error-lines N  Override the S10 error threshold (default 500).
#   --info-lines N   Override the S11 info threshold (default 150).
#
# Output: a plain-text table on stdout, worst offender first, plus a summary
# line. Exit: 1 if any file is FAIL, 0 otherwise, 2 on usage error.
set -uo pipefail

DIR="${1:-}"
shift || true

WARN_LINES=250
ERROR_LINES=500
INFO_LINES=150

while [ $# -gt 0 ]; do
  case "$1" in
    --warn-lines) WARN_LINES="$2"; shift 2 ;;
    --error-lines) ERROR_LINES="$2"; shift 2 ;;
    --info-lines) INFO_LINES="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -z "$DIR" ] || [ ! -d "$DIR" ]; then
  echo "usage: prose-economy-audit.sh <dir> [--warn-lines N] [--error-lines N] [--info-lines N]" >&2
  echo "error: directory not found: ${DIR:-<none>}" >&2
  exit 2
fi

# Extract only the body (post-frontmatter) of a SKILL.md: skip a leading
# `---` ... `---` block; if the file has no frontmatter, treat it all as body.
body_of() {
  awk '
    BEGIN { state = 0 }
    {
      if (state == 0) {
        if (NR == 1 && $0 == "---") { state = 1; next }
        else { state = 2 }
      } else if (state == 1) {
        if ($0 == "---") { state = 2; next }
        else next
      }
      if (state == 2) print
    }
  ' "$1"
}

ROWS=""
FAIL_COUNT=0
WARN_COUNT=0
INFO_COUNT=0
PASS_COUNT=0
TOTAL=0

while IFS= read -r -d '' file; do
  TOTAL=$((TOTAL + 1))
  body="$(body_of "$file")"
  lines="$(printf '%s\n' "$body" | grep -c '' || true)"
  # grep -c '' on an empty string still reports 1 (counts the trailing empty
  # line); normalize a truly empty body to 0.
  [ -z "$body" ] && lines=0
  words="$(printf '%s' "$body" | wc -w | tr -d ' ')"

  if [ "$lines" -ge "$ERROR_LINES" ]; then
    status="FAIL"; rank=0; FAIL_COUNT=$((FAIL_COUNT + 1))
  elif [ "$lines" -ge "$WARN_LINES" ]; then
    status="WARN"; rank=1; WARN_COUNT=$((WARN_COUNT + 1))
  elif [ "$lines" -gt "$INFO_LINES" ]; then
    status="INFO"; rank=2; INFO_COUNT=$((INFO_COUNT + 1))
  else
    status="PASS"; rank=3; PASS_COUNT=$((PASS_COUNT + 1))
  fi

  relpath="${file#"$DIR"/}"
  ROWS="${ROWS}${rank}"$'\t'"${status}"$'\t'"${lines}"$'\t'"${words}"$'\t'"${relpath}"$'\n'
done < <(find "$DIR" -name 'SKILL.md' -print0 2>/dev/null)

if [ "$TOTAL" -eq 0 ]; then
  echo "No SKILL.md files found under: $DIR" >&2
  exit 0
fi

printf '%s\n' "Prose-economy audit: $DIR"
printf '%s\n' "Caps (S10/S11): FAIL >= ${ERROR_LINES} lines, WARN >= ${WARN_LINES} lines, INFO > ${INFO_LINES} lines"
printf '%s\n' ""
printf '%-6s %6s %6s  %s\n' "STATUS" "LINES" "WORDS" "SKILL.md"
printf '%-6s %6s %6s  %s\n' "------" "-----" "-----" "--------"

printf '%s' "$ROWS" | sort -t $'\t' -k1,1n -k3,3nr | while IFS=$'\t' read -r _ status lines words relpath; do
  [ -z "$relpath" ] && continue
  printf '%-6s %6s %6s  %s\n' "$status" "$lines" "$words" "$relpath"
done

printf '%s\n' ""
printf 'Total: %d skills — %d FAIL, %d WARN, %d INFO, %d PASS\n' \
  "$TOTAL" "$FAIL_COUNT" "$WARN_COUNT" "$INFO_COUNT" "$PASS_COUNT"

[ "$FAIL_COUNT" -gt 0 ] && exit 1
exit 0
