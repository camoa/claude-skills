#!/usr/bin/env bash
# lint-changed.sh — FileChanged hook handler for watch-mode linting.
#
# Invoked by the skill-scoped FileChanged hook in
# skills/code-quality-audit/SKILL.md frontmatter.
#
# Receives hook JSON on stdin (file_path, event, cwd, ...). Detects project
# type (Drupal via composer.json, Next.js via package.json) and runs the fast
# linter on a single file when possible, or on the whole project when a
# linter-config file changed.
#
# Silent on clean runs. Prints to stderr on findings. Always exits 0 (no
# decision control on FileChanged; output is shown to user only).
#
# Disable mid-session:
#   export CLAUDE_CODE_QUALITY_WATCH=0
# Re-enable:
#   unset CLAUDE_CODE_QUALITY_WATCH   # or set to anything other than "0"

set -euo pipefail

if [ "${CLAUDE_CODE_QUALITY_WATCH:-1}" = "0" ]; then
  exit 0
fi

# Read JSON input from stdin; tolerate missing jq by falling back to minimal parsing.
INPUT=$(cat || true)
if command -v jq >/dev/null 2>&1; then
  FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.file_path // empty')
  EVENT=$(printf '%s' "$INPUT" | jq -r '.event // empty')
  CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
else
  FILE_PATH=$(printf '%s' "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  EVENT=$(printf '%s' "$INPUT" | sed -n 's/.*"event"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  CWD=$(printf '%s' "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi

[ -n "$FILE_PATH" ] || exit 0
[ "$EVENT" = "unlink" ] && exit 0   # nothing to lint on delete
CWD="${CWD:-$PWD}"
cd "$CWD" || exit 0

BASENAME=$(basename "$FILE_PATH")
EXT="${FILE_PATH##*.}"

# Detect project type.
PROJECT_TYPE=""
if [ -f composer.json ] && grep -q 'drupal/core' composer.json 2>/dev/null; then
  PROJECT_TYPE="drupal"
elif [ -f package.json ]; then
  PROJECT_TYPE="nextjs"
fi

[ -n "$PROJECT_TYPE" ] || exit 0

# Linter-config files trigger a project-wide lint; source files lint just themselves.
CONFIG_TRIGGERED=0
case "$BASENAME" in
  composer.json|package.json|phpstan.neon|phpstan.neon.dist|phpcs.xml|phpcs.xml.dist|.phpcs.xml|psalm.xml|eslint.config.js|eslint.config.mjs|eslint.config.cjs|.eslintrc.json|.eslintrc.js|tsconfig.json)
    CONFIG_TRIGGERED=1
    ;;
esac

run_drupal() {
  local target="$1"
  if ! command -v ddev >/dev/null 2>&1; then
    return 0
  fi
  if [ "$CONFIG_TRIGGERED" = "1" ] || [ -z "$target" ]; then
    ddev exec vendor/bin/phpstan analyse --memory-limit=1G --no-progress 2>&1 | head -50 >&2 || true
  else
    case "$EXT" in
      php|module|inc|install|theme|profile)
        ddev exec vendor/bin/phpstan analyse --memory-limit=1G --no-progress "$target" 2>&1 | head -20 >&2 || true
        ;;
    esac
  fi
}

run_nextjs() {
  local target="$1"
  if ! command -v npx >/dev/null 2>&1; then
    return 0
  fi
  if [ "$CONFIG_TRIGGERED" = "1" ] || [ -z "$target" ]; then
    npx --no-install eslint . --max-warnings=0 --format=compact 2>&1 | tail -30 >&2 || true
  else
    case "$EXT" in
      ts|tsx|js|jsx|mjs|cjs)
        npx --no-install eslint "$target" --format=compact 2>&1 | tail -20 >&2 || true
        ;;
    esac
  fi
}

case "$PROJECT_TYPE" in
  drupal) run_drupal "$FILE_PATH" ;;
  nextjs) run_nextjs "$FILE_PATH" ;;
esac

exit 0
