#!/usr/bin/env bash
# dev-guides-detect.sh — deterministic auto-load keyword detection.
#
# Usage: dev-guides-detect.sh <task_folder>
#
# Replaces agent-mediated keyword detection in guide-integrator with a
# deterministic shell scan. The auto-load keyword table mirrors
# skills/guide-integrator/SKILL.md §"Auto-Load Rules" verbatim.
#
# Output (per references/gate-audit-schema.md §5.6 gate_specific shape):
#   {
#     "keywords_matched": ["gate", "complete", "quality"],
#     "guides_to_load": ["plugin:quality-gates"],
#     "scanned_files": [".../task.md", ".../research.md"],
#     "warnings": []
#   }
#
# Scanned content: task.md + research.md (if present) + alignment.md (if present) +
# architecture.md (if present) + implementation.md (if present).
# All converted to lowercase for case-insensitive matching.

set -uo pipefail

TASK_FOLDER="${1:?task folder required}"

# Build scanned content set
SCANNED_FILES=()
SCANNED_CONTENT=""
for f in task.md alignment.md research.md architecture.md implementation.md; do
  PATH_F="$TASK_FOLDER/$f"
  if [[ -f "$PATH_F" ]]; then
    SCANNED_FILES+=("$PATH_F")
    SCANNED_CONTENT+=$'\n'"$(cat "$PATH_F")"
  fi
done

if [[ -z "$SCANNED_CONTENT" ]]; then
  jq -nc '{
    keywords_matched: [],
    guides_to_load: [],
    scanned_files: [],
    warnings: [{code: "no_artifacts", detail: "task folder has no markdown artifacts to scan"}]
  }'
  exit 0
fi

# Lowercase for matching
LC_CONTENT=$(echo "$SCANNED_CONTENT" | tr '[:upper:]' '[:lower:]')

# Auto-load rules (mirrors skills/guide-integrator/SKILL.md verbatim).
# Each row: keywords (regex-alternation) | guide ID
# Format below: regex pattern + guide ID, separated by literal "::"
declare -a RULES=(
  "test|tdd|unit test|kernel test::plugin:tdd-workflow"
  "service|dependency|inject|solid::plugin:solid-drupal"
  "duplicate|reuse|dry|extract::plugin:dry-patterns"
  "form|drush|command|service first::plugin:library-first"
  "complete|done|quality|gate::plugin:quality-gates"
)

KEYWORDS_MATCHED=()
GUIDES_TO_LOAD=()

for rule in "${RULES[@]}"; do
  PATTERN="${rule%%::*}"
  GUIDE_ID="${rule##*::}"

  # Check if any keyword in the pattern matches in scanned content
  MATCHED_KEYWORDS=$(echo "$LC_CONTENT" | grep -oE "\\b($PATTERN)\\b" | sort -u | head -10)

  if [[ -n "$MATCHED_KEYWORDS" ]]; then
    GUIDES_TO_LOAD+=("$GUIDE_ID")
    while IFS= read -r kw; do
      [[ -n "$kw" ]] && KEYWORDS_MATCHED+=("$kw")
    done <<< "$MATCHED_KEYWORDS"
  fi
done

# Dedupe keywords
if [[ "${#KEYWORDS_MATCHED[@]}" -gt 0 ]]; then
  KEYWORDS_JSON=$(printf '%s\n' "${KEYWORDS_MATCHED[@]}" | sort -u | jq -R . | jq -s -c .)
else
  KEYWORDS_JSON='[]'
fi

if [[ "${#GUIDES_TO_LOAD[@]}" -gt 0 ]]; then
  GUIDES_JSON=$(printf '%s\n' "${GUIDES_TO_LOAD[@]}" | sort -u | jq -R . | jq -s -c .)
else
  GUIDES_JSON='[]'
fi

FILES_JSON=$(printf '%s\n' "${SCANNED_FILES[@]}" | jq -R . | jq -s -c .)

jq -nc \
  --argjson keywords "$KEYWORDS_JSON" \
  --argjson guides "$GUIDES_JSON" \
  --argjson files "$FILES_JSON" '
  {
    keywords_matched: $keywords,
    guides_to_load: $guides,
    scanned_files: $files,
    warnings: []
  }'
