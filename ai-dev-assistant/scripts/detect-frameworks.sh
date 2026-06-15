#!/usr/bin/env bash
# detect-frameworks.sh — auto-detect web frameworks used by a project.
#
# Usage: detect-frameworks.sh <codePath>
#
# Always emits a single-line JSON array of framework slug strings to stdout.
# Exit 0 regardless of input (defensive posture; mirrors project-state-read.sh).
#
# Detected frameworks (stable output order):
#   drupal            — composer.json require/require-dev contains drupal/core or drupal/core-recommended,
#                       OR <codePath>/{web,docroot}/core/lib/Drupal.php OR <codePath>/core/lib/Drupal.php exists.
#                       (web/ = composer-template default; docroot/ = Acquia/Pantheon topology.)
#   nextjs            — package.json .dependencies or .devDependencies contains a "next" key.
#   claude-code-plugins — <codePath>/.claude-plugin/ directory exists
#                         (a Claude Code plugin project: individual plugins carry
#                         .claude-plugin/plugin.json; marketplace repos carry
#                         .claude-plugin/marketplace.json — the directory is the signal).
#
# Missing / non-dir codePath ⇒ []. Missing $1 ⇒ [].
# Malformed JSON in composer.json / package.json ⇒ that signal is absent (no crash).
#
# No writes. No side effects.

set -uo pipefail

CODE_PATH="${1:-}"

# Defensive: no arg or non-directory → empty array + exit 0
if [ -z "$CODE_PATH" ] || [ ! -d "$CODE_PATH" ]; then
  echo "[]"
  exit 0
fi

DETECTED=()

# ============================================================
# DRUPAL detection
# ============================================================
DRUPAL_FOUND=false

COMPOSER_JSON="${CODE_PATH}/composer.json"
if [ -f "$COMPOSER_JSON" ]; then
  # jq key-presence check on .require and ."require-dev"; match literal keys only.
  # 2>/dev/null guards against malformed JSON — jq exits non-zero; || echo false
  DRUPAL_IN_REQUIRE=$(jq -r '
    ((.require // {}) | has("drupal/core") or has("drupal/core-recommended"))
  ' "$COMPOSER_JSON" 2>/dev/null || echo "false")

  DRUPAL_IN_REQUIRE_DEV=$(jq -r '
    ((.["require-dev"] // {}) | has("drupal/core") or has("drupal/core-recommended"))
  ' "$COMPOSER_JSON" 2>/dev/null || echo "false")

  if [ "$DRUPAL_IN_REQUIRE" = "true" ] || [ "$DRUPAL_IN_REQUIRE_DEV" = "true" ]; then
    DRUPAL_FOUND=true
  fi
fi

# Fallback: bare Drupal checkout without a standard composer.json require
if [ "$DRUPAL_FOUND" = "false" ]; then
  if [ -f "${CODE_PATH}/web/core/lib/Drupal.php" ] || \
     [ -f "${CODE_PATH}/docroot/core/lib/Drupal.php" ] || \
     [ -f "${CODE_PATH}/core/lib/Drupal.php" ]; then
    DRUPAL_FOUND=true
  fi
fi

[ "$DRUPAL_FOUND" = "true" ] && DETECTED+=("drupal")

# ============================================================
# NEXTJS detection
# ============================================================
NEXTJS_FOUND=false

PACKAGE_JSON="${CODE_PATH}/package.json"
if [ -f "$PACKAGE_JSON" ]; then
  NEXT_IN_DEPS=$(jq -r '
    ((.dependencies // {}) | has("next")) or
    ((.devDependencies // {}) | has("next"))
  ' "$PACKAGE_JSON" 2>/dev/null || echo "false")

  [ "$NEXT_IN_DEPS" = "true" ] && NEXTJS_FOUND=true
fi

[ "$NEXTJS_FOUND" = "true" ] && DETECTED+=("nextjs")

# ============================================================
# CLAUDE-CODE-PLUGINS detection
# ============================================================
CLAUDE_CODE_PLUGINS_FOUND=false

# .claude-plugin/ directory presence is the signal for a Claude Code plugin /
# marketplace project. Individual plugins carry plugin.json; marketplace repos
# carry marketplace.json — checking the directory covers both.
if [ -d "${CODE_PATH}/.claude-plugin" ]; then
  CLAUDE_CODE_PLUGINS_FOUND=true
fi

[ "$CLAUDE_CODE_PLUGINS_FOUND" = "true" ] && DETECTED+=("claude-code-plugins")

# ============================================================
# Emit stable-order JSON array (de-duplicated by detection order above)
# ============================================================
if [ "${#DETECTED[@]}" -eq 0 ]; then
  echo "[]"
else
  printf '%s\n' "${DETECTED[@]}" | jq -R -s -c 'split("\n") | map(select(length > 0))'
fi
