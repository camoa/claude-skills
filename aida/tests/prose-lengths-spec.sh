#!/usr/bin/env bash
# prose-lengths-spec.sh: every skill body, reference and agent is read into the window when it is
# invoked, and nothing else holds their length. Reads tests/prose-lengths.txt, `<path> <lines>` per
# file, and fails naming each file that grew past its record, with both numbers. Growth is a
# deliberate edit of that record in the same commit. Shrinking passes. A file with no record fails,
# so a new reference never escapes. A record with no file fails, so a stale line never hides one.
# Usage: prose-lengths-spec.sh [<record file>]. bash 3.2+ and zsh.
# The whole set runs from the marketplace repository root, camoa-skills/scripts/run-tests.sh, not
# from the plugin's own scripts/. It finds a spec through git ls-files, so an untracked spec
# never runs.
set -uo pipefail
if [ -n "${ZSH_VERSION:-}" ]; then SCRIPT_SOURCE="$0"; else SCRIPT_SOURCE="${BASH_SOURCE[0]}"; fi
HERE="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd)"
PLUGIN="$(dirname "$HERE")"
RECORD="${1:-$HERE/prose-lengths.txt}"
[ -f "$RECORD" ] || { printf 'no record at %s\n' "$RECORD"; exit 1; }
FAIL=0
while read -r p n; do
  case "$p" in ''|'#'*) continue ;; esac
  if [ ! -f "$PLUGIN/$p" ]; then printf 'recorded, not found: %s\n' "$p"; FAIL=1; continue; fi
  now="$(wc -l <"$PLUGIN/$p" | tr -d ' ')"
  [ "$now" -le "$n" ] || { printf 'grew: %s recorded %s now %s\n' "$p" "$n" "$now"; FAIL=1; }
done <"$RECORD"
UNRECORDED="$(mktemp)"; trap 'rm -f "$UNRECORDED"' EXIT
(cd "$PLUGIN" && find agents skills -name '*.md' | grep -E '^agents/[^/]+\.md$|/SKILL\.md$|/references/[^/]+\.md$' | sort) \
  | while IFS= read -r p; do
      grep -q "^$p " "$RECORD" || printf 'not recorded: %s\n' "$p"
    done >"$UNRECORDED"
if [ -s "$UNRECORDED" ]; then cat "$UNRECORDED"; FAIL=1; fi
exit "$FAIL"
