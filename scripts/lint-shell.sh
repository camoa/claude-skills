#!/usr/bin/env bash
# Checks the repo's tracked shell scripts with shellcheck and holds the result
# against a committed baseline.
#
# Usage:
#   scripts/lint-shell.sh                    # check against the baseline
#   scripts/lint-shell.sh --update-baseline  # rewrite the baseline
#
# scripts/lint-baseline.txt lists the warnings this repo has not cleaned up
# yet, one "<path>:<CODE>" pair per line, sorted. A pair that is NOT in the
# baseline fails the build. A baseline pair that no longer occurs is reported
# as fixed and does not fail, so cleaning up a script never breaks CI.
#
# Its first line is "# shellcheck <version>", the version that produced it.
# A baseline is only meaningful against the shellcheck that generated it:
# versions add, remove and renumber checks, so a different build reports
# "new" warnings that are really just a version difference. This script
# compares the two and names both versions when they disagree, rather than
# leaving someone to work out why an untouched file suddenly fails.
#
# The key is file + code on purpose, never a line number. Keying on lines
# makes every unrelated edit shift the baseline, which trains people to
# regenerate it reflexively, and a baseline that is always regenerated stops
# being a ratchet.
#
# Known limit, stated rather than implied: a pair is recorded once per file,
# so a file going from one SC2086 to five does not fail. What this catches is
# a new code in a file, and a file that had no warnings acquiring one.
#
# Written for bash 3.2 so it behaves the same on macOS and CI.

set -uo pipefail

# comm and sort must agree byte-for-byte between a developer's macOS locale
# and CI's; otherwise the baseline compares as garbage.
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

BASELINE="scripts/lint-baseline.txt"

UPDATE=0
case "${1:-}" in
  "")                ;;
  --update-baseline) UPDATE=1 ;;
  *) printf 'usage: %s [--update-baseline]\n' "${0##*/}" >&2; exit 2 ;;
esac

if ! command -v shellcheck >/dev/null 2>&1; then
  if [ -n "${CI:-}" ]; then
    printf 'lint: FAILED, shellcheck is not installed and CI is set.\n' >&2
    printf 'lint: CI is expected to lint. Install shellcheck in the workflow\n' >&2
    printf 'lint: rather than let this step pass without checking anything.\n' >&2
    exit 1
  fi
  printf 'lint: SKIPPED, shellcheck is not installed and CI is not set.\n'
  printf 'lint: nothing was checked, so nothing passed. Install shellcheck\n'
  printf 'lint: (brew install shellcheck / apt-get install shellcheck) to run it.\n'
  exit 0
fi

# "version: 0.11.0" out of `shellcheck --version`. Not a pipeline: see the
# note on the here-string below.
SC_VERSION=""
while IFS= read -r _line; do
  case "$_line" in
    version:*)
      SC_VERSION="${_line#version:}"
      SC_VERSION="${SC_VERSION# }"
      break
      ;;
  esac
done <<< "$(shellcheck --version 2>/dev/null)"
[ -n "$SC_VERSION" ] || SC_VERSION="unknown"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IN_GIT=1
else
  IN_GIT=0
fi

# Mirrors discover() in scripts/run-tests.sh on purpose. Inside a git work
# tree the candidate list comes from `git ls-files`, so ignored and untracked
# paths are excluded by construction rather than by a prune list that drifts:
# .worktrees/ and .claude/worktrees/ hold entire stale copies of this repo,
# and a plain `find` lints those copies too (1239 files instead of 179).
# Outside a work tree (an extracted tarball) it falls back to `find` with the
# known noise directories pruned.
#
# Consequence worth knowing: a brand-new script is not linted until it is
# `git add`ed. On CI every file is tracked, so CI always sees all of them.
#
# Paths are NUL-separated so a name containing a newline survives discovery.
# `sort -z` is GNU-only, so nothing here pipes through sort.
discover() {
  if [ "$IN_GIT" -eq 1 ]; then
    git ls-files -z
  else
    find . \
      \( -path ./.git -o -path ./.claude -o -path ./.worktrees \) -prune -o \
      -type f -print0
  fi | while IFS= read -r -d '' p; do
    p="${p#./}"
    case "$p" in
      *.sh) ;;
      *) continue ;;
    esac
    # `git ls-files` still lists a tracked file deleted from the work tree,
    # which would be reported as an error and inflate the counts.
    # (A comment must not begin with the linter's own name: it is read as a
    # directive and becomes an SC1072/SC1073 parse error.)
    [ -f "$p" ] || continue
    printf '%s\0' "$p"
  done
}

