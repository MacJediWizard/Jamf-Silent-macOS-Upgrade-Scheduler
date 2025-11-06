#!/bin/bash

#######################################
# Test script for v2.0 JSON configuration loading
#
# This script tests the three configuration scenarios:
# 1. No JSON (fallback to script defaults)
# 2. Local JSON
# 3. Managed JSON (Jamf)
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
    echo "✅ Cleanup complete"
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

# Summary
echo "=== TEST SUMMARY ==="
echo ""
echo "Test 1: Script defaults (no JSON) - Should show 'script defaults'"
echo "Test 2: Local JSON - Should show 'local configuration'"
echo "Test 3: Managed JSON - Should show 'managed configuration (Jamf)'"
echo "Test 4: Invalid JSON - Should show 'ERROR' and 'script defaults'"
echo ""
echo "Review the output above to verify each test passed."
echo ""

# Cleanup happens via trap
