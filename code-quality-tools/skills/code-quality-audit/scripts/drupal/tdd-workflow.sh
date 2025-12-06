#!/bin/bash
# tdd-workflow.sh - TDD helper with watch mode
# Part of code-quality-audit skill

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DRUPAL_MODULES_PATH="${DRUPAL_MODULES_PATH:-web/modules/custom}"

# Parse arguments
ACTION="${1:-help}"
TEST_FILE="${2:-}"
WATCH_MODE="${3:-}"

show_help() {
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║               TDD Workflow Helper                            ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Usage: tdd-workflow.sh <action> [test-file] [--watch]"
    echo ""
    echo "Actions:"
    echo "  red      - Run test (should fail)"
    echo "  green    - Run test (should pass)"
    echo "  refactor - Run test after refactoring"
    echo "  cycle    - Full RED-GREEN-REFACTOR cycle"
    echo "  watch    - Watch mode with inotifywait"
    echo "  help     - Show this help"
    echo ""
    echo "Examples:"
    echo "  tdd-workflow.sh red tests/src/Unit/MyServiceTest.php"
    echo "  tdd-workflow.sh green"
    echo "  tdd-workflow.sh watch tests/src/Unit/"
    echo ""
    echo "TDD Cycle:"
    echo "  1. ${RED}RED${NC}:      Write failing test first"
    echo "  2. ${GREEN}GREEN${NC}:    Write minimal code to pass"
    echo "  3. ${BLUE}REFACTOR${NC}: Clean up, keep green"
    echo ""
}

# Check DDEV
check_ddev() {
    if ! ddev describe &> /dev/null; then
        echo -e "${RED}[ERROR]${NC} DDEV is not running"
        exit 1
    fi
}

# Run PHPUnit
run_test() {
    local filter=""
    if [ -n "$TEST_FILE" ]; then
        filter="--filter $(basename "$TEST_FILE" .php)"
    fi

    echo "Running: ddev exec vendor/bin/phpunit $filter"
    echo ""

    set +e
    ddev exec vendor/bin/phpunit $filter
    local exit_code=$?
    set -e

    return $exit_code
}

# RED phase - test should fail
phase_red() {
    echo ""
    echo -e "${RED}╔══════════════════════════════════════╗${NC}"
    echo -e "${RED}║           RED PHASE                  ║${NC}"
    echo -e "${RED}║   Test should FAIL at this point     ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════╝${NC}"
    echo ""

    if run_test; then
        echo ""
        echo -e "${YELLOW}[UNEXPECTED]${NC} Test passed! In RED phase, tests should fail."
        echo "  - Did you write the test before the implementation?"
        echo "  - Is this testing new functionality?"
        return 1
    else
        echo ""
        echo -e "${GREEN}[OK]${NC} Test failed as expected. RED phase complete."
        echo ""
        echo "Next step: Write minimal code to make it pass (GREEN phase)"
        echo "  Run: tdd-workflow.sh green $TEST_FILE"
        return 0
    fi
}

# GREEN phase - test should pass
phase_green() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          GREEN PHASE                 ║${NC}"
    echo -e "${GREEN}║   Test should PASS at this point     ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
    echo ""

    if run_test; then
        echo ""
        echo -e "${GREEN}[OK]${NC} Test passed! GREEN phase complete."
        echo ""
        echo "Next step: Refactor while keeping tests green"
        echo "  Run: tdd-workflow.sh refactor $TEST_FILE"
        return 0
    else
        echo ""
        echo -e "${RED}[FAIL]${NC} Test still failing. Keep working on implementation."
        echo "  - Write minimal code to pass"
        echo "  - Don't over-engineer yet"
        return 1
    fi
}

# REFACTOR phase - test should still pass
phase_refactor() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        REFACTOR PHASE                ║${NC}"
    echo -e "${BLUE}║  Improve code, tests should PASS     ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
    echo ""

    if run_test; then
        echo ""
        echo -e "${GREEN}[OK]${NC} Tests still passing after refactor!"
        echo ""
        echo "Refactoring tips:"
        echo "  - Remove duplication (DRY)"
        echo "  - Improve naming"
        echo "  - Extract methods/classes (SRP)"
        echo "  - Add type hints"
        echo ""
        echo "When done, start new RED phase for next feature"
        return 0
    else
        echo ""
        echo -e "${RED}[FAIL]${NC} Refactoring broke the test!"
        echo "  - Undo refactoring changes"
        echo "  - Try smaller refactoring steps"
        return 1
    fi
}

# Full cycle
full_cycle() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║               TDD Cycle Guide                                ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Step 1: ${RED}RED${NC} - Write a failing test"
    echo "  - Focus on WHAT, not HOW"
    echo "  - Test one behavior at a time"
    echo "  - Use descriptive test names"
    echo ""
    echo "Step 2: ${GREEN}GREEN${NC} - Make it pass"
    echo "  - Write minimal code"
    echo "  - Don't optimize yet"
    echo "  - It's OK to be \"ugly\""
    echo ""
    echo "Step 3: ${BLUE}REFACTOR${NC} - Clean up"
    echo "  - Remove duplication"
    echo "  - Improve names"
    echo "  - Run tests frequently"
    echo ""
    echo "Repeat for each new behavior!"
    echo ""

    echo "Running current test suite status..."
    run_test || true
}

# Watch mode
watch_mode() {
    local watch_path="${TEST_FILE:-${DRUPAL_MODULES_PATH}}"

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║               TDD Watch Mode                                 ║"
    echo "║   Tests run automatically on file changes                    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Watching: ${watch_path}"
    echo "Press Ctrl+C to stop"
    echo ""

    # Check for inotifywait
    if ! command -v inotifywait &> /dev/null; then
        echo -e "${YELLOW}[WARN]${NC} inotifywait not found"
        echo "  Install with: apt-get install inotify-tools"
        echo ""
        echo "Falling back to polling mode (checks every 2 seconds)..."
        echo ""

        # Polling fallback
        local last_hash=""
        while true; do
            local current_hash=$(find "$watch_path" -name "*.php" -exec md5sum {} \; 2>/dev/null | md5sum)
            if [ "$current_hash" != "$last_hash" ]; then
                if [ -n "$last_hash" ]; then
                    echo ""
                    echo "=== File change detected ==="
                    run_test || true
                fi
                last_hash="$current_hash"
            fi
            sleep 2
        done
    else
        # Watch with inotifywait
        while true; do
            inotifywait -q -e modify,create,delete -r "$watch_path" --include '\.php$'
            echo ""
            echo "=== File change detected ==="
            run_test || true
        done
    fi
}

# Main
main() {
    case "$ACTION" in
        red)
            check_ddev
            phase_red
            ;;
        green)
            check_ddev
            phase_green
            ;;
        refactor)
            check_ddev
            phase_refactor
            ;;
        cycle)
            check_ddev
            full_cycle
            ;;
        watch)
            check_ddev
            watch_mode
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}Unknown action: ${ACTION}${NC}"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
