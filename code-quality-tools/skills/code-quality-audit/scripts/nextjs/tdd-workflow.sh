#!/bin/bash
# tdd-workflow.sh - TDD workflow support for Next.js projects (Jest)
# Part of code-quality-audit skill

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPORT_DIR="${REPORT_DIR:-.reports}"

# Check for npm
if ! command -v npm &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} npm is not installed"
    exit 2
fi

# Check for Jest
if ! npx jest --version &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Jest is not installed"
    echo "  Run: npm install -D jest @jest/globals"
    exit 1
fi

usage() {
    echo "TDD Workflow - RED-GREEN-REFACTOR with Jest"
    echo ""
    echo "Usage: $0 <phase> [test-file]"
    echo ""
    echo "Phases:"
    echo "  red       Run test expecting failure (write test first)"
    echo "  green     Run test expecting pass (minimal implementation)"
    echo "  refactor  Run test ensuring it stays green (clean up code)"
    echo "  watch     Start Jest in watch mode (continuous TDD)"
    echo "  single    Run a single test file"
    echo ""
    echo "Examples:"
    echo "  $0 red src/utils/calculator.test.ts"
    echo "  $0 green src/utils/calculator.test.ts"
    echo "  $0 watch"
    echo ""
    echo "TDD Cycle Target: 20-40 cycles per hour"
}

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

PHASE=$1
TEST_FILE=$2

case "$PHASE" in
    red)
        echo -e "${RED}╔══════════════════════════════════════╗${NC}"
        echo -e "${RED}║          TDD PHASE: RED              ║${NC}"
        echo -e "${RED}║   Write a failing test first         ║${NC}"
        echo -e "${RED}╚══════════════════════════════════════╝${NC}"
        echo ""

        if [ -z "$TEST_FILE" ]; then
            echo -e "${YELLOW}[INFO]${NC} Running all tests..."
            set +e
            npx jest --no-coverage
            RESULT=$?
            set -e
        else
            echo "Running: $TEST_FILE"
            set +e
            npx jest "$TEST_FILE" --no-coverage
            RESULT=$?
            set -e
        fi

        echo ""
        if [ $RESULT -ne 0 ]; then
            echo -e "${GREEN}[OK]${NC} Test fails as expected - RED phase complete"
            echo ""
            echo "Next: Write minimal code to make the test pass"
            echo "Then run: $0 green $TEST_FILE"
        else
            echo -e "${YELLOW}[WARN]${NC} Test passed! In RED phase, test should fail first."
            echo ""
            echo "Either:"
            echo "  - Your test is not testing new functionality"
            echo "  - The implementation already exists"
            echo "  - Write a more specific test that fails"
        fi
        ;;

    green)
        echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║         TDD PHASE: GREEN             ║${NC}"
        echo -e "${GREEN}║   Write minimal code to pass         ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
        echo ""

        if [ -z "$TEST_FILE" ]; then
            echo -e "${YELLOW}[INFO]${NC} Running all tests..."
            set +e
            npx jest --no-coverage
            RESULT=$?
            set -e
        else
            echo "Running: $TEST_FILE"
            set +e
            npx jest "$TEST_FILE" --no-coverage
            RESULT=$?
            set -e
        fi

        echo ""
        if [ $RESULT -eq 0 ]; then
            echo -e "${GREEN}[OK]${NC} Test passes - GREEN phase complete"
            echo ""
            echo "Next: Refactor while keeping tests green"
            echo "Then run: $0 refactor $TEST_FILE"
        else
            echo -e "${RED}[FAIL]${NC} Test still fails"
            echo ""
            echo "Write just enough code to make the test pass."
            echo "Don't over-engineer - keep it minimal!"
        fi
        ;;

    refactor)
        echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║       TDD PHASE: REFACTOR            ║${NC}"
        echo -e "${BLUE}║   Clean up, tests must stay green    ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
        echo ""

        if [ -z "$TEST_FILE" ]; then
            echo -e "${YELLOW}[INFO]${NC} Running all tests..."
            set +e
            npx jest --no-coverage
            RESULT=$?
            set -e
        else
            echo "Running: $TEST_FILE"
            set +e
            npx jest "$TEST_FILE" --no-coverage
            RESULT=$?
            set -e
        fi

        echo ""
        if [ $RESULT -eq 0 ]; then
            echo -e "${GREEN}[OK]${NC} Tests still pass - REFACTOR phase complete"
            echo ""
            echo "Refactoring suggestions:"
            echo "  - Extract methods for clarity"
            echo "  - Rename for better readability"
            echo "  - Remove duplication"
            echo "  - Simplify conditionals"
            echo ""
            echo "Ready for next cycle: $0 red [new-test]"
        else
            echo -e "${RED}[FAIL]${NC} Refactoring broke the tests!"
            echo ""
            echo "Revert your changes and try a smaller refactoring step."
            echo "Tests must stay green during refactoring."
        fi
        ;;

    watch)
        echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║       TDD: WATCH MODE                ║${NC}"
        echo -e "${BLUE}║   Continuous testing                 ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
        echo ""
        echo "Starting Jest in watch mode..."
        echo "Press 'q' to quit, 'a' to run all tests"
        echo ""

        npx jest --watch --no-coverage
        ;;

    single)
        if [ -z "$TEST_FILE" ]; then
            echo -e "${RED}[ERROR]${NC} Please specify a test file"
            echo "Usage: $0 single path/to/test.spec.ts"
            exit 1
        fi

        echo "Running single test: $TEST_FILE"
        echo ""
        npx jest "$TEST_FILE" --verbose --no-coverage
        ;;

    *)
        echo -e "${RED}[ERROR]${NC} Unknown phase: $PHASE"
        echo ""
        usage
        exit 1
        ;;
esac
