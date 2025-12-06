#!/bin/bash
# install-tools.sh - Install code quality tools via DDEV
# Part of code-quality-audit skill

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="${REPORT_DIR:-./reports/quality}"

echo "=== Code Quality Audit - Install Tools ==="
echo ""

# Load environment if available
if [ -f "${REPORT_DIR}/environment.json" ]; then
    PROJECT_TYPE=$(grep -oP '"project_type":\s*"\K[^"]+' "${REPORT_DIR}/environment.json")
    DDEV_AVAILABLE=$(grep -oP '"ddev_available":\s*\K[^,}]+' "${REPORT_DIR}/environment.json")
else
    echo -e "${YELLOW}[WARN]${NC} Environment not detected. Run detect-environment.sh first."
    PROJECT_TYPE="${PROJECT_TYPE:-drupal}"
    DDEV_AVAILABLE="${DDEV_AVAILABLE:-false}"
fi

# Check DDEV
check_ddev() {
    if [ "$DDEV_AVAILABLE" != "true" ]; then
        if command -v ddev &> /dev/null && ddev describe &> /dev/null; then
            DDEV_AVAILABLE="true"
        else
            echo -e "${RED}[ERROR]${NC} DDEV is not available"
            echo "  Please start DDEV first: ddev start"
            exit 1
        fi
    fi
}

# Install Drupal tools
install_drupal_tools() {
    echo "Installing Drupal code quality tools..."
    echo ""

    # PHPStan with Drupal extension
    echo -e "${YELLOW}[1/6]${NC} Installing PHPStan + Drupal extension..."
    ddev composer require --dev \
        phpstan/phpstan \
        phpstan/extension-installer \
        mglaman/phpstan-drupal \
        phpstan/phpstan-deprecation-rules \
        --no-interaction 2>&1 || {
            echo -e "${YELLOW}[WARN]${NC} PHPStan may already be installed or had issues"
        }

    # PHPMD
    echo -e "${YELLOW}[2/6]${NC} Installing PHPMD..."
    ddev composer require --dev phpmd/phpmd --no-interaction 2>&1 || {
        echo -e "${YELLOW}[WARN]${NC} PHPMD may already be installed or had issues"
    }

    # PHPCPD (systemsdk fork for PHP 8.3+)
    echo -e "${YELLOW}[3/6]${NC} Installing PHPCPD..."
    ddev composer require --dev systemsdk/phpcpd --no-interaction 2>&1 || {
        echo -e "${YELLOW}[WARN]${NC} PHPCPD may already be installed or had issues"
    }

    # drupal-check
    echo -e "${YELLOW}[4/6]${NC} Installing drupal-check..."
    ddev composer require --dev mglaman/drupal-check --no-interaction 2>&1 || {
        echo -e "${YELLOW}[WARN]${NC} drupal-check may already be installed or had issues"
    }

    # Drupal Coder
    echo -e "${YELLOW}[5/6]${NC} Installing Drupal Coder..."
    ddev composer require --dev drupal/coder --no-interaction 2>&1 || {
        echo -e "${YELLOW}[WARN]${NC} Drupal Coder may already be installed or had issues"
    }

    # Check for PCOV
    echo -e "${YELLOW}[6/6]${NC} Checking PCOV extension..."
    if ddev exec php -m 2>/dev/null | grep -q pcov; then
        echo -e "${GREEN}[OK]${NC} PCOV is available"
    else
        echo -e "${YELLOW}[WARN]${NC} PCOV is not installed"
        echo "  Add to .ddev/config.yaml:"
        echo "    webimage_extra_packages:"
        echo "      - php\${DDEV_PHP_VERSION}-pcov"
        echo "  Then run: ddev restart"
    fi

    echo ""
}

