#!/bin/bash

#######################################
# Test script for v2.0 JSON configuration loading
#
# This script tests the configuration scenarios:
# 1. No JSON (fallback to script defaults)
# 2. Local JSON
# 3. Managed JSON (Jamf)
# 4. Invalid JSON (error handling)
# 5. Custom JSON (--config parameter)
# 6. --show-config parameter
# 7. Configuration priority order
# 8. Configuration validation
#######################################

echo "=== v2.0 JSON Configuration Loading Test ==="
echo ""

# Cleanup function
cleanup_test() {
    echo ""
    echo "Cleaning up test files..."
    sudo rm -f "/Library/Managed Preferences/com.macjediwizard.eraseinstall.config.json"
    sudo rm -f "/Library/Preferences/com.macjediwizard.eraseinstall.config.json"
    sudo rm -f "/var/log/erase-install-wrapper.log"
    sudo rm -f "/tmp/test-config.json"
    sudo rm -f "/tmp/managed-config.json"
    sudo rm -f "/tmp/invalid-config.json"
    sudo rm -f "/tmp/custom-config.json"
    sudo rm -f "/tmp/validation-test.json"
    echo "✅ Cleanup complete"
}

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Test result function
test_result() {
    local test_name="$1"
    local result="$2"

    if [[ "$result" == "PASS" ]]; then
        echo "✅ $test_name: PASSED"
        ((TESTS_PASSED++))
    else
        echo "❌ $test_name: FAILED"
        ((TESTS_FAILED++))
    fi
}

# Set trap to cleanup on exit
trap cleanup_test EXIT

# Test 1: No JSON (Script Defaults)
echo "TEST 1: No JSON Files (Script Defaults)"
echo "=========================================="
cleanup_test

# Create minimal test JSON for validation
cat > /tmp/test-config.json <<'EOF'
{
  "core_settings": {
    "INSTALLER_OS": "15",
    "MAX_DEFERS": 3
  },
  "feature_toggles": {
    "TEST_MODE": true,
    "DEBUG_MODE": false
  }
}
EOF

# Validate JSON syntax
if plutil -lint /tmp/test-config.json > /dev/null 2>&1; then
    echo "✅ Test JSON syntax is valid"
else
    echo "❌ Test JSON syntax is invalid"
    exit 1
fi

echo ""
echo "Expected: Script defaults from User Configuration Section"
echo "Running wrapper in help mode to trigger config loading..."
echo ""

# Run wrapper with --help to see config loading (won't execute full script)
sudo ./erase-install-defer-wrapper.sh 2>&1 | head -20 | grep -E "CONFIG|Starting|Configuration"

echo ""
echo ""

# Test 2: Local JSON
echo "TEST 2: Local JSON Configuration"
echo "================================="
echo "Creating local JSON at /Library/Preferences/..."

sudo mkdir -p "/Library/Preferences"
sudo cp /tmp/test-config.json "/Library/Preferences/com.macjediwizard.eraseinstall.config.json"
sudo chmod 644 "/Library/Preferences/com.macjediwizard.eraseinstall.config.json"

echo "Expected: Load from local JSON"
echo "Running wrapper to test config loading..."
echo ""

sudo ./erase-install-defer-wrapper.sh 2>&1 | head -20 | grep -E "CONFIG|Starting|Configuration"

echo ""
echo ""

# Test 3: Managed JSON (Jamf)
echo "TEST 3: Managed JSON Configuration (Jamf Simulation)"
echo "====================================================="
echo "Creating managed JSON at /Library/Managed Preferences/..."

sudo mkdir -p "/Library/Managed Preferences"

# Create managed JSON with different values to verify it takes priority
cat > /tmp/managed-config.json <<'EOF'
{
  "core_settings": {
    "INSTALLER_OS": "16",
    "MAX_DEFERS": 5
  },
  "feature_toggles": {
    "TEST_MODE": true,
    "DEBUG_MODE": true
  }
}
EOF

sudo cp /tmp/managed-config.json "/Library/Managed Preferences/com.macjediwizard.eraseinstall.config.json"
sudo chmod 644 "/Library/Managed Preferences/com.macjediwizard.eraseinstall.config.json"

echo "Expected: Load from managed JSON (takes priority over local)"
echo "Running wrapper to test config loading..."
echo ""

sudo ./erase-install-defer-wrapper.sh 2>&1 | head -20 | grep -E "CONFIG|Starting|Configuration"

echo ""
echo ""

# Test 4: Invalid JSON
echo "TEST 4: Invalid JSON Syntax (Fallback Test)"
echo "============================================"

