#!/usr/bin/env bash
# Pre-compact hook: Preserve active audit context before compaction
# Outputs report paths, last command run, and key findings

echo "## Pre-Compaction Context (code-quality-tools)"
echo ""

# Find .reports directory
REPORTS_DIR=".reports"
if [ ! -d "$REPORTS_DIR" ]; then
  REPORTS_DIR=$(find . -maxdepth 2 -type d -name ".reports" 2>/dev/null | head -1)
fi

if [ -z "$REPORTS_DIR" ] || [ ! -d "$REPORTS_DIR" ]; then
  echo "No .reports/ directory found. No active audit session."
  exit 0
fi

echo "### Reports Directory: $REPORTS_DIR"
echo ""

# List available reports with timestamps
echo "### Available Reports"
ls -lt "$REPORTS_DIR"/*.{json,md} 2>/dev/null | head -10 | while read -r line; do
  echo "- $line"
done
echo ""

# Show synthesis if it exists (most valuable for context)
if [ -f "$REPORTS_DIR/audit-synthesis.md" ]; then
  echo "### Audit Synthesis (summary)"
  head -30 "$REPORTS_DIR/audit-synthesis.md"
  echo "..."
  echo ""
fi

# Show code review if it exists
for review in "$REPORTS_DIR"/code-review-*.md; do
  if [ -f "$review" ]; then
    echo "### Code Review: $(basename "$review")"
    head -20 "$review"
    echo "..."
    echo ""
    break  # Only show most recent
  fi
done

# Show debate results if they exist
for debate in security-debate.md architecture-debate.md; do
  if [ -f "$REPORTS_DIR/$debate" ]; then
    echo "### Debate: $debate"
    head -15 "$REPORTS_DIR/$debate"
    echo "..."
    echo ""
  fi
done
