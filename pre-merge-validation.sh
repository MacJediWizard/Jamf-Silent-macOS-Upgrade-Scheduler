#!/bin/bash

#######################################
# Pre-Merge Validation Script
# Run this before merging v2.0-dev to main
# Can be run without sudo for basic checks
#######################################

echo "======================================"
echo "v2.0 Pre-Merge Validation"
echo "======================================"
echo ""

ERRORS=0
WARNINGS=0

# Test 1: Bash Syntax
echo "Test 1: Bash Syntax Validation"
echo "-------------------------------"
if bash -n erase-install-defer-wrapper.sh 2>/dev/null; then
    echo "✅ Bash syntax: Valid"
else
    echo "❌ Bash syntax: ERRORS FOUND"
    ((ERRORS++))
fi
echo ""

# Test 2: Script Version
echo "Test 2: Script Version Check"
echo "-----------------------------"
VERSION=$(grep "^SCRIPT_VERSION=" erase-install-defer-wrapper.sh | cut -d'"' -f2)
if [[ "$VERSION" == "2.0.0" ]]; then
    echo "✅ Script version: $VERSION"
else
    echo "⚠️  Script version: $VERSION (expected 2.0.0)"
    ((WARNINGS++))
fi
echo ""

# Test 3: JSON File Validation
echo "Test 3: JSON Configuration Files"
echo "---------------------------------"
JSON_VALID=0
JSON_TOTAL=0

for json in examples/*.json com.macjediwizard.eraseinstall.config.json; do
    ((JSON_TOTAL++))
    if python3 -c "import json; json.load(open('$json'))" 2>/dev/null; then
        echo "✅ $json"
        ((JSON_VALID++))
    else
        echo "❌ $json"
        ((ERRORS++))
    fi
done

if [[ $JSON_VALID -eq $JSON_TOTAL ]]; then
    echo "✅ All JSON files valid ($JSON_VALID/$JSON_TOTAL)"
else
    echo "❌ Some JSON files invalid ($JSON_VALID/$JSON_TOTAL)"
fi
echo ""

# Test 4: plutil Extraction Test
echo "Test 4: plutil Extraction Test"
echo "-------------------------------"
if plutil -extract core_settings.INSTALLER_OS raw examples/config-minimal.json >/dev/null 2>&1; then
    echo "✅ plutil can extract values from JSON"
else
    echo "❌ plutil extraction failed"
    ((ERRORS++))
fi
echo ""

# Test 5: Command-Line Parameters
echo "Test 5: Command-Line Parameters"
echo "--------------------------------"
if ./erase-install-defer-wrapper.sh --version 2>&1 | grep -q "v2.0.0"; then
    echo "✅ --version parameter working"
else
    echo "❌ --version parameter not working"
    ((ERRORS++))
fi

if ./erase-install-defer-wrapper.sh --help 2>&1 | grep -q "Usage:"; then
    echo "✅ --help parameter working"
else
    echo "❌ --help parameter not working"
    ((ERRORS++))
fi
echo ""

# Test 6: File Permissions
echo "Test 6: File Permissions"
echo "------------------------"
if [[ -x "test-json-config.sh" ]]; then
    echo "✅ test-json-config.sh is executable"
else
    echo "⚠️  test-json-config.sh not executable (chmod +x needed)"
    ((WARNINGS++))
fi

if [[ -x "erase-install-defer-wrapper.sh" ]]; then
    echo "✅ erase-install-defer-wrapper.sh is executable"
else
    echo "⚠️  erase-install-defer-wrapper.sh not executable (chmod +x needed)"
    ((WARNINGS++))
fi
echo ""

# Test 7: Git Status
echo "Test 7: Git Repository Status"
echo "------------------------------"
if git diff --quiet; then
    echo "✅ Working tree clean"
else
    echo "⚠️  Uncommitted changes detected"
    ((WARNINGS++))
fi

CURRENT_BRANCH=$(git branch --show-current)
echo "Current branch: $CURRENT_BRANCH"

COMMITS_AHEAD=$(git rev-list --count main..v2.0-dev 2>/dev/null || echo "0")
echo "Commits ahead of main: $COMMITS_AHEAD"
echo ""

# Test 8: Documentation Files
echo "Test 8: Documentation Files"
echo "----------------------------"
DOCS=(
    "README.md"
    "V2.0_JSON_CONFIG_IMPLEMENTATION.md"
    "JAMF_CONFIG_PROFILE_QUICK_START.md"
    "V2.0_TESTING_CHECKLIST.md"
    "V2.0_DEVELOPMENT_COMPLETE.md"
    "V2.0_FEATURE_SUMMARY.md"
    "examples/README.md"
)

DOC_COUNT=0
for doc in "${DOCS[@]}"; do
    if [[ -f "$doc" ]]; then
        ((DOC_COUNT++))
    else
        echo "⚠️  Missing: $doc"
        ((WARNINGS++))
    fi
done
echo "✅ Documentation files present: $DOC_COUNT/${#DOCS[@]}"
echo ""

# Test 9: Example Configurations
echo "Test 9: Example Configurations"
echo "-------------------------------"
EXAMPLES=(
    "examples/config-minimal.json"
    "examples/config-production.json"
    "examples/config-testing.json"
    "examples/config-aggressive.json"
    "examples/config-flexible.json"
)

EXAMPLE_COUNT=0
for example in "${EXAMPLES[@]}"; do
    if [[ -f "$example" ]]; then
        ((EXAMPLE_COUNT++))
    else
        echo "⚠️  Missing: $example"
        ((WARNINGS++))
    fi
done
echo "✅ Example configs present: $EXAMPLE_COUNT/${#EXAMPLES[@]}"
echo ""

# Summary
echo "======================================"
echo "Validation Summary"
echo "======================================"
echo ""
echo "Errors: $ERRORS"
echo "Warnings: $WARNINGS"
echo ""

if [[ $ERRORS -eq 0 ]]; then
    echo "✅ PRE-MERGE VALIDATION PASSED"
    echo ""
    echo "All basic validation checks passed!"
    echo ""
    echo "RECOMMENDED NEXT STEPS:"
    echo "1. If you have sudo access, run: sudo ./test-json-config.sh"
    echo "2. Or merge to main and test on a test Mac"
    echo "3. v2.0 is backwards compatible (no JSON = v1.7.3 behavior)"
    echo ""
    exit 0
else
    echo "❌ PRE-MERGE VALIDATION FAILED"
    echo ""
    echo "Please fix errors before merging to main"
    echo ""
    exit 1
fi
