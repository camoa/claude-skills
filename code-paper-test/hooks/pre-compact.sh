#!/usr/bin/env bash
# Pre-compact hook: Instruct Claude to read test reports instead of dumping content

# Find .reports directory for test team results
REPORTS_DIR=".reports"
if [ ! -d "$REPORTS_DIR" ]; then
  REPORTS_DIR=$(find . -maxdepth 2 -type d -name ".reports" 2>/dev/null | head -1)
fi

if [ -z "$REPORTS_DIR" ] || [ ! -d "$REPORTS_DIR" ]; then
  exit 0
fi

# Check if any test team reports exist (markdown or JSON)
REPORTS=(
  happy-path-analysis.md happy-path-analysis.json
  edge-case-analysis.md edge-case-analysis.json
  red-team-analysis.md red-team-analysis.json
  paper-test-team-report.md paper-test-team-report.json
)

FOUND=false
for report in "${REPORTS[@]}"; do
  if [ -f "$REPORTS_DIR/$report" ]; then
    FOUND=true
    break
  fi
done

if [ "$FOUND" = false ]; then
  exit 0
fi

echo "## Pre-Compaction Context (code-paper-test)"
echo ""
echo "Test reports found in \`$REPORTS_DIR\`."
echo ""
echo "To restore context after compaction, read the relevant report on demand:"
for report in "${REPORTS[@]}"; do
  if [ -f "$REPORTS_DIR/$report" ]; then
    echo "- Read \`$REPORTS_DIR/$report\`"
  fi
done
echo ""
echo "JSON reports (if present) follow schema_version 1.x — see \`skills/paper-test/references/json-output-schema.md\`."
