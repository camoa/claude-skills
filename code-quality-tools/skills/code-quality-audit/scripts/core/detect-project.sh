#!/bin/bash
#
# Project Type Detection Script
# Auto-detects Drupal or Next.js projects
#
# Usage: bash detect-project.sh [project-path]
# Output: "drupal", "nextjs", "both", or "unknown"
#

set -euo pipefail

# Default to current directory if no path provided
PROJECT_PATH="${1:-.}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Detection functions
detect_drupal() {
  local path="$1"

  # Check for composer.json with drupal/core
  if [ -f "$path/composer.json" ]; then
    if grep -q '"drupal/core"' "$path/composer.json" 2>/dev/null; then
      return 0
    fi
  fi

  # Check for web/core directory (Drupal 8+)
  if [ -d "$path/web/core" ] || [ -d "$path/docroot/core" ]; then
    return 0
  fi

  # Check for .ddev/config.yaml
  if [ -f "$path/.ddev/config.yaml" ]; then
    if grep -q 'type: drupal' "$path/.ddev/config.yaml" 2>/dev/null; then
      return 0
    fi
  fi

  return 1
}

detect_nextjs() {
  local path="$1"

  # Check for package.json with next dependency
  if [ -f "$path/package.json" ]; then
    if grep -q '"next"' "$path/package.json" 2>/dev/null; then
      return 0
    fi
  fi

  # Check for next.config.js or next.config.mjs
  if [ -f "$path/next.config.js" ] || [ -f "$path/next.config.mjs" ] || [ -f "$path/next.config.ts" ]; then
    return 0
  fi

  # Check for pages/ or app/ directory (Next.js structure)
  if [ -d "$path/pages" ] || [ -d "$path/app" ]; then
    if [ -f "$path/package.json" ]; then
      return 0
    fi
  fi

  return 1
}

# Main detection logic
main() {
  local drupal_detected=false
  local nextjs_detected=false

  # Run detection
  if detect_drupal "$PROJECT_PATH"; then
    drupal_detected=true
  fi

  if detect_nextjs "$PROJECT_PATH"; then
    nextjs_detected=true
  fi

  # Determine result
  if [ "$drupal_detected" = true ] && [ "$nextjs_detected" = true ]; then
    echo "both"
    >&2 echo -e "${YELLOW}⚠️  Both Drupal and Next.js detected${NC}"
    >&2 echo -e "${YELLOW}   Using Drupal detection for primary analysis${NC}"
  elif [ "$drupal_detected" = true ]; then
    echo "drupal"
    >&2 echo -e "${GREEN}✓ Detected: Drupal project${NC}"
  elif [ "$nextjs_detected" = true ]; then
    echo "nextjs"
    >&2 echo -e "${GREEN}✓ Detected: Next.js project${NC}"
  else
    echo "unknown"
    >&2 echo -e "${RED}✗ Could not detect project type${NC}"
    >&2 echo -e "${RED}   Expected: Drupal (composer.json with drupal/core) or Next.js (package.json with next)${NC}"
    exit 1
  fi
}

# Run main function
main
