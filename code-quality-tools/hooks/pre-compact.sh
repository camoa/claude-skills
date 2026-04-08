#!/usr/bin/env bash
# Pre-compact hook: Instruct Claude to read audit reports instead of dumping content

# Find .reports directory
REPORTS_DIR=".reports"
if [ ! -d "$REPORTS_DIR" ]; then
  REPORTS_DIR=$(find . -maxdepth 2 -type d -name ".reports" 2>/dev/null | head -1)
fi

if [ -z "$REPORTS_DIR" ] || [ ! -d "$REPORTS_DIR" ]; then
  exit 0
fi

echo "## Pre-Compaction Context (code-quality-tools)"
echo ""
echo "Reports directory found: \`$REPORTS_DIR\`"
echo ""
echo "To restore context after compaction:"
echo "1. List \`$REPORTS_DIR/\` for available reports"

[ -f "$REPORTS_DIR/audit-synthesis.md" ] && echo "2. Read \`$REPORTS_DIR/audit-synthesis.md\` for audit synthesis"

for review in "$REPORTS_DIR"/code-review-*.md; do
  if [ -f "$review" ]; then
    echo "3. Read \`$review\` for code review results"
    break
  fi
done

for debate in security-debate.md architecture-debate.md; do
  if [ -f "$REPORTS_DIR/$debate" ]; then
    echo "4. Read \`$REPORTS_DIR/$debate\` for debate results"
  fi
done
