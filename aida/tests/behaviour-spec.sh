#!/usr/bin/env bash
# Runs the behaviour fixtures in tests/behaviour, JOBS at a time (default 4), and fails when one
# fails. Each fixture gets an empty HOME, no system git config and a fixed git identity, so a run
# reads nothing from the machine it runs on. Prints each fixture's result and seconds, and the
# BAD lines of a failure. Arguments, when given, name the fixtures to run.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

# --one <log folder> <fixture>: runs one fixture with a HOME of its own, and writes its log and
# "<exit code> <seconds>". xargs calls this, so the parallel run needs no bash 4 job control.
if [ "${1:-}" = "--one" ]; then
  name="$(basename "$3" .sh)"
  fixture="$(cd "$(dirname "$3")" && pwd)/$name.sh"
  home="$(mktemp -d)" || exit 1
  start="$(date +%s)"
  (cd "$home" && HOME="$home" bash "$fixture") >"$2/$name.log" 2>&1 </dev/null
  printf '%s %s\n' "$?" "$(($(date +%s) - start))" >"$2/$name.rc"
  rm -rf "$home"
  exit 0
fi

PLUGIN="$(cd "$HERE/.." && pwd)"
OUT="$(mktemp -d)" || exit 1
trap 'rm -rf "$OUT"' EXIT
export PLUGIN GIT_CONFIG_NOSYSTEM=1 RUNS=1
export GIT_AUTHOR_NAME=aida-ci GIT_AUTHOR_EMAIL=aida-ci@example.invalid
export GIT_COMMITTER_NAME=aida-ci GIT_COMMITTER_EMAIL=aida-ci@example.invalid
unset AIDA_SESSION_PLUGIN_VERSION AIDA_SESSION_CHECKED CLAUDE_PLUGIN_ROOT

# The slowest fixtures start first, so the last job ends near the total over JOBS. The order
# is from measured runs; a fixture not named here runs after these.
SLOWEST="im-light-mode eh-whole-chain db-restart kg-implement-dispatch mm-records-hash
  gj-hook-frozen-tests kh-hook-prior-source ks-snapshot-drift mk-review-tool-rows es-design-close"
if [ "$#" -gt 0 ]; then
  FIXTURES=("$@")
else
  FIXTURES=()
  for n in $SLOWEST; do [ -f "$HERE/behaviour/$n.sh" ] && FIXTURES+=("$HERE/behaviour/$n.sh"); done
  for f in "$HERE"/behaviour/*.sh; do
    case " $(printf '%s ' $SLOWEST)" in *" $(basename "$f" .sh) "*) ;; *) FIXTURES+=("$f") ;; esac
  done
fi
start="$(date +%s)"
printf '%s\n' "${FIXTURES[@]}" | xargs -P "${JOBS:-4}" -I{} bash "$0" --one "$OUT" {}

failed=0
summary=""
for f in "${FIXTURES[@]}"; do
  name="$(basename "$f" .sh)"
  read -r rc secs <"$OUT/$name.rc" 2>/dev/null || { rc=1; secs='?'; }
  last="$(tail -1 "$OUT/$name.log" 2>/dev/null)"
  if [ "$rc" -eq 0 ]; then
    printf 'ok    %-32s %4ss  %s\n' "$name" "$secs" "$last"
  else
    failed=$((failed + 1))
    printf 'FAIL  %-32s %4ss  %s\n' "$name" "$secs" "$last"
    if grep -q '^BAD' "$OUT/$name.log" 2>/dev/null; then
      grep -A2 '^BAD' "$OUT/$name.log"
    else
      tail -10 "$OUT/$name.log" 2>/dev/null
    fi | sed 's/^/        /'
    summary="$summary$name: $(grep -c '^BAD' "$OUT/$name.log" 2>/dev/null) BAD"$'\n'
    summary="$summary$(grep '^BAD' "$OUT/$name.log" 2>/dev/null | sed 's/^/  /')"$'\n'
  fi
done
# run-tests.sh shows the last lines of a failed spec, so the BAD lines of every failure end it.
[ -z "$summary" ] || printf 'failed fixtures:\n%s' "$summary" | sed '/^$/d'
printf 'fixtures: %s run, %s failed, %ss wall\n' "${#FIXTURES[@]}" "$failed" "$(($(date +%s) - start))"
[ "$failed" -eq 0 ]
