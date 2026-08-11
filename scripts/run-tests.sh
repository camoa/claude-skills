#!/usr/bin/env bash
# Runs every test in the repo, or one plugin's tests.
#
# Usage:
#   scripts/run-tests.sh            # all plugins
#   scripts/run-tests.sh <plugin>   # one plugin folder name
#
# Test kinds discovered per plugin:
#   */tests/*.sh and *-spec.sh   run with bash
#   *-spec.mjs                   run with node
#   scripts/slides/tests/        run with pytest (skipped if pytest is absent)
#   infographic-generator/test.js run with node (skipped without node_modules)
#
# Exit code is 0 only when at least one test ran and every test that ran
# passed. A run that discovers nothing, or that skips everything, fails.
# Written for bash 3.2 so it behaves the same on macOS and CI.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

ONLY="${1:-}"

PASS=0
FAIL=0
SKIP=0
FAILED_LIST=""

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IN_GIT=1
else
  IN_GIT=0
fi

run_one() {
  label="$1"; shift
  # stdin comes from /dev/null: the caller's loop is reading the test queue
  # on stdin, and a test that reads stdin (cat, read, sort, ssh) would
  # otherwise swallow the rest of the queue and the runner would still
  # report success.
  out=$("$@" </dev/null 2>&1); rc=$?
  if [ "$rc" -eq 0 ]; then
    PASS=$((PASS + 1))
    printf '  ok    %s\n' "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_LIST="${FAILED_LIST}${label}"$'\n'
    printf '  FAIL  %s\n' "$label"
    printf '%s\n' "$out" | tail -15 | sed 's/^/          /'
  fi
}

want_plugin() {
  [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]
}

plugin_of() {
  p="${1#./}"
  printf '%s' "${p%%/*}"
}

# Emits the test files of one kind (bash|mjs), NUL-separated, filtered to the
# requested plugin.
#
# Inside a git work tree the candidate list comes from `git ls-files`, so
# untracked and ignored paths — nested worktrees, vendored copies, scratch
# dirs — are excluded by construction instead of by a prune list that drifts
# out of date. Outside one (an extracted tarball) it falls back to `find`
# with the known noise directories pruned; that fallback does not sort, while
# `git ls-files` is already sorted.
#
# Paths are NUL-separated so a name containing a newline survives. `sort -z`
# is GNU-only, so nothing here pipes through sort.
discover() {
  kind="$1"
  if [ "$IN_GIT" -eq 1 ]; then
    git ls-files -z
  else
    find . \
      \( -path ./.git -o -path ./.claude -o -path ./.worktrees \) -prune -o \
      -type f -print0
  fi | while IFS= read -r -d '' p; do
    p="${p#./}"
    case "$kind" in
      bash)
        case "./$p" in
          */tests/*.sh|*-spec.sh) ;;
          *) continue ;;
        esac
        ;;
      mjs)
        case "./$p" in
          *-spec.mjs) ;;
          *) continue ;;
        esac
        ;;
      *) continue ;;
    esac
    want_plugin "$(plugin_of "$p")" || continue
    printf '%s\0' "$p"
  done
}

LIST=$(mktemp); trap 'rm -f "$LIST"' EXIT

# ── bash specs ────────────────────────────────────────────────────────────────
discover bash > "$LIST"
while IFS= read -r -d '' t; do
  run_one "$t" bash "$t"
done < "$LIST"

# ── node specs ────────────────────────────────────────────────────────────────
if command -v node >/dev/null 2>&1; then
  discover mjs > "$LIST"
  while IFS= read -r -d '' t; do
    run_one "$t" node "$t"
  done < "$LIST"

  IG="brand-content-design/skills/infographic-generator"
  if want_plugin brand-content-design && [ -f "$IG/test.js" ]; then
    if [ -d "$IG/node_modules" ]; then
      run_one "$IG/test.js" node "$IG/test.js"
    else
      SKIP=$((SKIP + 1))
      printf '  skip  %s/test.js (run npm install in that folder)\n' "$IG"
    fi
  fi
else
  SKIP=$((SKIP + 1))
  printf '  skip  node tests (node is not installed)\n'
fi

# ── python tests ──────────────────────────────────────────────────────────────
SLIDES="brand-content-design/scripts/slides/tests"
if want_plugin brand-content-design && [ -d "$SLIDES" ]; then
  if command -v pytest >/dev/null 2>&1; then
    run_one "$SLIDES" pytest -q "$SLIDES"
  else
    SKIP=$((SKIP + 1))
    printf '  skip  %s (pytest is not installed)\n' "$SLIDES"
  fi
fi

# ── summary ───────────────────────────────────────────────────────────────────
printf -- '----\n'
if [ -n "$FAILED_LIST" ]; then
  printf 'failed:\n'
  printf '%s' "$FAILED_LIST" | sed 's/^/  /'
fi
printf 'tests: %s passed, %s failed, %s skipped\n' "$PASS" "$FAIL" "$SKIP"

RAN=$((PASS + FAIL))
if [ "$RAN" -eq 0 ]; then
  if [ -n "$ONLY" ]; then
    printf 'error: no tests ran for plugin "%s" (%s skipped). Nothing executed, so nothing passed.\n' \
      "$ONLY" "$SKIP" >&2
  else
    printf 'error: no tests ran (%s skipped). Nothing executed, so nothing passed.\n' "$SKIP" >&2
  fi
  exit 1
fi

[ "$FAIL" -eq 0 ]
