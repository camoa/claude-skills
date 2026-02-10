#!/bin/bash
#
# Error Handler Library
# Provides intelligent error messages with recovery guidance
#
# Usage: source scripts/core/error-handler.sh
#        handle_error $? "command-name" "$error_output"
#

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Error handler function
handle_error() {
  local exit_code="$1"
  local command="$2"
  local error_output="${3:-}"

  # Exit code 0 means success, no error handling needed
  if [ "$exit_code" -eq 0 ]; then
    return 0
  fi

  echo -e "${RED}❌ Error: Command failed${NC}"
  echo -e "${RED}   Command: $command${NC}"
  echo -e "${RED}   Exit code: $exit_code${NC}"
  echo ""

  # Analyze error and provide context-specific guidance
  case $exit_code in
    127)
      # Command not found
      echo -e "${YELLOW}💡 Suggested fixes:${NC}"
      echo -e "${YELLOW}   1. Run setup: /code-quality:setup${NC}"
      echo -e "${YELLOW}   2. Install missing tool manually${NC}"
      echo -e "${YELLOW}   3. Check PATH configuration${NC}"
      echo ""
      echo -e "${BLUE}📖 See: references/troubleshooting.md#command-not-found${NC}"
      ;;

    1)
      # Generic error - try to parse error output for common patterns
      if echo "$error_output" | grep -qi "php version\|php.*required"; then
        echo -e "${YELLOW}💡 PHP version mismatch${NC}"
        echo -e "${YELLOW}   Suggested fixes:${NC}"
        echo -e "${YELLOW}   1. Update DDEV PHP version in .ddev/config.yaml${NC}"
        echo -e "${YELLOW}   2. Run: ddev restart${NC}"
        echo ""
        echo -e "${BLUE}📖 See: references/troubleshooting.md#php-version-mismatch${NC}"

      elif echo "$error_output" | grep -qi "memory\|out of memory\|allowed memory size"; then
        echo -e "${YELLOW}💡 Out of memory${NC}"
        echo -e "${YELLOW}   Suggested fixes:${NC}"
        echo -e "${YELLOW}   1. Increase PHP memory limit in php.ini or .ddev/php.ini${NC}"
        echo -e "${YELLOW}   2. Run smaller subset of checks${NC}"
        echo -e "${YELLOW}   3. Exclude vendor/ directory${NC}"
        echo ""
        echo -e "${BLUE}📖 See: references/troubleshooting.md#memory-issues${NC}"

      elif echo "$error_output" | grep -qi "ddev.*not running\|ddev.*not found"; then
        echo -e "${YELLOW}💡 DDEV not running${NC}"
        echo -e "${YELLOW}   Suggested fixes:${NC}"
        echo -e "${YELLOW}   1. Start DDEV: ddev start${NC}"
        echo -e "${YELLOW}   2. Check DDEV status: ddev status${NC}"
        echo -e "${YELLOW}   3. Reinstall DDEV if needed${NC}"
        echo ""
        echo -e "${BLUE}📖 See: references/troubleshooting.md#ddev-issues${NC}"

      elif echo "$error_output" | grep -qi "node.*not found\|npm.*not found"; then
        echo -e "${YELLOW}💡 Node.js/npm not found${NC}"
        echo -e "${YELLOW}   Suggested fixes:${NC}"
        echo -e "${YELLOW}   1. Install Node.js: https://nodejs.org/${NC}"
        echo -e "${YELLOW}   2. Verify installation: node --version${NC}"
        echo -e "${YELLOW}   3. Add to PATH if needed${NC}"
        echo ""
        echo -e "${BLUE}📖 See: references/troubleshooting.md#nodejs-issues${NC}"

      elif echo "$error_output" | grep -qi "permission denied\|eacces"; then
        echo -e "${YELLOW}💡 Permission denied${NC}"
        echo -e "${YELLOW}   Suggested fixes:${NC}"
        echo -e "${YELLOW}   1. Check file permissions: ls -la${NC}"
        echo -e "${YELLOW}   2. Fix permissions: chmod +x script.sh${NC}"
        echo -e "${YELLOW}   3. Run with sudo if needed (use caution)${NC}"
        echo ""
        echo -e "${BLUE}📖 See: references/troubleshooting.md#permission-issues${NC}"

      elif echo "$error_output" | grep -qi "no tests\|no test files"; then
        echo -e "${YELLOW}💡 No tests found${NC}"
        echo -e "${YELLOW}   Suggested fixes:${NC}"
        echo -e "${YELLOW}   1. Create tests in tests/ directory${NC}"
        echo -e "${YELLOW}   2. Check test naming convention (*Test.php or *.test.js)${NC}"
        echo -e "${YELLOW}   3. Verify test configuration (phpunit.xml or jest.config.js)${NC}"
        echo ""
        echo -e "${BLUE}📖 See: references/troubleshooting.md#no-tests-found${NC}"

      else
        # Generic error
        echo -e "${YELLOW}💡 General troubleshooting:${NC}"
        echo -e "${YELLOW}   1. Check error output above for specific issues${NC}"
        echo -e "${YELLOW}   2. Verify tool installation: /code-quality:setup${NC}"
        echo -e "${YELLOW}   3. Check project configuration${NC}"
        echo ""
        if [ -n "$error_output" ]; then
          echo -e "${RED}Error output:${NC}"
          echo "$error_output" | head -20
          echo ""
        fi
        echo -e "${BLUE}📖 See: references/troubleshooting.md${NC}"
      fi
      ;;

    2)
      # Tool-specific error (often config issues)
      echo -e "${YELLOW}💡 Tool configuration issue${NC}"
      echo -e "${YELLOW}   Suggested fixes:${NC}"
      echo -e "${YELLOW}   1. Check tool configuration files (phpstan.neon, .eslintrc.json, etc.)${NC}"
      echo -e "${YELLOW}   2. Verify .code-quality.json settings${NC}"
      echo -e "${YELLOW}   3. Run: /code-quality:setup to regenerate config${NC}"
      echo ""
      echo -e "${BLUE}📖 See: references/troubleshooting.md#configuration-issues${NC}"
      ;;

    *)
      # Unknown error code
      echo -e "${YELLOW}💡 Unexpected error${NC}"
      echo -e "${YELLOW}   Suggested fixes:${NC}"
      echo -e "${YELLOW}   1. Check error output for details${NC}"
      echo -e "${YELLOW}   2. Verify tool installation${NC}"
      echo -e "${YELLOW}   3. Check project structure${NC}"
      echo ""
      if [ -n "$error_output" ]; then
        echo -e "${RED}Error output:${NC}"
        echo "$error_output" | head -20
        echo ""
      fi
      echo -e "${BLUE}📖 See: references/troubleshooting.md${NC}"
      ;;
  esac

  return "$exit_code"
}

# Export function for use in other scripts
export -f handle_error
