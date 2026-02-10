#!/bin/bash
# Pre-compaction context preservation for brand-content-design plugin
# Outputs active brand project state so it survives context compaction

echo "## Pre-Compaction Context (brand-content-design)"

# Find active brand project by looking for brand-philosophy.md in recent directories
BRAND_PROJECT=""
for dir in */; do
  if [ -f "${dir}brand-philosophy.md" ]; then
    BRAND_PROJECT="$dir"
    break
  fi
done

if [ -z "$BRAND_PROJECT" ]; then
  echo "No active brand project found in current directory."
  exit 0
fi

echo "### Active Brand Project: ${BRAND_PROJECT}"

# Output brand philosophy summary (first 20 lines)
if [ -f "${BRAND_PROJECT}brand-philosophy.md" ]; then
  echo "#### Brand Philosophy"
  head -20 "${BRAND_PROJECT}brand-philosophy.md"
  echo "..."
fi

# List available templates
if [ -d "${BRAND_PROJECT}templates" ]; then
  echo "#### Templates"
  ls "${BRAND_PROJECT}templates/" 2>/dev/null
fi

# List recent outputs
if [ -d "${BRAND_PROJECT}output" ]; then
  echo "#### Recent Outputs"
  ls -t "${BRAND_PROJECT}output/" 2>/dev/null | head -5
fi
