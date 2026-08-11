#!/usr/bin/env bash
# Pre-compact hook: Instruct Claude to read audit reports instead of dumping content
#
# This hook used to look for `.reports` in the working directory. That was where every
# script wrote until the report directory moved out of the audited repository, so after
# the move the hook found nothing and every audit run silently lost its context at
# compaction. It now asks the same file the scripts source, which is the only way to
# stay correct without keeping a second copy of the resolution rule here.
#
# `--latest` and not `--print`: this hook is a READER. `--print` answers where the NEXT
# run would write, which for the out-of-repo layout is a timestamped directory that does
# not exist yet.

REPORTS_DIR=""

# Resolve relative to this file rather than $CLAUDE_PLUGIN_ROOT: the variable is set for
# plugin-shipped hooks, but a copy of this hook wired into a project's own settings.json
# gets no such variable, and a wrong path here fails the same silent way the old
# `.reports` default did.
SEAM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills/code-quality-audit/scripts/core" 2>/dev/null && pwd)"
if [ -n "$SEAM_DIR" ] && [ -r "$SEAM_DIR/report-dir.sh" ]; then
  REPORTS_DIR=$(bash "$SEAM_DIR/report-dir.sh" --latest 2>/dev/null || true)
fi

# Fallbacks for reports this resolution cannot claim: an in-repo `.reports` from the
# opt-in path or from a checkout audited by an older version of this plugin. Still real
# reports, still worth pointing at.
if [ -z "$REPORTS_DIR" ] || [ ! -d "$REPORTS_DIR" ]; then
  REPORTS_DIR=".reports"
fi
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
