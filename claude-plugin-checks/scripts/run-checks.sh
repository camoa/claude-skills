#!/usr/bin/env bash
# run-checks.sh — run every plugin check available on this machine.
#
# Our own checks are one program, `check.py`. This script exists for the ones
# that are separate processes and always will be: the first-party validator and
# plugin-dev's linters. Their output is passed through untouched — not filtered,
# not reworded, not graded. If one of them is wrong, its maintainers can fix it.
#
# Usage:  run-checks.sh [plugin-dir] [--strict]
#
# Exit:   0  every check ran and every one was clean
#         1  at least one check found something
#         2  the arguments were wrong
#         3  no check failed, but at least one could not look
#
# Zero means everything looked and everything was clean. A machine missing the
# claude CLI does not get a zero, because the first-party validator did not run,
# and reporting that as clean is the false all-clear this plugin exists against.
set -uo pipefail

DIR="${1:-.}"
case "$DIR" in --*) DIR="." ;; esac
STRICT=""
for a in "$@"; do [ "$a" = "--strict" ] && STRICT="--strict"; done

if [ ! -d "$DIR" ]; then
  echo "run-checks: not a directory: $DIR" >&2
  exit 2
fi
DIR="$(cd "$DIR" && pwd)"
HERE="$(dirname "$(readlink -f "$0")")"

FAILED=0; CLEAN=0; UNCHECKED=0
SUMMARY=""
note() { SUMMARY="${SUMMARY}${1}"$'\n'; }
banner() { printf '\n=== %s ===\n' "$1"; }

# One vocabulary for every check, ours and theirs. A check that could not look
# is counted apart from both pass and fail, everywhere.
record() { # name, rc
  case "$2" in
    0) CLEAN=$((CLEAN+1));     note "  PASS       $1" ;;
    3) UNCHECKED=$((UNCHECKED+1)); note "  UNCHECKED  $1  (it could not look; this is not a clean result)" ;;
    *) FAILED=$((FAILED+1));   note "  FAIL       $1  (exit $2)" ;;
  esac
}

# Collect files without mapfile, which is bash 4 only. A check silently
# vanishing on an older shell is the exact failure this plugin exists to catch.
collect() { # dir, path-fragment, extension  -> newline-separated on stdout
  find "$1" -type d \( -name .git -o -name node_modules \) -prune -o \
       -path "$2" -name "$3" -print 2>/dev/null | sort
}

echo "Checking plugin: $DIR"

# --- First-party -------------------------------------------------------------
banner "claude plugin validate"
if command -v claude >/dev/null 2>&1; then
  claude plugin validate "$DIR"
  record "claude plugin validate" $?
else
  echo "the claude CLI is not on PATH, so this did not run"
  record "claude plugin validate" 3
fi

# --- plugin-dev, resolved by glob rather than a written-down path ------------
PD="$(ls -d "$HOME"/.claude/plugins/cache/*/plugin-dev/*/ 2>/dev/null | tail -1)"

banner "plugin-dev: hook linter"
if [ -n "$PD" ] && [ -f "${PD}skills/hook-development/scripts/hook-linter.sh" ]; then
  HOOKS="$(collect "$DIR" '*/hooks/*' '*.sh')"
  if [ -z "$HOOKS" ]; then
    echo "no hook scripts in this plugin"
    record "plugin-dev hook linter" 0
  else
    rc=0
    while IFS= read -r h; do
      [ -n "$h" ] || continue
      bash "${PD}skills/hook-development/scripts/hook-linter.sh" "$h" || rc=1
    done <<< "$HOOKS"
    record "plugin-dev hook linter" "$rc"
  fi
else
  echo "plugin-dev is not installed, so this did not run"
  record "plugin-dev hook linter" 3
fi

banner "plugin-dev: agent validator"
echo "Note: it stops at the first finding, so a short report is not a clean file."
echo "It also reports a missing \`model\` or \`color\` as an error; both are optional."
echo "Re-run it after fixing what it names rather than reading this as a full list."
echo ""
if [ -n "$PD" ] && [ -f "${PD}skills/agent-development/scripts/validate-agent.sh" ]; then
  AGENTS="$(collect "$DIR" '*/agents/*' '*.md')"
  if [ -z "$AGENTS" ]; then
    echo "no agent files in this plugin"
    record "plugin-dev agent validator" 0
  else
    rc=0
    while IFS= read -r a; do
      [ -n "$a" ] || continue
      bash "${PD}skills/agent-development/scripts/validate-agent.sh" "$a" || rc=1
    done <<< "$AGENTS"
    record "plugin-dev agent validator" "$rc"
  fi
else
  echo "plugin-dev is not installed, so this did not run"
  record "plugin-dev agent validator" 3
fi

banner "not run, on purpose"
cat <<'TXT'
plugin-dev validate-hook-schema.sh  crashes on the standard hooks.json shape.
plugin-dev validate-settings.sh     reads a settings file, not a plugin.
superpowers                         ships no validator; there is nothing to call.
TXT

# --- Ours, one program -------------------------------------------------------
banner "claude-plugin-checks"
if command -v python3 >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  python3 "$HERE/check.py" "$DIR" $STRICT >/dev/null
  record "claude-plugin-checks" $?
else
  echo "python3 is not on PATH, so none of our checks ran"
  record "claude-plugin-checks" 3
fi

# --- Summary -----------------------------------------------------------------
printf '\n=== summary ===\n'
printf '%s' "$SUMMARY"
printf '\n%d clean, %d failed, %d could not look\n' "$CLEAN" "$FAILED" "$UNCHECKED"

if [ "$FAILED" -gt 0 ]; then exit 1; fi
if [ "$UNCHECKED" -gt 0 ]; then exit 3; fi
if [ "$CLEAN" -eq 0 ]; then exit 3; fi
exit 0