LIST=$(mktemp); RAW=$(mktemp); ERR=$(mktemp)
CUR=$(mktemp); BSORT=$(mktemp); NEWF=$(mktemp); FIXEDF=$(mktemp)
trap 'rm -f "$LIST" "$RAW" "$ERR" "$CUR" "$BSORT" "$NEWF" "$FIXEDF"' EXIT

discover > "$LIST"

TOTAL=0
while IFS= read -r -d '' f; do
  [ -n "$f" ] || continue
  TOTAL=$((TOTAL + 1))
done < "$LIST"

if [ "$TOTAL" -eq 0 ]; then
  printf 'lint: FAILED, no shell scripts were found.\n' >&2
  printf 'lint: nothing was checked, so nothing passed.\n' >&2
  exit 1
fi

# One pass over every file. shellcheck's exit status is deliberately unused:
# it is non-zero whenever it reports anything at all, and "it reported
# something" is not the question the ratchet asks.
xargs -0 shellcheck --severity=warning --format=gcc < "$LIST" > "$RAW" 2> "$ERR"

# A shellcheck that failed to run writes to stderr and emits no diagnostics,
# which would otherwise be indistinguishable from a perfectly clean repo.
if [ -s "$ERR" ]; then
  printf 'lint: FAILED, shellcheck itself reported a problem:\n' >&2
  sed 's/^/  /' "$ERR" >&2
  exit 1
fi

# gcc format is "path:line:col: level: message [SCnnnn]". Reduce each
# diagnostic to "path:CODE" and drop duplicates.
sed -n 's/^\(.*\):[0-9][0-9]*:[0-9][0-9]*: [a-z]*: .*\[\(SC[0-9][0-9]*\)\]$/\1:\2/p' \
  "$RAW" | sort -u > "$CUR"

CUR_N=$(wc -l < "$CUR" | tr -d ' ')

if [ "$UPDATE" -eq 1 ]; then
  # The version header goes first, so the file records which shellcheck
  # produced it and a later run can tell whether it is comparable.
  {
    printf '# shellcheck %s\n' "$SC_VERSION"
    cat "$CUR"
  } > "$BASELINE"
  printf 'lint: baseline rewritten with shellcheck %s. %s scripts checked, %s pair(s) recorded in %s\n' \
    "$SC_VERSION" "$TOTAL" "$CUR_N" "$BASELINE"
  printf 'lint: review the diff before committing it.\n'
  exit 0
fi

if [ ! -f "$BASELINE" ]; then
  printf 'lint: FAILED, the baseline %s is missing.\n' "$BASELINE" >&2
  printf 'lint: create it deliberately with "make lint-baseline" and commit it.\n' >&2
  exit 1
fi

# The recorded version, read without a pipeline so the loop can `break` on
# the header without the upstream taking SIGPIPE under `pipefail`.
BASE_VERSION=""
while IFS= read -r _line; do
  case "$_line" in
    '# shellcheck '*) BASE_VERSION="${_line#\# shellcheck }"; break ;;
  esac
done < "$BASELINE"

