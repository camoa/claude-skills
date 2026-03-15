#!/usr/bin/env bash
# Pre-compact hook: Preserve active plugin development context before compaction
# Outputs plugin being built/edited, its components, and validation state

echo "## Pre-Compaction Context (plugin-creation-tools)"
echo ""

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
  echo "No plugin.json found. Not currently in a plugin project."
  exit 0
fi

PLUGIN_DIR=$(dirname "$(dirname "$PLUGIN_JSON")")
PLUGIN_NAME=$(jq -r '.name // "unknown"' "$PLUGIN_JSON" 2>/dev/null)
PLUGIN_VERSION=$(jq -r '.version // "unknown"' "$PLUGIN_JSON" 2>/dev/null)

echo "### Active Plugin: $PLUGIN_NAME v$PLUGIN_VERSION"
echo "### Location: $PLUGIN_DIR"
echo ""

# List components
echo "### Components"
SKILLS=$(find "$PLUGIN_DIR/skills" -name "SKILL.md" 2>/dev/null | wc -l)
COMMANDS=$(find "$PLUGIN_DIR/commands" -name "*.md" 2>/dev/null | wc -l)
AGENTS=$(find "$PLUGIN_DIR/agents" -name "*.md" 2>/dev/null | wc -l)
HOOKS_COUNT=0
[ -f "$PLUGIN_DIR/hooks/hooks.json" ] && HOOKS_COUNT=$(jq '[.hooks | to_entries[].value[].hooks | length] | add // 0' "$PLUGIN_DIR/hooks/hooks.json" 2>/dev/null)

echo "- Skills: $SKILLS"
echo "- Commands: $COMMANDS"
echo "- Agents: $AGENTS"
echo "- Hooks: $HOOKS_COUNT"
echo ""

# Show CLAUDE.md if it exists (plugin conventions)
if [ -f "$PLUGIN_DIR/CLAUDE.md" ]; then
  echo "### Plugin Conventions"
  head -15 "$PLUGIN_DIR/CLAUDE.md"
  echo "..."
fi