# Verify installations
verify_drupal_tools() {
    echo "Verifying tool installations..."
    echo ""

    local tools_status=()
    local all_ok=true

    # PHPStan
    if ddev exec vendor/bin/phpstan --version &> /dev/null; then
        VERSION=$(ddev exec vendor/bin/phpstan --version 2>/dev/null | head -1)
        echo -e "${GREEN}[OK]${NC} PHPStan: ${VERSION}"
        tools_status+=("phpstan:ok")
    else
        echo -e "${RED}[FAIL]${NC} PHPStan not found"
        tools_status+=("phpstan:fail")
        all_ok=false
    fi

    # PHPMD
    if ddev exec vendor/bin/phpmd --version &> /dev/null; then
        VERSION=$(ddev exec vendor/bin/phpmd --version 2>/dev/null | head -1)
        echo -e "${GREEN}[OK]${NC} PHPMD: ${VERSION}"
        tools_status+=("phpmd:ok")
    else
        echo -e "${RED}[FAIL]${NC} PHPMD not found"
        tools_status+=("phpmd:fail")
        all_ok=false
    fi

    # PHPCPD
    if ddev exec vendor/bin/phpcpd --version &> /dev/null; then
        VERSION=$(ddev exec vendor/bin/phpcpd --version 2>/dev/null | head -1)
        echo -e "${GREEN}[OK]${NC} PHPCPD: ${VERSION}"
        tools_status+=("phpcpd:ok")
    else
        echo -e "${RED}[FAIL]${NC} PHPCPD not found"
        tools_status+=("phpcpd:fail")
        all_ok=false
    fi

    # drupal-check
    if ddev exec vendor/bin/drupal-check --version &> /dev/null; then
        VERSION=$(ddev exec vendor/bin/drupal-check --version 2>/dev/null | head -1)
        echo -e "${GREEN}[OK]${NC} drupal-check: ${VERSION}"
        tools_status+=("drupal-check:ok")
    else
        echo -e "${RED}[FAIL]${NC} drupal-check not found"
        tools_status+=("drupal-check:fail")
        all_ok=false
    fi

    # phpcs (Drupal Coder)
    if ddev exec vendor/bin/phpcs --version &> /dev/null; then
        VERSION=$(ddev exec vendor/bin/phpcs --version 2>/dev/null | head -1)
        echo -e "${GREEN}[OK]${NC} PHP_CodeSniffer: ${VERSION}"
        tools_status+=("phpcs:ok")
    else
        echo -e "${RED}[FAIL]${NC} PHP_CodeSniffer not found"
        tools_status+=("phpcs:fail")
        all_ok=false
    fi

    # PHPUnit
    if ddev exec vendor/bin/phpunit --version &> /dev/null; then
        VERSION=$(ddev exec vendor/bin/phpunit --version 2>/dev/null | head -1)
        echo -e "${GREEN}[OK]${NC} PHPUnit: ${VERSION}"
        tools_status+=("phpunit:ok")
    else
        echo -e "${YELLOW}[WARN]${NC} PHPUnit not found (may need drupal/core-dev)"
        tools_status+=("phpunit:warn")
    fi

    echo ""

    # Save tool status
    cat > "${REPORT_DIR}/tools-status.json" << EOF
{
  "installed_at": "$(date -Iseconds)",
  "project_type": "${PROJECT_TYPE}",
  "tools": {
$(printf '    "%s": "%s",\n' "${tools_status[@]}" | sed 's/:\([^"]*\)$/": "\1/' | sed '$ s/,$//')
  },
  "all_ok": ${all_ok}
}
EOF

    if [ "$all_ok" = true ]; then
        echo -e "${GREEN}All tools installed successfully${NC}"
        exit 0
    else
        echo -e "${YELLOW}Some tools failed to install${NC}"
        exit 1
    fi
}

# Install Next.js tools (placeholder for future)
install_nextjs_tools() {
    echo -e "${YELLOW}[INFO]${NC} Next.js tool installation not yet implemented"
    echo "  Manual installation:"
    echo "    npm install -D jest @jest/globals eslint jscpd"
}

# Main
main() {
    check_ddev

    case "$PROJECT_TYPE" in
        drupal|monorepo)
            install_drupal_tools
            verify_drupal_tools
            ;;
        nextjs)
            install_nextjs_tools
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} Unknown project type: ${PROJECT_TYPE}"
            exit 1
            ;;
    esac
}

main "$@"
