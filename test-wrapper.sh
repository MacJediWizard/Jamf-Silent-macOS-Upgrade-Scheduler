#!/bin/bash

################################################################################
# test-wrapper.sh - Basic Testing Suite for erase-install-defer-wrapper
#
# Created for Issue #20
# Tests basic functionality, security features, and configuration loading
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test results array
declare -a FAILED_TESTS

################################################################################
# Helper Functions
################################################################################

log_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
    FAILED_TESTS+=("$1")
}

run_test() {
    ((TESTS_RUN++))
    log_test "$1"
}

################################################################################
# Test Categories
################################################################################

test_script_syntax() {
    echo ""
    echo "=========================================="
    echo "CATEGORY: Script Syntax Validation"
    echo "=========================================="

    run_test "Bash syntax validation"
    if bash -n erase-install-defer-wrapper.sh 2>/dev/null; then
        log_pass "Bash syntax is valid"
    else
        log_fail "Bash syntax errors detected"
    fi
}

test_security_functions() {
    echo ""
    echo "=========================================="
    echo "CATEGORY: Security Functions"
    echo "=========================================="

    run_test "verify_package_integrity() function exists"
    if grep -q "^verify_package_integrity()" erase-install-defer-wrapper.sh; then
        log_pass "verify_package_integrity() function found"
    else
        log_fail "verify_package_integrity() function not found"
    fi

    run_test "install_daemon_secure() function exists"
    if grep -q "^install_daemon_secure()" erase-install-defer-wrapper.sh; then
        log_pass "install_daemon_secure() function found"
    else
        log_fail "install_daemon_secure() function not found"
    fi

    run_test "create_secure_temp_dir() function exists"
    if grep -q "^create_secure_temp_dir()" erase-install-defer-wrapper.sh; then
        log_pass "create_secure_temp_dir() function found"
    else
        log_fail "create_secure_temp_dir() function not found"
    fi

    run_test "kill_process_safely() function exists"
    if grep -q "^kill_process_safely()" erase-install-defer-wrapper.sh; then
        log_pass "kill_process_safely() function found"
    else
        log_fail "kill_process_safely() function not found"
    fi

    run_test "validate_path() function exists"
    if grep -q "^validate_path()" erase-install-defer-wrapper.sh; then
        log_pass "validate_path() function found"
    else
        log_fail "validate_path() function not found"
    fi

    run_test "acquire_lock() uses flock"
    if grep -q "flock.*lock_fd" erase-install-defer-wrapper.sh; then
        log_pass "acquire_lock() uses flock for atomic locking"
    else
        log_fail "acquire_lock() does not use flock"
    fi
}

test_error_handling() {
    echo ""
    echo "=========================================="
    echo "CATEGORY: Error Handling"
    echo "=========================================="

    run_test "set -euo pipefail is enabled"
    if head -20 erase-install-defer-wrapper.sh | grep -q "^set -euo pipefail"; then
        log_pass "Strict error handling enabled"
    else
        log_fail "set -euo pipefail not found"
    fi

    run_test "error_handler() function exists"
    if grep -q "^error_handler()" erase-install-defer-wrapper.sh; then
        log_pass "error_handler() function found"
    else
        log_fail "error_handler() function not found"
    fi

    run_test "ERR trap is set"
    if grep -q "trap.*ERR" erase-install-defer-wrapper.sh; then
        log_pass "ERR trap configured"
    else
        log_fail "ERR trap not found"
    fi
}

test_configuration() {
    echo ""
    echo "=========================================="
    echo "CATEGORY: Configuration Management"
    echo "=========================================="

    run_test "load_json_config() function exists"
    if grep -q "^load_json_config()" erase-install-defer-wrapper.sh; then
        log_pass "load_json_config() function found"
    else
        log_fail "load_json_config() function not found"
    fi

    run_test "JSON config file exists"
    if [ -f "com.macjediwizard.eraseinstall.config.json" ]; then
        log_pass "JSON config file found"
    else
        log_fail "JSON config file not found"
    fi

    run_test "JSON config syntax is valid"
    if python3 -m json.tool com.macjediwizard.eraseinstall.config.json >/dev/null 2>&1; then
        log_pass "JSON config syntax is valid"
    else
        log_fail "JSON config has syntax errors"
    fi
}

