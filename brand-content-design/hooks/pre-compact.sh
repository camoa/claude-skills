#!/bin/bash
# Pre-compaction context preservation for brand-content-design plugin
# Instructs Claude to read live brand project state instead of dumping content

# Find active brand project by looking for brand-philosophy.md in current directory
BRAND_PROJECT=""
for dir in */; do
  if [ -f "${dir}brand-philosophy.md" ]; then
    BRAND_PROJECT="$dir"
    break
  fi
done

if [ -z "$BRAND_PROJECT" ]; then
  exit 0
fi

echo "## Pre-Compaction Context (brand-content-design)"
echo ""
echo "Active brand project found: **${BRAND_PROJECT}**"
echo ""
echo "To restore context after compaction:"
echo "1. Read \`${BRAND_PROJECT}brand-philosophy.md\` for brand identity and design tokens"
if [ -d "${BRAND_PROJECT}templates" ]; then
  echo "2. List \`${BRAND_PROJECT}templates/\` for available templates"
fi
if [ -d "${BRAND_PROJECT}output" ]; then
  echo "3. List \`${BRAND_PROJECT}output/\` for recent outputs"
fi
