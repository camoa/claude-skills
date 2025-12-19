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
REPORT_DIR="${REPORT_DIR:-.reports}"

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
    echo -e "${YELLOW}[1/12]${NC} Installing PHPStan + Drupal extension..."
    ddev composer require --dev \
        phpstan/phpstan \
        phpstan/extension-installer \
        mglaman/phpstan-drupal \
        phpstan/phpstan-deprecation-rules \
        --no-interaction 2>&1 || {
            echo -e "${YELLOW}[WARN]${NC} PHPStan may already be installed or had issues"
        }

    # PHPMD
    echo -e "${YELLOW}[2/12]${NC} Installing PHPMD..."
    ddev composer require --dev phpmd/phpmd --no-interaction 2>&1 || {
        echo -e "${YELLOW}[WARN]${NC} PHPMD may already be installed or had issues"
    }

    # PHPCPD (systemsdk fork for PHP 8.3+)
    echo -e "${YELLOW}[3/12]${NC} Installing PHPCPD..."
    ddev composer require --dev systemsdk/phpcpd --no-interaction 2>&1 || {
        echo -e "${YELLOW}[WARN]${NC} PHPCPD may already be installed or had issues"
    }

    # Drupal Coder
    echo -e "${YELLOW}[4/12]${NC} Installing Drupal Coder..."
    ddev composer require --dev drupal/coder --no-interaction 2>&1 || {
        echo -e "${YELLOW}[WARN]${NC} Drupal Coder may already be installed or had issues"
    }

    # Drupal Rector (auto-fix deprecations)
    echo -e "${YELLOW}[5/12]${NC} Installing Drupal Rector..."
    ddev composer require --dev palantirnet/drupal-rector --no-interaction 2>&1 || {
        echo -e "${YELLOW}[WARN]${NC} Drupal Rector may already be installed or had issues"
    }

    # Check for jq (required for JSON processing)
    echo -e "${YELLOW}[6/12]${NC} Checking jq dependency..."
    if command -v jq &> /dev/null; then
        echo -e "${GREEN}[OK]${NC} jq is available"
    else
        echo -e "${YELLOW}[WARN]${NC} jq is not installed"
        echo "  Install with: apt-get install jq (Linux) or brew install jq (macOS)"
    fi

    # Check for PCOV
    echo -e "${YELLOW}[7/12]${NC} Checking PCOV extension..."
    if ddev exec php -m 2>/dev/null | grep -q pcov; then
        echo -e "${GREEN}[OK]${NC} PCOV is available"
    else
        echo -e "${YELLOW}[WARN]${NC} PCOV is not installed"
        echo "  Add to .ddev/config.yaml:"
        echo "    webimage_extra_packages:"
        echo "      - php\${DDEV_PHP_VERSION}-pcov"
        echo "  Then run: ddev restart"
    fi

    # Psalm (Security - Taint Analysis) - RECOMMENDED
    echo -e "${YELLOW}[8/12]${NC} Installing Psalm (taint analysis - recommended for security)..."
    ddev composer require --dev vimeo/psalm --no-interaction 2>&1 || {
        echo -e "${YELLOW}[WARN]${NC} Psalm may already be installed or had issues"
    }

    # php-security-linter (OWASP/CIS Security Rules) - RECOMMENDED
    echo -e "${YELLOW}[9/13]${NC} Installing php-security-linter (OWASP/CIS - recommended)..."
    ddev composer require --dev yousha/php-security-linter --no-interaction 2>&1 || {
        echo -e "${YELLOW}[WARN]${NC} php-security-linter may already be installed or had issues"
    }

    # Roave Security Advisories (Composer Prevention Layer) - RECOMMENDED
    echo -e "${YELLOW}[10/13]${NC} Installing Roave Security Advisories (vulnerability prevention)..."
    ddev composer require --dev roave/security-advisories:dev-master --no-interaction 2>&1 || {
        echo -e "${YELLOW}[INFO]${NC} Roave Security Advisories prevents vulnerable package installation"
        echo -e "${YELLOW}[INFO]${NC} If installation conflicts, you may have vulnerable packages installed"
    }

    # Semgrep (Multi-language SAST) - RECOMMENDED
    echo -e "${YELLOW}[11/13]${NC} Installing Semgrep (multi-language SAST)..."
    if ddev exec semgrep --version &> /dev/null; then
        echo -e "${GREEN}[OK]${NC} Semgrep already installed"
    else
        ddev exec pip3 install semgrep 2>&1 || {
            echo -e "${YELLOW}[WARN]${NC} Semgrep installation failed - install manually: pip3 install semgrep"
        }
    fi

    # Trivy (Dependency/Container/Secret Scanner) - RECOMMENDED
    echo -e "${YELLOW}[12/13]${NC} Installing Trivy (dependency/secret scanner)..."
    if command -v trivy &> /dev/null; then
        echo -e "${GREEN}[OK]${NC} Trivy already installed"
    else
        echo -e "${YELLOW}[INFO]${NC} Installing Trivy..."
        # Install Trivy binary for host system
        curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin 2>&1 || {
            echo -e "${YELLOW}[WARN]${NC} Trivy installation failed - install manually:"
            echo "  See: https://aquasecurity.github.io/trivy/latest/getting-started/installation/"
        }
    fi

    # Gitleaks (Secret Detection) - RECOMMENDED
    echo -e "${YELLOW}[13/13]${NC} Installing Gitleaks (secret detection)..."
    if command -v gitleaks &> /dev/null; then
        echo -e "${GREEN}[OK]${NC} Gitleaks already installed"
    else
        echo -e "${YELLOW}[INFO]${NC} Installing Gitleaks..."
        # Install Gitleaks binary for host system
        curl -sfL https://raw.githubusercontent.com/gitleaks/gitleaks/master/scripts/install.sh | sh -s -- -b /usr/local/bin 2>&1 || {
            echo -e "${YELLOW}[WARN]${NC} Gitleaks installation failed - install manually:"
            echo "  See: https://github.com/gitleaks/gitleaks#installation"
        }
    fi

    echo ""
    echo -e "${BLUE}[OPTIONAL]${NC} Security Review module (Drupal config audit):"
    echo "  ddev composer require drupal/security_review"
    echo "  ddev drush pm:enable security_review"
    echo ""
    echo -e "${BLUE}[OPTIONAL]${NC} Roave Security Advisories (blocks vulnerable packages):"
    echo "  ddev composer require --dev roave/security-advisories:dev-latest"
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

    # Psalm (Security - Optional)
    if ddev exec vendor/bin/psalm --version &> /dev/null; then
        VERSION=$(ddev exec vendor/bin/psalm --version 2>/dev/null | head -1)
        echo -e "${GREEN}[OK]${NC} Psalm: ${VERSION}"
        tools_status+=("psalm:ok")
    else
        echo -e "${YELLOW}[OPTIONAL]${NC} Psalm not found (recommended for security taint analysis)"
        tools_status+=("psalm:optional")
    fi

    # php-security-linter (Optional)
    if ddev exec vendor/bin/php-security-linter --version &> /dev/null; then
        VERSION=$(ddev exec vendor/bin/php-security-linter --version 2>/dev/null | head -1)
        echo -e "${GREEN}[OK]${NC} php-security-linter: ${VERSION}"
        tools_status+=("php-security-linter:ok")
    else
        echo -e "${YELLOW}[OPTIONAL]${NC} php-security-linter not found (recommended for OWASP security checks)"
        tools_status+=("php-security-linter:optional")
    fi

    # Roave Security Advisories (Optional)
    if ddev composer show roave/security-advisories &> /dev/null; then
        echo -e "${GREEN}[OK]${NC} Roave Security Advisories: installed (prevents vulnerable packages)"
        tools_status+=("roave:ok")
    else
        echo -e "${YELLOW}[OPTIONAL]${NC} Roave Security Advisories not found (prevents vulnerable package installation)"
        tools_status+=("roave:optional")
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

    # Rector (drupal-rector)
    if ddev exec vendor/bin/rector --version &> /dev/null; then
        VERSION=$(ddev exec vendor/bin/rector --version 2>/dev/null | head -1)
        echo -e "${GREEN}[OK]${NC} Rector: ${VERSION}"
        tools_status+=("rector:ok")
    else
        echo -e "${YELLOW}[WARN]${NC} Rector not found"
        tools_status+=("rector:warn")
    fi

    # Semgrep (Multi-language SAST)
    if ddev exec semgrep --version &> /dev/null; then
        VERSION=$(ddev exec semgrep --version 2>/dev/null | head -1)
        echo -e "${GREEN}[OK]${NC} Semgrep: ${VERSION}"
        tools_status+=("semgrep:ok")
    else
        echo -e "${YELLOW}[OPTIONAL]${NC} Semgrep not found (recommended for cross-stack SAST)"
        tools_status+=("semgrep:optional")
    fi

    # Trivy (Dependency/Secret Scanner)
    if command -v trivy &> /dev/null; then
        VERSION=$(trivy --version 2>/dev/null | head -1)
        echo -e "${GREEN}[OK]${NC} Trivy: ${VERSION}"
        tools_status+=("trivy:ok")
    else
        echo -e "${YELLOW}[OPTIONAL]${NC} Trivy not found (recommended for dependency/secret scanning)"
        tools_status+=("trivy:optional")
    fi

    # Gitleaks (Secret Detection)
    if command -v gitleaks &> /dev/null; then
        VERSION=$(gitleaks version 2>/dev/null)
        echo -e "${GREEN}[OK]${NC} Gitleaks: ${VERSION}"
        tools_status+=("gitleaks:ok")
    else
        echo -e "${YELLOW}[OPTIONAL]${NC} Gitleaks not found (recommended for secret detection)"
        tools_status+=("gitleaks:optional")
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

