#!/usr/bin/env bash
# Pre-compact hook: Preserve HTMX migration context before compaction
# Outputs analyzed modules, migration progress, and pattern recommendations

echo "## Pre-Compaction Context (drupal-htmx)"
echo ""

# Find custom modules directory
MODULES_PATH=""
for path in web/modules/custom modules/custom docroot/modules/custom; do
  if [ -d "$path" ]; then
    MODULES_PATH="$path"
    break
  fi
done

if [ -z "$MODULES_PATH" ]; then
  echo "No custom modules directory found."
  exit 0
fi

echo "### Custom Modules: $MODULES_PATH"
echo ""

# Scan for HTMX usage (modules already migrated)
HTMX_MODULES=$(grep -rl "Htmx\|hx-get\|hx-post\|hx-swap" "$MODULES_PATH" --include="*.php" 2>/dev/null | sed 's|/[^/]*$||' | sort -u)
if [ -n "$HTMX_MODULES" ]; then
  echo "### Modules Using HTMX"
  echo "$HTMX_MODULES" | while read -r mod; do
    echo "- $(basename "$mod")"
  done
  echo ""
fi

# Scan for remaining AJAX patterns (migration candidates)
AJAX_MODULES=$(grep -rl "'#ajax'" "$MODULES_PATH" --include="*.php" 2>/dev/null | sed 's|/[^/]*$||' | sort -u)
if [ -n "$AJAX_MODULES" ]; then
  echo "### Modules With AJAX (Migration Candidates)"
  echo "$AJAX_MODULES" | while read -r mod; do
    count=$(grep -c "'#ajax'" "$mod"/*.php 2>/dev/null | awk -F: '{s+=$2} END{print s}')
    echo "- $(basename "$mod") ($count AJAX patterns)"
  done
  echo ""
fi

# Check for mixed modules (both HTMX and AJAX — in-progress migration)
if [ -n "$HTMX_MODULES" ] && [ -n "$AJAX_MODULES" ]; then
  MIXED=$(comm -12 <(echo "$HTMX_MODULES" | sort) <(echo "$AJAX_MODULES" | sort))
  if [ -n "$MIXED" ]; then
    echo "### In-Progress Migrations (Both HTMX + AJAX)"
    echo "$MIXED" | while read -r mod; do
      echo "- $(basename "$mod")"
    done
    echo ""
  fi
fi
