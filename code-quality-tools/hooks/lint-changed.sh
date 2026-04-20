#!/usr/bin/env bash
# lint-changed.sh — FileChanged hook handler for watch-mode linting.
#
# Invoked by the skill-scoped FileChanged hook in
# skills/code-quality-audit/SKILL.md frontmatter.
#
# Receives hook JSON on stdin (file_path, event, cwd, ...). Detects project
# type (Drupal via composer.json with drupal/core, Next.js via package.json)
# and runs the fast linter on a single file when possible, or on the whole
# project when a linter-config file changed.
#
# Silent on clean runs. Prints to stderr on findings. Always exits 0 (no
# decision control on FileChanged; output is shown to user only).
#
# Guarantees:
#   - Never aborts on malformed stdin (jq parse error, missing fields)
#   - Never lints a file outside cwd (refuses to pass host paths into ddev)
#   - Disable mid-session: export CLAUDE_CODE_QUALITY_WATCH=0

# Deliberately NOT using `set -e` — we tolerate linter non-zero exits and
# parser failures; each step handles its own error path.
set -uo pipefail

if [ "${CLAUDE_CODE_QUALITY_WATCH:-1}" = "0" ]; then
  exit 0
fi

INPUT=$(cat 2>/dev/null || true)

# Tolerate malformed JSON: jq on parse failure returns non-zero and prints to
# stderr; capture empty and move on. Same for sed fallback.
if command -v jq >/dev/null 2>&1; then
  FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.file_path // empty' 2>/dev/null || echo "")
  EVENT=$(printf '%s'     "$INPUT" | jq -r '.event // empty'     2>/dev/null || echo "")
  CWD=$(printf '%s'       "$INPUT" | jq -r '.cwd // empty'       2>/dev/null || echo "")
else
  FILE_PATH=$(printf '%s' "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  EVENT=$(printf     '%s' "$INPUT" | sed -n 's/.*"event"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'     | head -1)
  CWD=$(printf       '%s' "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'       | head -1)
fi

FILE_PATH="${FILE_PATH:-}"
EVENT="${EVENT:-}"
CWD="${CWD:-$PWD}"

[ -n "$FILE_PATH" ] || exit 0
[ "$EVENT" = "unlink" ] && exit 0   # nothing to lint on delete
cd "$CWD" 2>/dev/null || exit 0

# Security: refuse to lint a file outside cwd. Prevents host paths (e.g.
# /tmp/foo.php) from being passed into `ddev exec` where they won't exist,
# or into `npx eslint` from an unrelated project tree.
case "$FILE_PATH" in
  /*) # Absolute path — must be inside cwd
    case "$FILE_PATH" in
      "$CWD"/*) ;;
      *) exit 0 ;;
    esac
    ;;
esac

BASENAME=$(basename "$FILE_PATH")
EXT="${FILE_PATH##*.}"

# Detect project type. Drupal wins if both markers present and composer.json
# names drupal/core; otherwise Next.js if package.json exists.
PROJECT_TYPE=""
if [ -f composer.json ] && grep -q 'drupal/core' composer.json 2>/dev/null; then
  PROJECT_TYPE="drupal"
elif [ -f package.json ]; then
  PROJECT_TYPE="nextjs"
fi

[ -n "$PROJECT_TYPE" ] || exit 0

# Linter-config files trigger a project-wide lint; source files lint just
# themselves. The list here must stay aligned with SKILL.md frontmatter
# matcher — FileChanged won't fire for basenames not in the matcher.
CONFIG_TRIGGERED=0
case "$BASENAME" in
  composer.json|package.json| \
  phpstan.neon|phpstan.neon.dist|phpstan.dist.neon| \
  phpcs.xml|phpcs.xml.dist|.phpcs.xml| \
  psalm.xml|psalm.xml.dist| \
  eslint.config.js|eslint.config.mjs|eslint.config.cjs| \
  .eslintrc.js|.eslintrc.json|.eslintrc.yml|.eslintrc.yaml| \
  tsconfig.json)
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
