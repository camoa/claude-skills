#!/usr/bin/env bash
# removed-names-spec.sh: every name 6.1.0 removed is gone. Reads tests/removed-names.txt, one
# literal per line, or `<literal> | <path>` where one spec may hold it, and greps every file of
# the plugin for each, case as written. CHANGELOG.md keeps the history and the list names every
# entry, so neither is read. A hit prints as `<path>:<line>: <literal>`. The last line is
# `hits: <n>`; the exit is 1 on any hit.
# Usage: removed-names-spec.sh [<list file>]. bash 3.2+.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PLUGIN="$(dirname "$HERE")"
LIST="${1:-$HERE/removed-names.txt}"
[ -f "$LIST" ] || { printf 'no list at %s\n' "$LIST"; exit 1; }
HITS="$(mktemp)"; trap 'rm -f "$HITS"' EXIT
while IFS= read -r entry; do
  case "$entry" in ''|'#'*) continue ;; esac
  name="${entry%% | *}"; allowed=""
  [ "$name" = "$entry" ] || allowed="${entry#* | }"
  (cd "$PLUGIN" && grep -rnF --exclude=CHANGELOG.md -- "$name" .) \
    | while IFS= read -r hit; do
        path="${hit#./}"; path="${path%%:*}"
        [ "$PLUGIN/$path" -ef "$LIST" ] && continue
        [ "$path" = "$allowed" ] && continue
        line="${hit#./"$path":}"
        printf '%s:%s: %s\n' "$path" "${line%%:*}" "$name"
      done
done <"$LIST" >"$HITS"
cat "$HITS"
N="$(wc -l <"$HITS" | tr -d ' ')"
printf 'hits: %s\n' "$N"
[ "$N" -eq 0 ]
