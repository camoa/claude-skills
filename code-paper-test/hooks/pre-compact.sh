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

# Check if any test team reports exist
FOUND=false
for report in happy-path-analysis.md edge-case-analysis.md red-team-analysis.md paper-test-team-report.md; do
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
echo "To restore context after compaction:"
for report in happy-path-analysis.md edge-case-analysis.md red-team-analysis.md paper-test-team-report.md; do
  if [ -f "$REPORTS_DIR/$report" ]; then
    echo "- Read \`$REPORTS_DIR/$report\`"
  fi
done
