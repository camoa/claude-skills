#!/usr/bin/env bash
# Pre-compact hook: Instruct Claude to read plugin state instead of dumping content

# Find plugin.json in current directory or subdirectories
PLUGIN_JSON=""
if [ -f ".claude-plugin/plugin.json" ]; then
  PLUGIN_JSON=".claude-plugin/plugin.json"
elif [ -f "plugin.json" ]; then
  PLUGIN_JSON="plugin.json"
else
  PLUGIN_JSON=$(find . -maxdepth 3 -name "plugin.json" -path "*/.claude-plugin/*" 2>/dev/null | head -1)
fi

if [ -z "$PLUGIN_JSON" ]; then
  exit 0
fi

PLUGIN_DIR=$(dirname "$(dirname "$PLUGIN_JSON")")
PLUGIN_NAME=$(jq -r '.name // "unknown"' "$PLUGIN_JSON" 2>/dev/null)
PLUGIN_VERSION=$(jq -r '.version // "unknown"' "$PLUGIN_JSON" 2>/dev/null)

echo "## Pre-Compaction Context (plugin-creation-tools)"
echo ""
echo "Active plugin: **$PLUGIN_NAME v$PLUGIN_VERSION** at \`$PLUGIN_DIR\`"
echo ""
echo "To restore context after compaction:"
echo "1. Read \`$PLUGIN_JSON\` for plugin metadata"
echo "2. List \`$PLUGIN_DIR/skills/\`, \`$PLUGIN_DIR/commands/\`, \`$PLUGIN_DIR/agents/\` for components"
if [ -f "$PLUGIN_DIR/CLAUDE.md" ]; then
  echo "3. Read \`$PLUGIN_DIR/CLAUDE.md\` for plugin conventions"
fi