# Install Next.js tools
install_nextjs_tools() {
    echo "Installing Next.js code quality tools..."
    echo ""

    # Check for npm
    if ! command -v npm &> /dev/null; then
        echo -e "${RED}[ERROR]${NC} npm is not installed"
        echo "  Please install Node.js first: https://nodejs.org/"
        exit 1
    fi

    # ESLint with Next.js config + security plugins
    echo -e "${YELLOW}[1/11]${NC} Installing ESLint + Next.js config + security plugins..."
    npm install -D eslint eslint-config-next @typescript-eslint/eslint-plugin \
        eslint-plugin-react-hooks eslint-config-prettier \
        eslint-plugin-security eslint-plugin-no-secrets 2>&1 || {
        echo -e "${YELLOW}[WARN]${NC} ESLint may already be installed or had issues"
    }

    # Jest + Testing Library
    echo -e "${YELLOW}[2/11]${NC} Installing Jest + Testing Library..."
    npm install -D jest @jest/globals jest-environment-jsdom \
        @testing-library/react @testing-library/jest-dom 2>&1 || {
        echo -e "${YELLOW}[WARN]${NC} Jest may already be installed or had issues"
    }

    # jscpd for duplication detection
    echo -e "${YELLOW}[3/11]${NC} Installing jscpd..."
    npm install -D jscpd 2>&1 || {
        echo -e "${YELLOW}[WARN]${NC} jscpd may already be installed or had issues"
    }

    # madge for circular dependency detection (SOLID check)
    echo -e "${YELLOW}[4/11]${NC} Installing madge (circular dependency detection)..."
    npm install -D madge 2>&1 || {
        echo -e "${YELLOW}[WARN]${NC} madge may already be installed or had issues"
    }

    # TypeScript (if not already present)
    echo -e "${YELLOW}[5/11]${NC} Checking TypeScript..."
    if [ -f "tsconfig.json" ]; then
        echo -e "${GREEN}[OK]${NC} TypeScript already configured"
    else
        npm install -D typescript @types/node @types/react 2>&1 || {
            echo -e "${YELLOW}[WARN]${NC} TypeScript may already be installed or had issues"
        }
    fi

    # Check for jq (required for JSON processing)
    echo -e "${YELLOW}[6/11]${NC} Checking jq dependency..."
    if command -v jq &> /dev/null; then
        echo -e "${GREEN}[OK]${NC} jq is available"
    else
        echo -e "${YELLOW}[WARN]${NC} jq is not installed"
        echo "  Install with: apt-get install jq (Linux) or brew install jq (macOS)"
    fi

    # Semgrep (Multi-language SAST) - RECOMMENDED
    echo -e "${YELLOW}[7/11]${NC} Installing Semgrep (multi-language SAST)..."
    if command -v semgrep &> /dev/null; then
        echo -e "${GREEN}[OK]${NC} Semgrep already installed"
    else
        # Try pip3 first, fallback to npm
        if command -v pip3 &> /dev/null; then
            pip3 install semgrep 2>&1 || {
                echo -e "${YELLOW}[WARN]${NC} Semgrep pip3 installation failed, trying npm..."
                npm install -g @semgrep/cli 2>&1 || {
                    echo -e "${YELLOW}[WARN]${NC} Semgrep installation failed - install manually: pip3 install semgrep"
                }
            }
        else
            echo -e "${YELLOW}[INFO]${NC} pip3 not found, using npm..."
            npm install -g @semgrep/cli 2>&1 || {
                echo -e "${YELLOW}[WARN]${NC} Semgrep installation failed - install manually: pip3 install semgrep"
            }
        fi
    fi

    # Trivy (Dependency/Container/Secret Scanner) - RECOMMENDED
    echo -e "${YELLOW}[8/11]${NC} Installing Trivy (dependency/secret scanner)..."
    if command -v trivy &> /dev/null; then
        echo -e "${GREEN}[OK]${NC} Trivy already installed"
    else
        echo -e "${YELLOW}[INFO]${NC} Installing Trivy..."
        curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin 2>&1 || {
            echo -e "${YELLOW}[WARN]${NC} Trivy installation failed - install manually:"
            echo "  See: https://aquasecurity.github.io/trivy/latest/getting-started/installation/"
        }
    fi

    # Gitleaks (Secret Detection) - RECOMMENDED
    echo -e "${YELLOW}[9/11]${NC} Installing Gitleaks (secret detection)..."
    if command -v gitleaks &> /dev/null; then
        echo -e "${GREEN}[OK]${NC} Gitleaks already installed"
    else
        echo -e "${YELLOW}[INFO]${NC} Installing Gitleaks..."
        curl -sfL https://raw.githubusercontent.com/gitleaks/gitleaks/master/scripts/install.sh | sh -s -- -b /usr/local/bin 2>&1 || {
            echo -e "${YELLOW}[WARN]${NC} Gitleaks installation failed - install manually:"
            echo "  See: https://github.com/gitleaks/gitleaks#installation"
        }
    fi

    # Socket CLI (Supply Chain Security) - RECOMMENDED
    echo -e "${YELLOW}[10/11]${NC} Installing Socket CLI (supply chain attack detection)..."
    npm install -D @socketsecurity/cli 2>&1 || {
        echo -e "${YELLOW}[WARN]${NC} Socket CLI may already be installed or had issues"
    }

    # Setup complete message
    echo -e "${YELLOW}[11/11]${NC} Installation complete!"
    echo ""

    echo ""
    verify_nextjs_tools
}

