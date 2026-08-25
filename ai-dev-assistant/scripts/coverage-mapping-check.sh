#!/usr/bin/env bash
# coverage-mapping-check.sh — verify research.md has the required Coverage Mapping section.
#
# Usage: coverage-mapping-check.sh <task_folder>
#
# Always emits single JSON object to stdout. Exit 0 for all recoverable states.
# Non-zero ONLY for bash-level read failures.
#
# Output (per references/gate-audit-schema.md gate_specific shape):
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
#   4. Each Research Question from task.md (extracted from the `## Research
#      Questions` section — ordered `1.`/`2.` items, or `-`/`*`/`+` bullets;
#      the marker prefix is stripped) must have a corresponding row in the
#      Coverage Mapping section (matched by case-insensitive substring of the
#      question text against the row)
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
  # Extract list items under ## Research Questions (case-insensitive).
  # Tolerant reader: accepts ordered (1. / 2) ) and bulleted (- / * / +) markers;
  # an optional numeric section prefix on the heading is allowed too. The
  # marker prefix is stripped before the question text is emitted.
  QUESTIONS=$(awk '
    BEGIN { in_block = 0; IGNORECASE = 1 }
    /^## ([0-9]+\.?[[:space:]]+)?Research Questions([[:space:]]|$)/ { in_block = 1; next }
    in_block && /^## / { in_block = 0 }
    in_block && /^([0-9]+[.)]|[-*+])[[:space:]]/ {
      line = $0
      sub(/^([0-9]+[.)]|[-*+])[[:space:]]+/, "", line)
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

    # A question counts as addressed if the row names it either way:
    #
    #   verbatim  — the question's first 30 characters appear in the body
    #   by number — a row label of Q<n>, matching the numbered list in task.md
    #
    # Only the first form existed before v5.30.0, and it was never written down. A run
    # whose research was complete — six subjects, every question answered — got back
    # `fail, 1 of 6 addressed` because its rows abbreviated the questions. The verdict
    # said coverage; what it measured was string formatting. The run inferred the rule
    # from the failure and pasted the full question text into every row, which made the
    # gate pass and the table harder to read. Numbered rows are what the walkthrough's own
    # example uses, and task.md numbers the questions, so the number is a real reference.
    COVERAGE_LC=$(echo "$COVERAGE_BODY" | tr '[:upper:]' '[:lower:]')
    MISSING_ARR=()
    QN=0
    while IFS= read -r q; do
      [[ -z "$q" ]] && continue
      QUESTIONS_FOUND=$((QUESTIONS_FOUND + 1))
      QN=$((QN + 1))
      SUBSTR=$(echo "$q" | head -c 30 | tr '[:upper:]' '[:lower:]')
      # Anchored so "q1" cannot be matched by "q12", and so a bare mention of Q1 in
      # prose does not count — it has to label a row.
      if echo "$COVERAGE_LC" | grep -qF "$SUBSTR" \
         || echo "$COVERAGE_LC" | grep -qE "(^|\|)[[:space:]]*q${QN}([^0-9]|$)"; then
        QUESTIONS_ADDRESSED=$((QUESTIONS_ADDRESSED + 1))
      else
        MISSING_ARR+=("$q")
      fi
    done <<< "$QUESTIONS"

    if [[ "${#MISSING_ARR[@]}" -gt 0 ]]; then
      MISSING_JSON=$(printf '%s\n' "${MISSING_ARR[@]}" | jq -R . | jq -s -c .)
      # Say what a row has to look like. A verdict a reader cannot act on sends them
      # guessing at the matcher, which is how the last failure got "fixed" by pasting
      # whole questions into every row.
      FORMAT_WARN=$(jq -nc '[{code:"coverage_row_format", detail:"A Coverage Mapping row must name its question either verbatim (its first 30 characters) or by number (a row starting Q<n>, matching the numbered list under task.md ## Research Questions). A row that paraphrases matches neither. This is a formatting requirement, not a judgement about whether the research answered the question."}]')
    fi
  fi
fi

# Verdict
if [[ "$QUESTIONS_FOUND" -eq 0 ]]; then
  # No declared questions — section presence is enough
  emit "pass" 0 0 '[]' '[]'
elif [[ "$QUESTIONS_ADDRESSED" -lt "$QUESTIONS_FOUND" ]]; then
  emit "fail" "$QUESTIONS_FOUND" "$QUESTIONS_ADDRESSED" "$MISSING_JSON" "${FORMAT_WARN:-[]}"
else
  emit "pass" "$QUESTIONS_FOUND" "$QUESTIONS_ADDRESSED" '[]' '[]'
fi