# Create invalid JSON
cat > /tmp/invalid-config.json <<'EOF'
{
  "core_settings": {
    "INSTALLER_OS": "15",
    "MAX_DEFERS": 3
  // Missing closing brace - invalid JSON
EOF

sudo cp /tmp/invalid-config.json "/Library/Managed Preferences/com.macjediwizard.eraseinstall.config.json"

echo "Expected: Detect invalid JSON, fall back to script defaults"
echo "Running wrapper to test error handling..."
echo ""

sudo ./erase-install-defer-wrapper.sh 2>&1 | head -20 | grep -E "CONFIG|Starting|Configuration|ERROR"

echo ""
echo ""

# Test 5: Custom JSON with --config parameter
echo "TEST 5: Custom JSON (--config parameter)"
echo "========================================="

# Create custom config with unique values
cat > /tmp/custom-config.json <<'EOF'
{
  "core_settings": {
    "INSTALLER_OS": "14",
    "MAX_DEFERS": 7
  },
  "feature_toggles": {
    "TEST_MODE": true,
    "DEBUG_MODE": true
  }
}
EOF

echo "Creating custom JSON with INSTALLER_OS=14, MAX_DEFERS=7"
echo "Expected: Custom config takes priority over managed and local"
echo "Running wrapper with --config parameter..."
echo ""

OUTPUT=$(sudo ./erase-install-defer-wrapper.sh --config=/tmp/custom-config.json 2>&1 | head -30)
echo "$OUTPUT" | grep -E "CONFIG|Starting|Configuration"

if echo "$OUTPUT" | grep -q "custom configuration"; then
    test_result "Test 5: Custom JSON via --config" "PASS"
else
    test_result "Test 5: Custom JSON via --config" "FAIL"
fi

echo ""
echo ""

# Test 6: --show-config parameter
echo "TEST 6: --show-config Parameter"
echo "================================"

echo "Testing --show-config parameter..."
echo "Expected: Display configuration and exit without running"
echo ""

OUTPUT=$(sudo ./erase-install-defer-wrapper.sh --show-config 2>&1)
echo "$OUTPUT"

if echo "$OUTPUT" | grep -q "=== Current Configuration ===" && echo "$OUTPUT" | grep -q "Configuration Source:"; then
    test_result "Test 6: --show-config parameter" "PASS"
else
    test_result "Test 6: --show-config parameter" "FAIL"
fi

echo ""
echo ""

# Test 7: Configuration Priority Order
echo "TEST 7: Configuration Priority Order"
echo "====================================="

echo "Testing 4-tier priority: Custom > Managed > Local > Defaults"
echo ""

# Clean all configs first
sudo rm -f "/Library/Managed Preferences/com.macjediwizard.eraseinstall.config.json"
sudo rm -f "/Library/Preferences/com.macjediwizard.eraseinstall.config.json"

# Create local with INSTALLER_OS=16
cat > /tmp/local-test.json <<'EOF'
{
  "core_settings": {
    "INSTALLER_OS": "16"
  }
}
EOF
sudo cp /tmp/local-test.json "/Library/Preferences/com.macjediwizard.eraseinstall.config.json"

# Create managed with INSTALLER_OS=15
cat > /tmp/managed-test.json <<'EOF'
{
  "core_settings": {
    "INSTALLER_OS": "15"
  }
}
EOF
sudo cp /tmp/managed-test.json "/Library/Managed Preferences/com.macjediwizard.eraseinstall.config.json"

# Create custom with INSTALLER_OS=14
cat > /tmp/custom-test.json <<'EOF'
{
  "core_settings": {
    "INSTALLER_OS": "14"
  }
}
EOF

echo "7a. Testing with custom (14) + managed (15) + local (16)..."
OUTPUT=$(sudo ./erase-install-defer-wrapper.sh --config=/tmp/custom-test.json --show-config 2>&1)
if echo "$OUTPUT" | grep -q "INSTALLER_OS: 14"; then
    test_result "Test 7a: Custom priority (highest)" "PASS"
else
    test_result "Test 7a: Custom priority (highest)" "FAIL"
fi

echo "7b. Testing with managed (15) + local (16) only..."
OUTPUT=$(sudo ./erase-install-defer-wrapper.sh --show-config 2>&1)
if echo "$OUTPUT" | grep -q "INSTALLER_OS: 15"; then
    test_result "Test 7b: Managed priority (over local)" "PASS"
else
    test_result "Test 7b: Managed priority (over local)" "FAIL"
fi

echo "7c. Testing with local (16) only..."
sudo rm -f "/Library/Managed Preferences/com.macjediwizard.eraseinstall.config.json"
OUTPUT=$(sudo ./erase-install-defer-wrapper.sh --show-config 2>&1)
if echo "$OUTPUT" | grep -q "INSTALLER_OS: 16"; then
    test_result "Test 7c: Local priority (over defaults)" "PASS"
else
    test_result "Test 7c: Local priority (over defaults)" "FAIL"
fi

echo ""
echo ""

# Test 8: Configuration Validation
echo "TEST 8: Configuration Validation"
echo "================================="

# Create JSON with invalid values
cat > /tmp/validation-test.json <<'EOF'
{
  "core_settings": {
    "INSTALLER_OS": "abc",
    "MAX_DEFERS": -1,
    "MAX_ABORTS": "invalid"
  }
}
EOF

echo "Creating config with invalid values (INSTALLER_OS='abc', MAX_DEFERS=-1)"
echo "Expected: Warnings logged, defaults used"
echo ""

OUTPUT=$(sudo ./erase-install-defer-wrapper.sh --config=/tmp/validation-test.json --show-config 2>&1)

echo "$OUTPUT" | grep -i "WARNING"
echo ""

if echo "$OUTPUT" | grep -q "WARNING"; then
    test_result "Test 8: Configuration validation" "PASS"
else
    test_result "Test 8: Configuration validation" "FAIL"
fi

echo ""
echo ""

# Summary
echo "========================================"
echo "=== TEST SUMMARY ==="
echo "========================================"
echo ""
echo "Tests Passed: $TESTS_PASSED"
echo "Tests Failed: $TESTS_FAILED"
echo ""
echo "Test 1: Script defaults (no JSON) - Should show 'script defaults'"
echo "Test 2: Local JSON - Should show 'local configuration'"
echo "Test 3: Managed JSON - Should show 'managed configuration (Jamf)'"
echo "Test 4: Invalid JSON - Should show 'ERROR' and 'script defaults'"
echo "Test 5: Custom JSON (--config) - Should show 'custom configuration'"
echo "Test 6: --show-config - Should display configuration and exit"
echo "Test 7: Priority Order - Custom > Managed > Local > Defaults"
echo "Test 8: Validation - Should warn on invalid values and use defaults"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✅ ALL TESTS PASSED!"
    exit 0
else
    echo "❌ SOME TESTS FAILED - Review output above"
    exit 1
fi

# Cleanup happens via trap