# Verify Next.js tools
verify_nextjs_tools() {
    echo "Verifying tool installations..."
    echo ""

    local tools_status=()
    local all_ok=true

    # ESLint
    if npx eslint --version &> /dev/null; then
        VERSION=$(npx eslint --version 2>/dev/null)
        echo -e "${GREEN}[OK]${NC} ESLint: ${VERSION}"
        tools_status+=("eslint:ok")
    else
        echo -e "${RED}[FAIL]${NC} ESLint not found"
        tools_status+=("eslint:fail")
        all_ok=false
    fi

    # Jest
    if npx jest --version &> /dev/null; then
        VERSION=$(npx jest --version 2>/dev/null)
        echo -e "${GREEN}[OK]${NC} Jest: ${VERSION}"
        tools_status+=("jest:ok")
    else
        echo -e "${RED}[FAIL]${NC} Jest not found"
        tools_status+=("jest:fail")
        all_ok=false
    fi

    # jscpd
    if npx jscpd --version &> /dev/null; then
        VERSION=$(npx jscpd --version 2>/dev/null)
        echo -e "${GREEN}[OK]${NC} jscpd: ${VERSION}"
        tools_status+=("jscpd:ok")
    else
        echo -e "${RED}[FAIL]${NC} jscpd not found"
        tools_status+=("jscpd:fail")
        all_ok=false
    fi

    # madge (SOLID check)
    if npx madge --version &> /dev/null; then
        VERSION=$(npx madge --version 2>/dev/null)
        echo -e "${GREEN}[OK]${NC} madge: ${VERSION}"
        tools_status+=("madge:ok")
    else
        echo -e "${RED}[FAIL]${NC} madge not found"
        tools_status+=("madge:fail")
        all_ok=false
    fi

    # TypeScript
    if npx tsc --version &> /dev/null; then
        VERSION=$(npx tsc --version 2>/dev/null)
        echo -e "${GREEN}[OK]${NC} TypeScript: ${VERSION}"
        tools_status+=("typescript:ok")
    else
        echo -e "${YELLOW}[WARN]${NC} TypeScript not found"
        tools_status+=("typescript:warn")
    fi

    # Semgrep (Multi-language SAST)
    if command -v semgrep &> /dev/null; then
        VERSION=$(semgrep --version 2>/dev/null | head -1)
        echo -e "${GREEN}[OK]${NC} Semgrep: ${VERSION}"
        tools_status+=("semgrep:ok")
    else
        echo -e "${YELLOW}[OPTIONAL]${NC} Semgrep not found (recommended for security scanning)"
        tools_status+=("semgrep:optional")
    fi

    # Trivy (Dependency/Secret Scanner)
    if command -v trivy &> /dev/null; then
        VERSION=$(trivy --version 2>/dev/null | head -1)
        echo -e "${GREEN}[OK]${NC} Trivy: ${VERSION}"
        tools_status+=("trivy:ok")
    else
        echo -e "${YELLOW}[OPTIONAL]${NC} Trivy not found (recommended for dependency/secret scanning)"
        tools_status+=("trivy:optional")
    fi

    # Gitleaks (Secret Detection)
    if command -v gitleaks &> /dev/null; then
        VERSION=$(gitleaks version 2>/dev/null)
        echo -e "${GREEN}[OK]${NC} Gitleaks: ${VERSION}"
        tools_status+=("gitleaks:ok")
    else
        echo -e "${YELLOW}[OPTIONAL]${NC} Gitleaks not found (recommended for secret detection)"
        tools_status+=("gitleaks:optional")
    fi

    # Socket CLI (Supply Chain Security)
    if npx socket-npm --version &> /dev/null 2>&1; then
        VERSION=$(npx socket-npm --version 2>/dev/null)
        echo -e "${GREEN}[OK]${NC} Socket CLI: ${VERSION}"
        tools_status+=("socket:ok")
    else
        echo -e "${YELLOW}[OPTIONAL]${NC} Socket CLI not found (recommended for supply chain attack detection)"
        tools_status+=("socket:optional")
    fi

    echo ""

    # Create reports directory
    mkdir -p "${REPORT_DIR}"

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

# Main
main() {
    case "$PROJECT_TYPE" in
        drupal|monorepo)
            check_ddev
            install_drupal_tools
            verify_drupal_tools
            ;;
        nextjs)
            # Next.js doesn't need DDEV
            install_nextjs_tools
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} Unknown project type: ${PROJECT_TYPE}"
            exit 1
            ;;
    esac
}

main "$@"
