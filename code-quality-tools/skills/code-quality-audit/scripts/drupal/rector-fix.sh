#!/bin/bash
# rector-fix.sh - Auto-fix deprecations with drupal-rector
# Part of code-quality-audit skill

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPORT_DIR="${REPORT_DIR:-.reports}"
DRUPAL_MODULES_PATH="${DRUPAL_MODULES_PATH:-web/modules/custom}"

echo "=== Drupal Rector - Auto-fix Deprecations ==="
echo ""

# Check DDEV
if ! ddev describe &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} DDEV is not running"
    exit 2
fi

# Check if rector is available
if ! ddev exec vendor/bin/rector --version &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Rector is not installed"
    echo "  Run: ddev composer require --dev palantirnet/drupal-rector"
    exit 1
fi

# Check for rector.php config
if [ ! -f "rector.php" ]; then
    echo -e "${YELLOW}[INFO]${NC} No rector.php config found"
    echo "  Creating default config for Drupal..."

    # Create default rector.php for Drupal
    cat > rector.php << 'EOF'
<?php

declare(strict_types=1);

use Rector\Config\RectorConfig;
use DrupalRector\Set\Drupal10SetList;
use DrupalRector\Set\Drupal11SetList;

return RectorConfig::configure()
    ->withPaths([
        __DIR__ . '/web/modules/custom',
        __DIR__ . '/web/themes/custom',
    ])
    ->withSets([
        Drupal10SetList::DRUPAL_10,
        Drupal11SetList::DRUPAL_11,
    ])
    ->withSkip([
        // Skip test files if needed
        '*/tests/*',
    ]);
EOF
    echo -e "${GREEN}[OK]${NC} Created rector.php"
fi

mkdir -p "${REPORT_DIR}/rector"

# Parse command line arguments
DRY_RUN=true
if [ "$1" == "--apply" ]; then
    DRY_RUN=false
fi

if [ "$DRY_RUN" == true ]; then
    echo -e "${BLUE}[DRY RUN]${NC} Checking for deprecations (no changes will be made)..."
    echo ""

    # Run rector in dry-run mode
    set +e
    ddev exec vendor/bin/rector process "${DRUPAL_MODULES_PATH}" --dry-run 2>&1 | tee "${REPORT_DIR}/rector/dry-run.txt"
    RECTOR_EXIT=$?
    set -e

    # Count changes
    CHANGES=$(grep -c "would be applied" "${REPORT_DIR}/rector/dry-run.txt" 2>/dev/null || echo "0")

    echo ""
    echo "=== Summary ==="
    if [ "$CHANGES" -gt 0 ] || [ "$RECTOR_EXIT" -ne 0 ]; then
        echo -e "${YELLOW}Found ${CHANGES} deprecations that can be auto-fixed${NC}"
        echo ""
        echo "To apply fixes, run:"
        echo "  scripts/drupal/rector-fix.sh --apply"
        echo ""
        echo "Or manually:"
        echo "  ddev exec vendor/bin/rector process ${DRUPAL_MODULES_PATH}"
        exit 1
    else
        echo -e "${GREEN}No deprecations found!${NC}"
        exit 0
    fi
else
    echo -e "${YELLOW}[APPLY]${NC} Fixing deprecations..."
    echo ""

    # Run rector
    set +e
    ddev exec vendor/bin/rector process "${DRUPAL_MODULES_PATH}" 2>&1 | tee "${REPORT_DIR}/rector/apply.txt"
    RECTOR_EXIT=$?
    set -e

    echo ""
    if [ "$RECTOR_EXIT" -eq 0 ]; then
        echo -e "${GREEN}[OK]${NC} Deprecations fixed successfully"
        echo ""
        echo "Review changes with:"
        echo "  git diff"
        exit 0
    else
        echo -e "${YELLOW}[WARN]${NC} Some issues may need manual review"
        exit 1
    fi
fi
