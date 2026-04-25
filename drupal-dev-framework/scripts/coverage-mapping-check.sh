#!/usr/bin/env bash
# coverage-mapping-check.sh — verify research.md has the required Coverage Mapping section.
#
# Usage: coverage-mapping-check.sh <task_folder>
#
# Always emits single JSON object to stdout. Exit 0 for all recoverable states.
# Non-zero ONLY for bash-level read failures.
#
# Output (per references/gate-audit-schema.md §5.2 gate_specific shape):
#   {
#     "verdict": "pass | fail",
#     "research_questions_found": <int>,
#     "research_questions_addressed": <int>,
#     "missing_questions": ["<question text>", ...],
#     "warnings": []
#   }
#
# Logic:
#   1. research.md must exist
#   2. research.md must contain a `## Coverage Mapping` H2 (synonyms accepted:
#      `## Coverage Mapping`, `## Coverage`, `## Coverage Map`)
#   3. Section must have ≥3 content lines below the heading
#   4. Each Research Question from task.md (extracted from `## Research Questions`
#      bullets) must have a corresponding row in the Coverage Mapping section
#      (matched by case-insensitive substring of the question text against the row)
#
# verdict: pass requires all 4 conditions; fail otherwise.

set -uo pipefail

TASK_FOLDER="${1:?task folder required}"
RESEARCH_MD="$TASK_FOLDER/research.md"
TASK_MD="$TASK_FOLDER/task.md"

emit() {
  jq -nc \
    --arg v "$1" \
    --argjson found "$2" \
    --argjson addressed "$3" \
    --argjson missing "$4" \
    --argjson warnings "${5:-[]}" '
    {
      verdict: $v,
      research_questions_found: $found,
      research_questions_addressed: $addressed,
      missing_questions: $missing,
      warnings: $warnings
    }'
}

if [[ ! -f "$RESEARCH_MD" ]]; then
  emit "fail" 0 0 '[]' '[{"code":"research_md_missing","detail":"research.md not found"}]'
  exit 0
fi

# Find a Coverage Mapping H2 heading (synonyms accepted)
COVERAGE_LINE=$(awk '
  BEGIN { IGNORECASE = 1 }
  /^## ([0-9]+\.?[[:space:]]+)?(Coverage Mapping|Coverage Map|Coverage)([[:space:]]|\.|$)/ {
    print NR
    exit
  }
' "$RESEARCH_MD")

if [[ -z "$COVERAGE_LINE" ]]; then
  emit "fail" 0 0 '[]' '[{"code":"coverage_section_missing","detail":"## Coverage Mapping (or Coverage / Coverage Map) H2 not found in research.md"}]'
  exit 0
fi

# Count content lines below the heading until next H2
CONTENT_LINES=$(awk -v start="$COVERAGE_LINE" '
  NR > start {
    if (/^## /) exit
    if (NF > 0) count++
  }
  END { print count + 0 }
' "$RESEARCH_MD")

if [[ "$CONTENT_LINES" -lt 3 ]]; then
  emit "fail" 0 0 '[]' "[{\"code\":\"coverage_section_thin\",\"detail\":\"## Coverage Mapping has fewer than 3 content lines (found $CONTENT_LINES)\"}]"
  exit 0
fi

# Extract Research Questions from task.md if present
QUESTIONS_FOUND=0
QUESTIONS_ADDRESSED=0
MISSING_JSON='[]'

if [[ -f "$TASK_MD" ]]; then
  # Extract bullets under ## Research Questions (case-insensitive)
  QUESTIONS=$(awk '
    BEGIN { in_block = 0; IGNORECASE = 1 }
    /^## Research Questions/ { in_block = 1; next }
    in_block && /^## / { in_block = 0 }
    in_block && /^- / {
      line = $0
      sub(/^- */, "", line)
      print line
    }
  ' "$TASK_MD")

  if [[ -n "$QUESTIONS" ]]; then
    # Extract Coverage Mapping section content
    COVERAGE_BODY=$(awk -v start="$COVERAGE_LINE" '
      NR > start {
        if (/^## /) exit
        print
      }
    ' "$RESEARCH_MD")

    # For each question, check if a substring of it appears in coverage body
    MISSING_ARR=()
    while IFS= read -r q; do
      [[ -z "$q" ]] && continue
      QUESTIONS_FOUND=$((QUESTIONS_FOUND + 1))
      # Use first 30 chars of the question as the substring (lowercase compare)
      SUBSTR=$(echo "$q" | head -c 30 | tr '[:upper:]' '[:lower:]')
      if echo "$COVERAGE_BODY" | tr '[:upper:]' '[:lower:]' | grep -qF "$SUBSTR"; then
        QUESTIONS_ADDRESSED=$((QUESTIONS_ADDRESSED + 1))
      else
        MISSING_ARR+=("$q")
      fi
    done <<< "$QUESTIONS"

    if [[ "${#MISSING_ARR[@]}" -gt 0 ]]; then
      MISSING_JSON=$(printf '%s\n' "${MISSING_ARR[@]}" | jq -R . | jq -s -c .)
    fi
  fi
fi

# Verdict
if [[ "$QUESTIONS_FOUND" -eq 0 ]]; then
  # No declared questions — section presence is enough
  emit "pass" 0 0 '[]' '[]'
elif [[ "$QUESTIONS_ADDRESSED" -lt "$QUESTIONS_FOUND" ]]; then
  emit "fail" "$QUESTIONS_FOUND" "$QUESTIONS_ADDRESSED" "$MISSING_JSON" '[]'
else
  emit "pass" "$QUESTIONS_FOUND" "$QUESTIONS_ADDRESSED" '[]' '[]'
fi
