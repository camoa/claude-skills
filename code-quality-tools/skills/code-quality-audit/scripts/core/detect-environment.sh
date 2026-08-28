#!/bin/bash
# detect-environment.sh - Detect project type and validate environment
# Part of code-quality-audit skill

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# shellcheck source=../core/report-dir.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/report-dir.sh"
# Where the custom code is, and what a gate does when it is not there. The rule lives in
# its own library because seven gates need it and none of them can afford to source THIS
# script to get it: everything above main() here runs at source time, including `set -e`,
# a banner, report-dir.sh and fourteen globals two of which full-audit.sh owns. This
# script keeps its own function names as thin wrappers over the library, so nothing that
# calls them changes.
# shellcheck source=../core/path-resolve.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)/path-resolve.sh"

# Default values
PROJECT_TYPE="unknown"
PROJECT_ROOT="${PWD}"
DRUPAL_ROOT=""
NEXTJS_ROOT=""
DDEV_AVAILABLE="false"
ENV_READY="false"
DRUPAL_VERSION=""

# The composer.lock / installed-tree comparison. "unchecked" is the honest starting
# value: it is not "match", because claiming a match for a comparison that never ran is
# the same false clean this suite exists to catch.
VERSION_DRIFT="unchecked"
VERSION_DRIFT_REASON="not applicable"
COMPOSER_LOCK_CORE_VERSION=""

echo "=== Code Quality Audit - Environment Detection ==="
echo ""

# Check for DDEV
check_ddev() {
    if command -v ddev &> /dev/null; then
        echo -e "${GREEN}[OK]${NC} DDEV is installed"

        # Check if we're in a DDEV project
        if [ -f ".ddev/config.yaml" ]; then
            echo -e "${GREEN}[OK]${NC} DDEV project detected"

            # Check if DDEV is running
            if ddev describe &> /dev/null; then
                echo -e "${GREEN}[OK]${NC} DDEV is running"
                DDEV_AVAILABLE="true"
            else
                echo -e "${YELLOW}[WARN]${NC} DDEV is not running. Starting..."
                ddev start
                DDEV_AVAILABLE="true"
            fi
        else
            echo -e "${YELLOW}[WARN]${NC} Not in a DDEV project directory"
            echo "  Recommendation: Run 'ddev config' to initialize DDEV"
        fi
    else
        echo -e "${RED}[ERROR]${NC} DDEV is not installed"
        echo "  Recommendation: Install DDEV from https://ddev.com/get-started/"
        echo "  This skill requires DDEV for consistent PHP environment"
    fi
}

# Detect Drupal project
detect_drupal() {
    local search_paths=("." "drupal-app" "web" "docroot")

    for path in "${search_paths[@]}"; do
        # Check for Drupal indicators
        if [ -f "${path}/core/lib/Drupal.php" ] || [ -f "${path}/web/core/lib/Drupal.php" ]; then
            echo -e "${GREEN}[OK]${NC} Drupal project detected"

            # Determine web root
            if [ -f "${path}/web/core/lib/Drupal.php" ]; then
                DRUPAL_ROOT="${PROJECT_ROOT}/${path}/web"
            elif [ -f "${path}/core/lib/Drupal.php" ]; then
                DRUPAL_ROOT="${PROJECT_ROOT}/${path}"
            fi

            PROJECT_TYPE="drupal"

            # Check Drupal version. Kept in its own variable rather than the shared
            # VERSION, which detect_nextjs overwrites moments later: this value is the
            # left-hand side of the composer.lock comparison below.
            if [ -f "${DRUPAL_ROOT}/core/lib/Drupal.php" ]; then
                DRUPAL_VERSION=$(grep -oP "const VERSION = '\K[^']+" "${DRUPAL_ROOT}/core/lib/Drupal.php" 2>/dev/null || echo "unknown")
                echo "  Drupal version: ${DRUPAL_VERSION}"
            fi

            return 0
        fi
    done

    return 1
}

