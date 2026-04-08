#!/usr/bin/env bash
# Pre-compact hook: Instruct Claude to scan for HTMX/AJAX state instead of dumping content

# Find custom modules directory
MODULES_PATH=""
for path in web/modules/custom modules/custom docroot/modules/custom; do
  if [ -d "$path" ]; then
    MODULES_PATH="$path"
    break
  fi
done

if [ -z "$MODULES_PATH" ]; then
  exit 0
fi

echo "## Pre-Compaction Context (drupal-htmx)"
echo ""
echo "Custom modules found at \`$MODULES_PATH\`."
echo ""
echo "To restore HTMX migration context after compaction:"
echo "1. Grep \`$MODULES_PATH\` for \`hx-get\`, \`hx-post\`, \`hx-swap\` to find modules already using HTMX"
echo "2. Grep \`$MODULES_PATH\` for \`'#ajax'\` to find migration candidates"
echo "3. Modules with both patterns are in-progress migrations"
