#!/usr/bin/env bash
# Pre-compact hook: Preserve active paper test context before compaction
# Outputs what's being tested, findings so far, and test team status

echo "## Pre-Compaction Context (code-paper-test)"
echo ""

# Find .reports directory for test team results
REPORTS_DIR=".reports"
if [ ! -d "$REPORTS_DIR" ]; then
  REPORTS_DIR=$(find . -maxdepth 2 -type d -name ".reports" 2>/dev/null | head -1)
fi

# Check for test team reports
if [ -n "$REPORTS_DIR" ] && [ -d "$REPORTS_DIR" ]; then
  FOUND_REPORTS=false

  for report in happy-path-analysis.md edge-case-analysis.md red-team-analysis.md paper-test-synthesis.md; do
    if [ -f "$REPORTS_DIR/$report" ]; then
      if [ "$FOUND_REPORTS" = false ]; then
        echo "### Test Team Reports in $REPORTS_DIR"
        FOUND_REPORTS=true
      fi
      echo ""
      echo "#### $(basename "$report" .md)"
      head -20 "$REPORTS_DIR/$report"
      echo "..."
    fi
  done

  if [ "$FOUND_REPORTS" = true ]; then
    exit 0
  fi
fi

echo "No active paper test session found."
echo "Use /paper-test or /test-team to start testing."