# Mismatch handling, split on purpose:
#   CI     - hard failure. The workflow pins the version, so a disagreement
#            means the pin and the baseline have drifted apart. That is a
#            repo bug, and any verdict this run produced is meaningless.
#   local  - loud warning, then carry on. A contributor's shellcheck is not
#            the repo's business until it actually changes the result, and
#            blocking them on it would be a confusing failure for a reason
#            unrelated to their change. If it DOES change the result, the
#            new-warnings failure below names the mismatch as the suspect.
VERSION_MISMATCH=0
if [ -z "$BASE_VERSION" ]; then
  VERSION_MISMATCH=1
  printf 'lint: %s has no "# shellcheck <version>" header, so there is no way\n' "$BASELINE" >&2
  printf 'lint: to tell which shellcheck produced it. Regenerate it with\n' >&2
  printf 'lint: "make lint-baseline" and commit the result.\n' >&2
elif [ "$BASE_VERSION" != "$SC_VERSION" ]; then
  VERSION_MISMATCH=1
  printf 'lint: shellcheck version mismatch.\n' >&2
  printf 'lint:   running here: %s\n' "$SC_VERSION" >&2
  printf 'lint:   baseline was built with: %s (per the header in %s)\n' \
    "$BASE_VERSION" "$BASELINE" >&2
  printf 'lint: shellcheck versions add, remove and renumber checks, so these\n' >&2
  printf 'lint: two are not comparable. Either install %s, or regenerate the\n' "$BASE_VERSION" >&2
  printf 'lint: baseline with "make lint-baseline" and commit the diff.\n' >&2
fi

if [ "$VERSION_MISMATCH" -eq 1 ] && [ -n "${CI:-}" ]; then
  printf 'lint: FAILED, the pinned CI shellcheck and the baseline disagree.\n' >&2
  printf 'lint: .github/workflows/ci.yml pins the version; the baseline header\n' >&2
  printf 'lint: must match it. Fix them together.\n' >&2
  exit 1
fi

# The header is a comment, not a pair, so it must not reach the comparison.
sed '/^#/d' "$BASELINE" | sort -u > "$BSORT"
BASE_N=$(wc -l < "$BSORT" | tr -d ' ')

comm -23 "$CUR" "$BSORT" > "$NEWF"   # present now, not in the baseline
comm -13 "$CUR" "$BSORT" > "$FIXEDF" # in the baseline, gone now
NEW_N=$(wc -l < "$NEWF" | tr -d ' ')
FIXED_N=$(wc -l < "$FIXEDF" | tr -d ' ')

printf -- '----\n'
printf 'lint: %s scripts checked, %s warning pair(s) now, %s in the baseline\n' \
  "$TOTAL" "$CUR_N" "$BASE_N"

if [ "$FIXED_N" -gt 0 ]; then
  printf 'lint: %s baseline warning(s) no longer occur:\n' "$FIXED_N"
  sed 's/^/  fixed  /' "$FIXEDF"
  printf 'lint: run "make lint-baseline" to record that. Optional, never automatic.\n'
fi

if [ "$NEW_N" -gt 0 ]; then
  printf 'lint: %s warning(s) not in the baseline:\n' "$NEW_N" >&2
  while IFS= read -r pair; do
    [ -n "$pair" ] || continue
    path="${pair%:*}"
    code="${pair##*:}"
    printf '  NEW    %s\n' "$pair" >&2
    grep -F "$path:" "$RAW" | grep -F "[$code]" | sed 's/^/           /' >&2
  done < "$NEWF"
  if [ "$VERSION_MISMATCH" -eq 1 ]; then
    printf 'lint: NOTE, your shellcheck (%s) is not the one that built the\n' "$SC_VERSION" >&2
    printf 'lint: baseline (%s). That is the likely cause of the warnings above,\n' "$BASE_VERSION" >&2
    printf 'lint: not your change. Check against %s before acting on them.\n' "$BASE_VERSION" >&2
  fi
  printf 'lint: fix these. If they are genuinely acceptable, run\n' >&2
  printf 'lint: "make lint-baseline" and say why in the commit message.\n' >&2
  exit 1
fi

printf 'lint: no new warnings\n'
exit 0