# Detect Next.js project
detect_nextjs() {
    local search_paths=("." "frontend" "next-app" "web")

    for path in "${search_paths[@]}"; do
        if [ -f "${path}/next.config.js" ] || [ -f "${path}/next.config.mjs" ] || [ -f "${path}/next.config.ts" ]; then
            echo -e "${GREEN}[OK]${NC} Next.js project detected"
            NEXTJS_ROOT="${PROJECT_ROOT}/${path}"

            if [ "$PROJECT_TYPE" == "drupal" ]; then
                PROJECT_TYPE="monorepo"
            else
                PROJECT_TYPE="nextjs"
            fi

            # Check Next.js version
            if [ -f "${path}/package.json" ]; then
                VERSION=$(grep -oP '"next":\s*"\K[^"]+' "${path}/package.json" 2>/dev/null || echo "unknown")
                echo "  Next.js version: ${VERSION}"
            fi

            return 0
        fi
    done

    return 1
}

# The detected Drupal root as a project-root-relative prefix, and one resolved
# custom-code path.
#
# Both bodies now live in core/path-resolve.sh, which is sourced above; these are thin
# wrappers that keep this script's own names, signatures and output. Callers here are
# untouched. The library is where they live because a GATE needs the same two answers,
# and a gate cannot source this file to get them.
#
# The announcements stay HERE rather than moving down with the logic: they are this
# command's user interface, and a gate sourcing the library must not print an
# environment-detection banner in the middle of its own output. So the library resolves
# silently and reports the origin (explicit / derived / nonstandard) and the state
# (ok / missing), and this wrapper turns those into the five lines it has always printed.
drupal_root_prefix() {
    cqt_drupal_root_prefix
}

resolve_custom_path() {
    local var_name="$1" kind="$2"
    local value

    cqt_resolve_custom_path "$var_name" "$kind"
    value="${!var_name}"

    case "${CQT_PATH_ORIGIN}:${CQT_PATH_STATE}" in
        nonstandard:ok)
            echo -e "${YELLOW}[WARN]${NC} Custom ${kind} at non-standard path: ${value}"
            ;;
        *:ok)
            echo -e "${GREEN}[OK]${NC} Custom ${kind} found at: ${value}"
            ;;
        *)
            echo -e "${YELLOW}[WARN]${NC} No custom ${kind} directory found"
            echo "  Expected: ${value}"
            ;;
    esac
}

# Check for custom modules and themes paths
check_custom_paths() {
    resolve_custom_path DRUPAL_MODULES_PATH modules
    resolve_custom_path DRUPAL_THEMES_PATH themes
}

# Create report directory.
#
# The whole rule — resolution order, creation, permissions, the gitignore entry — lives
# in core/report-dir.sh, because sixteen scripts resolved REPORT_DIR independently and
# NONE of them called this function. Anything owned here alone would have applied to the
# environment detection and to nothing else.
setup_report_dir() {
    cqt_report_dir_init
    cqt_announce_report_dir
}

