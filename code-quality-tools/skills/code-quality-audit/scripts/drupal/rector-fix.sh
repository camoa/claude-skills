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

# Where reports go is decided in one place, and it is never inside the audited
# repository unless REPORT_DIR says so or REPORT_DIR_IN_REPO=1 asks for it.
# shellcheck source=../core/report-dir.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/report-dir.sh"
cqt_report_dir_init
cqt_announce_report_dir

# Where this project's custom code lives is answered in ONE place, for every gate.
# shellcheck source=../core/path-resolve.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/path-resolve.sh"
cqt_resolve_drupal_paths

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
    echo "  Run: ddev composer require --dev palantirnet/drupal-rector:^1.1"
    exit 1
fi

# Check for rector.php config
if [ ! -f "rector.php" ]; then
    echo -e "${YELLOW}[INFO]${NC} No rector.php config found"
    echo "  Creating default config for Drupal..."

    # The heredoc STAYS QUOTED — it is PHP, and an unquoted one would have the shell
    # interpret `$` and backslashes in it — so the resolved paths go in as placeholders
    # and one substitution pass afterwards. Same shape, and the same reason, as the
    # psalm.xml generation in security-check.sh.
    #
    # This file outlives the run that writes it: it is created only when the project has
    # none and found on every later run, so a layout literal baked in here keeps rector
    # pointed at directories that do not exist long after the gate itself is fixed.
    #
    # A path containing a single quote would break the PHP string literal, so it is
    # refused rather than written.
    if [ "${DRUPAL_MODULES_PATH}" != "${DRUPAL_MODULES_PATH//\'/}" ] \
       || [ "${DRUPAL_THEMES_PATH}" != "${DRUPAL_THEMES_PATH//\'/}" ]; then
        echo -e "${YELLOW}[SKIP]${NC} rector.php not generated: a custom path contains a single quote"
    else
    # Create default rector.php for Drupal
    cat > rector.php << 'EOF'
<?php

declare(strict_types=1);

use Rector\Config\RectorConfig;
use DrupalRector\Set\Drupal10SetList;
use DrupalRector\Set\Drupal11SetList;

return RectorConfig::configure()
    ->withPaths([
        __DIR__ . '/@CQT_MODULES@',
        __DIR__ . '/@CQT_THEMES@',
    ])
    ->withSets([
        Drupal10SetList::DRUPAL_10,
        Drupal11SetList::DRUPAL_11,
    ])
    ->withSkip([
        // Skip test files if needed
        '*/tests/*',
        // Somebody else's code, vendored into this tree.
        '*/node_modules/*',
        '*/vendor/*',
    ]);
EOF
    # `|` as the sed delimiter, because the values are paths and contain `/`.
    sed -i.cqtbak \
        -e "s|@CQT_MODULES@|${DRUPAL_MODULES_PATH}|" \
        -e "s|@CQT_THEMES@|${DRUPAL_THEMES_PATH}|" \
        rector.php
    rm -f rector.php.cqtbak
    echo -e "${GREEN}[OK]${NC} Created rector.php"
    fi
fi

# Is there anything to process? Checked BEFORE rector is invoked, so the verdict does not
# depend on what rector does with a path that is not there — which was never exercised,
# and which the pipeline below could not have read correctly anyway.
#
# Exit 4, never 0 and never 3. This gate writes no JSON report, so the exit code is not a
# fallback channel here — a direct caller, or AIDA's /validate-* wrappers, have nothing
# else to read.
if [ "$(cqt_scan_path_state "${DRUPAL_MODULES_PATH}")" != "ok" ]; then
    cqt_unmeasured "the custom modules path is not there — no deprecations were looked for" \
        "${DRUPAL_MODULES_PATH}"
    exit "$CQT_EXIT_UNMEASURED"
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
    # PIPESTATUS[0], not $?. After `cmd | tee file`, `$?` is TEE's status, and tee
    # succeeds whenever it can write the file — so a rector that died was read as a
    # rector that exited 0. The guard below is `changes > 0 OR exit != 0`, which means
    # half of it had never fired.
    RECTOR_EXIT=${PIPESTATUS[0]}
    set -e

    # Count changes. `|| true`, not `|| echo "0"`: grep -c PRINTS its count and exits 1
    # when that count is zero, so the fallback appended a SECOND zero and the comparison
    # below errored on "0\n0" — which `if` swallows as false.
    CHANGES=$(grep -c "would be applied" "${REPORT_DIR}/rector/dry-run.txt" 2>/dev/null || true)
    CHANGES="${CHANGES:-0}"

    # A rector that never ran is not a rector that found nothing. Only shell-level
    # statuses are read this way: rector's own non-zero codes mean it found changes,
    # which is a measurement.
    if [ "$RECTOR_EXIT" -ge 126 ]; then
        cqt_unmeasured "rector produced no result (exit ${RECTOR_EXIT}) — deprecations were NOT checked" \
            "${DRUPAL_MODULES_PATH}"
        exit "$CQT_EXIT_UNMEASURED"
    fi

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
    # See the dry-run branch: `$?` after a pipe is tee's, not rector's.
    RECTOR_EXIT=${PIPESTATUS[0]}
    set -e

    if [ "$RECTOR_EXIT" -ge 126 ]; then
        cqt_unmeasured "rector produced no result (exit ${RECTOR_EXIT}) — nothing was fixed" \
            "${DRUPAL_MODULES_PATH}"
        exit "$CQT_EXIT_UNMEASURED"
    fi

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
