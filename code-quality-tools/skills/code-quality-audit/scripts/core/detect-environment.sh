#!/bin/bash
# detect-environment.sh - Detect project type and validate environment
# Part of code-quality-audit skill

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
PROJECT_TYPE="unknown"
PROJECT_ROOT="${PWD}"
DRUPAL_ROOT=""
NEXTJS_ROOT=""
DDEV_AVAILABLE="false"
ENV_READY="false"

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

            # Check Drupal version
            if [ -f "${DRUPAL_ROOT}/core/lib/Drupal.php" ]; then
                VERSION=$(grep -oP "const VERSION = '\K[^']+" "${DRUPAL_ROOT}/core/lib/Drupal.php" 2>/dev/null || echo "unknown")
                echo "  Drupal version: ${VERSION}"
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

# Check for custom modules path
check_modules_path() {
    local default_path="${DRUPAL_MODULES_PATH:-web/modules/custom}"

    if [ -d "${default_path}" ]; then
        echo -e "${GREEN}[OK]${NC} Custom modules found at: ${default_path}"
        export DRUPAL_MODULES_PATH="${default_path}"
    elif [ -d "modules/custom" ]; then
        echo -e "${YELLOW}[WARN]${NC} Custom modules at non-standard path: modules/custom"
        export DRUPAL_MODULES_PATH="modules/custom"
    else
        echo -e "${YELLOW}[WARN]${NC} No custom modules directory found"
        echo "  Expected: ${default_path}"
    fi
}

# Create report directory
setup_report_dir() {
    local report_dir="${REPORT_DIR:-.reports}"

    if [ ! -d "${report_dir}" ]; then
        mkdir -p "${report_dir}"
        echo -e "${GREEN}[OK]${NC} Created report directory: ${report_dir}"
    else
        echo -e "${GREEN}[OK]${NC} Report directory exists: ${report_dir}"
    fi

    # Reports quote findings out of the audited source, so the directory must not
    # be committable by accident. This is defence in depth in a repository we do
    # not own: it never aborts the audit, never writes through a symlink, never
    # invents a pattern it cannot write safely, and only ever appends.
    local in_work_tree=""
    in_work_tree="$(git rev-parse --is-inside-work-tree 2>/dev/null || true)"

    if [ "${in_work_tree}" = "true" ]; then
        local gitignore=".gitignore"
        local entry="${report_dir%/}"
        entry="${entry#./}"
        local skip_reason=""

        # Ask git, not this file: the path may already be covered by a parent
        # .gitignore, .git/info/exclude or a global excludesfile, in which case
        # writing anything here would just be a stray edit.
        if [ -z "${entry}" ]; then
            skip_reason="empty"
        elif git check-ignore -q "${report_dir}" 2>/dev/null; then
            skip_reason="already-ignored"
        fi

        # A gitignore entry is a repo-relative pattern, so an absolute REPORT_DIR
        # is deliberately never written: rewriting it into one is not safe to
        # guess. Say so only when it actually sits inside this work tree, where it
        # would otherwise go unprotected. Absolute and outside the tree needs no
        # entry at all, so that case stays silent.
        if [ -z "${skip_reason}" ]; then
            case "${entry}" in
                /*)
                    local top=""
                    top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
                    skip_reason="absolute-outside-work-tree"
                    if [ -n "${top}" ]; then
                        case "${entry}/" in
                            "${top}"/*) skip_reason="absolute-inside-work-tree" ;;
                        esac
                    fi
                    ;;
            esac
        fi

        # REPORT_DIR is interpolated into gitignore's PATTERN language, where
        # * ? [ ] \ are wildcards, a leading # is a comment, a leading ! negates
        # (which would UN-ignore paths), and a trailing space is stripped. Refuse
        # rather than guess an escaping for a value holding any of them.
        if [ -z "${skip_reason}" ]; then
            case "${entry}" in
                *'*'*|*'?'*|*'['*|*']'*|*'\'*|*$'\n'*|'#'*|'!'*|*' ')
                    skip_reason="unsafe-pattern"
                    ;;
            esac
        fi

        # Writing through a symlink would land the entry outside the repository.
        if [ -z "${skip_reason}" ] && [ -L "${gitignore}" ]; then
            skip_reason="symlink"
        fi

        # An existing literal entry may be overridden by a later negation, so git
        # can report the path as not ignored while the line is already there.
        # Appending a duplicate would not help, so scan before writing.
        if [ -z "${skip_reason}" ] && [ -f "${gitignore}" ]; then
            if [ -r "${gitignore}" ]; then
                local line=""
                local trimmed=""
                while IFS= read -r line || [ -n "${line}" ]; do
                    trimmed="${line%$'\r'}"
                    trimmed="${trimmed#/}"
                    trimmed="${trimmed%/}"
                    if [ "${trimmed}" = "${entry}" ]; then
                        skip_reason="already-listed"
                        break
                    fi
                done 2>/dev/null < "${gitignore}" || skip_reason="unreadable"
            else
                skip_reason="unreadable"
            fi
        fi

        if [ -z "${skip_reason}" ]; then
            # Do not glue the entry onto a last line that has no newline.
            local lead=""
            if [ -s "${gitignore}" ] && [ -n "$(tail -c 1 "${gitignore}" 2>/dev/null)" ]; then
                lead=$'\n'
            fi
            # Never fatal. `2>/dev/null` is placed BEFORE the append so a failed
            # redirection stays quiet, and testing it in an `if` keeps `set -e`
            # from killing the whole environment detection over an ignore entry.
            if printf '%s%s/\n' "${lead}" "${entry}" 2>/dev/null >> "${gitignore}"; then
                echo -e "${GREEN}[OK]${NC} Added ${entry}/ to ${gitignore}"
            else
                skip_reason="unwritable"
            fi
        fi

        case "${skip_reason}" in
            ''|already-ignored|already-listed|absolute-outside-work-tree) ;;
            *)
                echo -e "${YELLOW}[WARN]${NC} Could not gitignore ${report_dir} (${skip_reason})"
                echo "  Keep audit reports out of your commits: they can quote matched secrets"
                ;;
        esac
    fi

    export REPORT_DIR="${report_dir}"
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
        check_modules_path
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
  "ddev_available": ${DDEV_AVAILABLE},
  "env_ready": ${ENV_READY},
  "report_dir": "${REPORT_DIR}",
  "detected_at": "$(date -Iseconds)"
}
EOF

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

main "$@"