# Compare what composer.lock says is installed against what is actually on disk.
#
# The project this check was written for had composer.lock pinning Drupal 11.3.13 while
# vendor/ and docroot/core held 10.5.6, because an earlier `composer install` had failed
# on an expired token in auth.json. This script read 10.5.6 correctly and wrote it to
# environment.json; nothing compared the two. Every gate then ran against the mismatch,
# comparing Drupal 11 custom code against Drupal 10 core, and every finding had to be
# thrown away once the cause was found.
#
# Sets VERSION_DRIFT to one of:
#   match      both versions are concrete and equal
#   drift      both are concrete and differ
#   unchecked  no comparison was possible, with the reason recorded alongside
#
# "unchecked" is deliberately not a soft "probably fine". It is what the record says
# whenever the comparison could not be made, so a consumer can tell "we looked and it
# was fine" from "we never looked".
check_version_drift() {
    VERSION_DRIFT="unchecked"

    if [ ! -f "composer.lock" ]; then
        VERSION_DRIFT_REASON="no composer.lock in the project root"
        return 0
    fi

    # jq rather than a grep for a version string: composer.lock lists every package, and
    # a pattern loose enough to find drupal/core's version finds other packages' too. A
    # false drift stop on somebody else's repository is worse than no check at all.
    if ! command -v jq &> /dev/null; then
        VERSION_DRIFT_REASON="jq is not available to read composer.lock"
        return 0
    fi

    # "we read the file and it does not pin drupal/core" and "we never got to read the
    # file" are different findings, and only one of them is about the file's CONTENT.
    # They used to be the same line: jq's failure was swallowed by `|| echo ""`, so an
    # unreadable, an empty and a corrupt lockfile were all reported as
    # "composer.lock does not pin drupal/core" — a statement about content that had never
    # been established. version_drift is deliberately "unchecked" for both, because it
    # records whether a comparison happened; version_drift_reason is the field that is
    # supposed to say WHY, and it is the one an operator acts on.
    if [ ! -r "composer.lock" ]; then
        VERSION_DRIFT_REASON="composer.lock could not be read"
        return 0
    fi
    if [ ! -s "composer.lock" ]; then
        VERSION_DRIFT_REASON="composer.lock is empty"
        return 0
    fi

    # Status captured rather than discarded. `X=$(cmd) || rc=$?` is safe under `set -e`:
    # the assignment's status is the command substitution's, and testing it is what makes
    # it not fatal.
    local lock_read=0
    COMPOSER_LOCK_CORE_VERSION=$(jq -r '
        [ (.packages // [])[], (."packages-dev" // [])[] ]
        | map(select(.name == "drupal/core"))
        | .[0].version // ""
    ' composer.lock 2>/dev/null) || lock_read=$?
    if [ "${lock_read}" -ne 0 ]; then
        # Covers both a file that is not JSON and a file that is JSON of the wrong shape
        # (packages as an object, say). The reason names what happened rather than
        # guessing which, because the remedy is the same: look at the file.
        COMPOSER_LOCK_CORE_VERSION=""
        VERSION_DRIFT_REASON="composer.lock could not be parsed"
        return 0
    fi
    COMPOSER_LOCK_CORE_VERSION="${COMPOSER_LOCK_CORE_VERSION#v}"

    if [ -z "${COMPOSER_LOCK_CORE_VERSION}" ]; then
        VERSION_DRIFT_REASON="composer.lock does not pin drupal/core"
        return 0
    fi

    if [ -z "${DRUPAL_VERSION}" ] || [ "${DRUPAL_VERSION}" = "unknown" ]; then
        VERSION_DRIFT_REASON="the installed core version could not be read"
        return 0
    fi

    # A development branch carries no comparable version: composer.lock says 11.3.x-dev
    # while Drupal.php says 11.3.13, and they do not disagree. Stopping every run on a
    # project tracking a dev branch is the fastest way to have this check turned off for
    # good.
    case "${COMPOSER_LOCK_CORE_VERSION}${DRUPAL_VERSION}" in
        *dev*)
            VERSION_DRIFT_REASON="a development branch is pinned (${COMPOSER_LOCK_CORE_VERSION} / ${DRUPAL_VERSION})"
            return 0
            ;;
    esac

    if [ "${COMPOSER_LOCK_CORE_VERSION}" = "${DRUPAL_VERSION}" ]; then
        VERSION_DRIFT="match"
        VERSION_DRIFT_REASON="composer.lock and the installed core agree"
    else
        VERSION_DRIFT="drift"
        VERSION_DRIFT_REASON="composer.lock pins ${COMPOSER_LOCK_CORE_VERSION}, the installed core is ${DRUPAL_VERSION}"
    fi
    return 0
}

# A hard stop, not a warning.
#
# No gate downstream can be right about a tree whose core is not the core its
# dependencies were resolved against, so continuing produces findings whose only possible
# use is to be discarded — and a warning at step 1 of six is not what anyone reads six
# steps later. The remedy is one command, and it is named.
#
# Overridable, because this is somebody else's repository and because a version
# comparison can be wrong in ways the person at the keyboard can see and this script
# cannot. Overriding does not buy a clean bill of health: the drift stays recorded in
# environment.json, and full-audit.sh reads it back and caps the verdict.
enforce_version_drift() {
    [ "${VERSION_DRIFT}" = "drift" ] || return 0

    echo ""
    echo -e "${RED}[STOP]${NC} The installed code does not match composer.lock"
    echo "  composer.lock pins drupal/core ${COMPOSER_LOCK_CORE_VERSION}"
    echo "  the tree on disk is running ${DRUPAL_VERSION}"
    echo ""
    echo "  Every check below would compare this project's code against a core it was"
    echo "  not resolved against, so its findings could not be trusted. Run"
    echo "  'composer install' (a previous one probably failed, often on credentials in"
    echo "  auth.json) and audit again."
    echo ""

    if [ "${ALLOW_VERSION_DRIFT:-0}" = "1" ]; then
        echo -e "${YELLOW}[WARN]${NC} Continuing anyway: ALLOW_VERSION_DRIFT=1"
        echo "  This run cannot certify a pass. The drift is recorded in environment.json."
        echo ""
        return 0
    fi

    echo "  Set ALLOW_VERSION_DRIFT=1 to run anyway."
    exit 3
}

# Main detection flow
main() {
    check_ddev
    echo ""

    detect_drupal || true
    detect_nextjs || true
    echo ""

    if [ "$PROJECT_TYPE" == "unknown" ]; then
        echo -e "${RED}[ERROR]${NC} Could not detect project type"
        echo "  Please ensure you're in a Drupal or Next.js project directory"
        exit 1
    fi

    if [ "$PROJECT_TYPE" == "drupal" ] || [ "$PROJECT_TYPE" == "monorepo" ]; then
        check_custom_paths
        check_version_drift
    fi

    setup_report_dir
    echo ""

    # Determine if environment is ready
    # Drupal requires DDEV, Next.js does not
    if [ "$PROJECT_TYPE" == "nextjs" ]; then
        ENV_READY="true"
    elif [ "$DDEV_AVAILABLE" == "true" ] && [ "$PROJECT_TYPE" != "unknown" ]; then
        ENV_READY="true"
    fi

    # Export environment variables
    export PROJECT_TYPE
    export PROJECT_ROOT
    export DRUPAL_ROOT
    export NEXTJS_ROOT
    export DDEV_AVAILABLE
    export ENV_READY

    # Save to JSON for other scripts
    cat > "${REPORT_DIR}/environment.json" << EOF
{
  "project_type": "${PROJECT_TYPE}",
  "project_root": "${PROJECT_ROOT}",
  "drupal_root": "${DRUPAL_ROOT}",
  "nextjs_root": "${NEXTJS_ROOT}",
  "drupal_modules_path": "${DRUPAL_MODULES_PATH}",
  "drupal_themes_path": "${DRUPAL_THEMES_PATH}",
  "ddev_available": ${DDEV_AVAILABLE},
  "env_ready": ${ENV_READY},
  "report_dir": "${REPORT_DIR}",
  "version_drift": "${VERSION_DRIFT}",
  "version_drift_reason": "${VERSION_DRIFT_REASON}",
  "composer_lock_core_version": "${COMPOSER_LOCK_CORE_VERSION}",
  "installed_core_version": "${DRUPAL_VERSION}",
  "detected_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

    # The record is written BEFORE the stop, so the reason for the stop survives it.
    # full-audit.sh reads version_drift back from this file: on a hard stop to say what
    # actually happened instead of blaming the environment, and on an override to cap
    # the verdict at "warning" through the same vocabulary a gate uses when it could not
    # cover its ground.
    enforce_version_drift

    echo "=== Environment Summary ==="
    echo "Project Type: ${PROJECT_TYPE}"
    echo "Project Root: ${PROJECT_ROOT}"
    [ -n "$DRUPAL_ROOT" ] && echo "Drupal Root: ${DRUPAL_ROOT}"
    [ -n "$NEXTJS_ROOT" ] && echo "Next.js Root: ${NEXTJS_ROOT}"
    echo "DDEV Available: ${DDEV_AVAILABLE}"
    echo "Environment Ready: ${ENV_READY}"
    echo ""

    if [ "$ENV_READY" == "true" ]; then
        echo -e "${GREEN}Environment is ready for code quality audit${NC}"
        exit 0
    else
        echo -e "${YELLOW}Environment needs setup before audit${NC}"
        exit 1
    fi
}

# Executed, not sourced. The guard is correct on its own merits and the file should have
# it; it is NOT why core/path-resolve.sh exists, and reading it that way would be a
# mistake a later edit could act on. It suppresses main() and nothing above it: `set -e`
# at the top, the banner, the report-dir.sh source and every global assignment all still
# land in a shell that sources this file. That is the reason two pure path functions were
# extracted downward instead.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