test_command_line_params() {
    echo ""
    echo "=========================================="
    echo "CATEGORY: Command-Line Parameters"
    echo "=========================================="

    run_test "Command-line argument processing code exists"
    if grep -q "Command-line Argument Processing" erase-install-defer-wrapper.sh; then
        log_pass "Command-line argument processing found"
    else
        log_fail "Command-line argument processing not found"
    fi

    run_test "--version parameter code exists"
    if grep -q "\-\-version" erase-install-defer-wrapper.sh; then
        log_pass "--version parameter code found"
    else
        log_fail "--version parameter code not found"
    fi

    run_test "--help parameter code exists"
    if grep -q "\-\-help" erase-install-defer-wrapper.sh; then
        log_pass "--help parameter code found"
    else
        log_fail "--help parameter code not found"
    fi

    # Note: Actual execution tests skipped to avoid script initialization
    # which requires root privileges and may modify system state
}

test_code_quality() {
    echo ""
    echo "=========================================="
    echo "CATEGORY: Code Quality"
    echo "=========================================="

    run_test "get_console_user() function exists"
    if grep -q "^get_console_user()" erase-install-defer-wrapper.sh; then
        log_pass "get_console_user() function found (Issue #15)"
    else
        log_fail "get_console_user() function not found"
    fi

    run_test "Time constants defined"
    if grep -q "readonly SECONDS_PER_MINUTE=" erase-install-defer-wrapper.sh; then
        log_pass "Time constants defined (Issue #19)"
    else
        log_fail "Time constants not found"
    fi

    run_test "apply_branding() function exists"
    if grep -q "^apply_branding()" erase-install-defer-wrapper.sh; then
        log_pass "apply_branding() function found (Issue #12)"
    else
        log_fail "apply_branding() function not found"
    fi
}

test_validation_script() {
    echo ""
    echo "=========================================="
    echo "CATEGORY: Validation Script"
    echo "=========================================="

    run_test "pre-merge-validation.sh exists"
    if [ -f "pre-merge-validation.sh" ]; then
        log_pass "Validation script found"
    else
        log_fail "Validation script not found"
    fi

    run_test "pre-merge-validation.sh is executable"
    if [ -x "pre-merge-validation.sh" ]; then
        log_pass "Validation script is executable"
    else
        log_fail "Validation script is not executable"
    fi
}

################################################################################
# Run All Tests
################################################################################

main() {
    echo "################################################################################"
    echo "# erase-install-defer-wrapper Testing Suite"
    echo "# Issue #20 - v2.1 Basic Testing"
    echo "################################################################################"
    echo ""

    # Verify we're in the right directory
    if [ ! -f "erase-install-defer-wrapper.sh" ]; then
        echo -e "${RED}ERROR: erase-install-defer-wrapper.sh not found in current directory${NC}"
        exit 1
    fi

    # Run all test categories
    test_script_syntax
    test_security_functions
    test_error_handling
    test_configuration
    test_command_line_params
    test_code_quality
    test_validation_script

    # Summary
    echo ""
    echo "=========================================="
    echo "TEST SUMMARY"
    echo "=========================================="
    echo "Tests Run:    $TESTS_RUN"
    echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"

    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
        echo ""
        echo "Failed Tests:"
        for test in "${FAILED_TESTS[@]}"; do
            echo -e "  ${RED}✗${NC} $test"
        done
        echo ""
        exit 1
    else
        echo -e "Tests Failed: ${GREEN}0${NC}"
        echo ""
        echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
        echo ""
        exit 0
    fi
}

# Run tests
main "$@"
