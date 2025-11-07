# Jamf JSON Configuration - Quick Start Guide

## 5-Minute Setup for v2.0

This guide shows the fastest way to deploy JSON-based configuration management for the macOS Upgrade Wrapper using Jamf Pro.

---

## Step 1: Deploy JSON Configuration via Jamf (2 minutes)

### Method A: Files and Processes Payload (Recommended)

1. Go to **Computers → Configuration Profiles → New**
2. **General Tab:**
   - Display Name: `macOS Upgrade Wrapper JSON Configuration`
   - Distribution Method: `Install Automatically`
   - Level: `Computer Level`

3. **Files and Processes:**
   - Click **Configure**
   - Click **Add** under "Files to Deploy"
   - Upload: `com.macjediwizard.eraseinstall.config.json`
   - Destination Path: `/Library/Managed Preferences/`
   - File Permissions: `644`
   - File Owner: `root`
   - File Group: `wheel`

4. **Scope Tab:**
   - Target: `All Computers` (or your specific group)

5. Click **Save**

### Method B: Script Deployment (Alternative)

If you prefer to manage JSON via a Jamf script:

```bash
#!/bin/bash
# Deploy JSON Configuration to Managed Preferences

cat > /Library/Managed\ Preferences/com.macjediwizard.eraseinstall.config.json <<'EOF'
{
  "core_settings": {
    "INSTALLER_OS": "15",
    "MAX_DEFERS": 3,
    "FORCE_TIMEOUT_SECONDS": 259200
  },
  "feature_toggles": {
    "TEST_MODE": false,
    "DEBUG_MODE": false
  },
  "main_dialog": {
    "DIALOG_TITLE": "macOS Upgrade Required"
  }
}
EOF

# Set permissions
chmod 644 /Library/Managed\ Preferences/com.macjediwizard.eraseinstall.config.json
chown root:wheel /Library/Managed\ Preferences/com.macjediwizard.eraseinstall.config.json

echo "✅ JSON configuration deployed"
```

---

## Step 2: Verify Deployment (1 minute)

On any Mac in scope:

```bash
# Check if JSON file exists
ls -la /Library/Managed\ Preferences/com.macjediwizard.eraseinstall.config.json

# Validate JSON syntax
plutil -lint /Library/Managed\ Preferences/com.macjediwizard.eraseinstall.config.json

# Read specific setting
plutil -extract core_settings.INSTALLER_OS raw /Library/Managed\ Preferences/com.macjediwizard.eraseinstall.config.json

# View entire configuration
plutil -p /Library/Managed\ Preferences/com.macjediwizard.eraseinstall.config.json

# Use wrapper's --show-config parameter (BEST METHOD)
sudo /Library/Management/erase-install/erase-install-defer-wrapper.sh --show-config
```

**Expected Output:**
```
15
```

---

## Step 3: Deploy v2.0 Wrapper (2 minutes)

### Update Your Jamf Deployment Script

```bash
#!/bin/bash
# Jamf Policy: Deploy macOS Upgrade Wrapper v2.0

echo "Deploying macOS upgrade wrapper script v2.0..."

# Create directory
mkdir -p /Library/Management/erase-install

# Download v2.0 from GitHub
curl -L -o /Library/Management/erase-install/erase-install-defer-wrapper.sh \
  "https://github.com/MacJediWizard/Jamf-Silent-macOS-Upgrade-Scheduler/releases/download/v2.0.0/erase-install-defer-wrapper.sh"

# Make executable
chmod +x /Library/Management/erase-install/erase-install-defer-wrapper.sh

# Verify deployment
if [ -x "/Library/Management/erase-install/erase-install-defer-wrapper.sh" ]; then
  echo "✅ v2.0 wrapper deployed successfully"

  # Run once to verify config loading
  /Library/Management/erase-install/erase-install-defer-wrapper.sh --help 2>&1 | head -5
else
  echo "❌ ERROR: v2.0 wrapper deployment failed"
  exit 1
fi
```

---

## Common Configurations

### Configuration 1: Standard Deployment (Most Organizations)

```json
{
  "core_settings": {
    "INSTALLER_OS": "15",
    "MAX_DEFERS": 3,
    "MAX_ABORTS": 3,
    "FORCE_TIMEOUT_SECONDS": 259200
  },
  "feature_toggles": {
    "TEST_MODE": false,
    "DEBUG_MODE": false
  },
  "auth_notice": {
    "SHOW_AUTH_NOTICE": true
  }
}
```

### Configuration 2: Aggressive Enforcement (IT/Security Teams)

```json
{
  "core_settings": {
    "INSTALLER_OS": "15",
    "MAX_DEFERS": 1,
    "MAX_ABORTS": 1,
    "FORCE_TIMEOUT_SECONDS": 86400
  },
  "main_dialog": {
    "DIALOG_TITLE": "⚠️ URGENT: Security Update Required"
  }
}
```

### Configuration 3: Flexible Deployment (Standard Users)

```json
{
  "core_settings": {
    "INSTALLER_OS": "15",
    "MAX_DEFERS": 5,
    "MAX_ABORTS": 5,
    "FORCE_TIMEOUT_SECONDS": 604800
  },
  "auth_notice": {
    "SHOW_AUTH_NOTICE": true,
    "AUTH_NOTICE_TIMEOUT": 0
  }
}
```

### Configuration 4: Testing/QA Environment

```json
{
  "core_settings": {
    "INSTALLER_OS": "15",
    "MAX_DEFERS": 99
  },
  "feature_toggles": {
    "TEST_MODE": true,
    "SKIP_OS_VERSION_CHECK": true,
    "DEBUG_MODE": true
  },
  "main_dialog": {
    "DIALOG_TITLE": "[QA TEST] macOS Upgrade"
  }
}
```

---

## Per-Department Configuration

### Strategy: Multiple Configuration Profiles with Different Scopes

#### Profile 1: IT Department (Early Adopters)
- **Profile Name:** `macOS Upgrade Config - IT Department`
- **Scope:** Smart Group "Department - IT"
- **Settings:** Aggressive enforcement (1 defer, 1 day timeout)

#### Profile 2: Finance Department (Conservative)
- **Profile Name:** `macOS Upgrade Config - Finance`
- **Scope:** Smart Group "Department - Finance"
- **Settings:** Flexible enforcement (5 defers, 7 day timeout)

#### Profile 3: All Other Departments (Standard)
- **Profile Name:** `macOS Upgrade Config - Standard`
- **Scope:** Smart Group "All Computers" (Exclude IT and Finance)
- **Settings:** Standard enforcement (3 defers, 3 day timeout)

---

## Testing Configurations with Command-Line Parameters

v2.0 includes command-line parameters for testing configurations before deploying via Jamf.

### Test Custom Configuration Locally

```bash
# Create test JSON
cat > /tmp/test-config.json <<'EOF'
{
  "core_settings": {
    "INSTALLER_OS": "15",
    "MAX_DEFERS": 1
  },
  "feature_toggles": {
    "TEST_MODE": true,
    "DEBUG_MODE": true
  }
}
EOF

# View configuration without running
sudo /Library/Management/erase-install/erase-install-defer-wrapper.sh --config=/tmp/test-config.json --show-config

# Run with test configuration
sudo /Library/Management/erase-install/erase-install-defer-wrapper.sh --config=/tmp/test-config.json
```

### Verify Deployed Configuration

```bash
# Show what configuration is currently loaded
sudo /Library/Management/erase-install/erase-install-defer-wrapper.sh --show-config
```

**Example Output:**
```
=== Current Configuration ===
Configuration Source: managed configuration (Jamf)

Core Settings:
  INSTALLER_OS: 15
  MAX_DEFERS: 3
  MAX_ABORTS: 3
  FORCE_TIMEOUT_SECONDS: 259200

Feature Toggles:
  TEST_MODE: false
  DEBUG_MODE: false
  SKIP_OS_VERSION_CHECK: false
```

### Skip OS Version Check for Testing

```bash
# Test workflow on lower OS version
sudo /Library/Management/erase-install/erase-install-defer-wrapper.sh --test-os-check
```

---

## Instant Settings Changes

### Example: Reduce Deferral Limit Organization-Wide

**Old Way (v1.7.x):**
1. Edit script → Rebuild package → Redeploy → Wait (hours/days)

**New Way (v2.0):**
1. Edit Configuration Profile in Jamf
2. Change `MAX_DEFERS` from `3` to `2`
3. Click **Save**
4. Settings apply on next check-in (minutes)

### How to Change a Setting:

1. **Computers → Configuration Profiles**
2. Find: `macOS Upgrade Wrapper Configuration`
3. Click **Edit**
4. **Application & Custom Settings → Edit**
5. Find setting (e.g., `MAX_DEFERS`)
6. Change value (e.g., `2`)
7. Click **Save**

**Result:** All scoped Macs receive new setting within 15-30 minutes (Jamf check-in interval)

---

## Troubleshooting Commands

### Quick Diagnostics - Use --show-config (BEST METHOD)

```bash
# Display current configuration
sudo /Library/Management/erase-install/erase-install-defer-wrapper.sh --show-config
```

This shows:
- Configuration source (Custom/Managed/Local/Defaults)
- All critical settings
- Feature toggles
- File paths

### Check JSON File Status
```bash
# Check if JSON file exists
ls -la /Library/Managed\ Preferences/com.macjediwizard.eraseinstall.config.json

# Validate JSON syntax
plutil -lint /Library/Managed\ Preferences/com.macjediwizard.eraseinstall.config.json

# View entire JSON
plutil -p /Library/Managed\ Preferences/com.macjediwizard.eraseinstall.config.json

# Extract specific value
plutil -extract core_settings.INSTALLER_OS raw /Library/Managed\ Preferences/com.macjediwizard.eraseinstall.config.json
```

### Force Configuration Update
```bash
# Re-run Jamf check-in
sudo jamf policy

# Check file updated
stat /Library/Managed\ Preferences/com.macjediwizard.eraseinstall.config.json
```

### Check Wrapper Log
```bash
# See configuration source
tail -50 /var/log/erase-install-wrapper.log | grep -i "CONFIG"

# Look for:
# [CONFIG] Found managed JSON configuration
# [CONFIG] Configuration loaded from: managed configuration (Jamf)
```

### Test Custom Configuration
```bash
# Test with local JSON to isolate issues
sudo /Library/Management/erase-install/erase-install-defer-wrapper.sh --config=/tmp/test.json --show-config
```

---

## Best Practices

### 1. Test Before Production

1. Create test Configuration Profile
2. Scope to 1-2 test Macs
3. Verify settings apply correctly
4. Test complete upgrade workflow
5. Expand scope to production

### 2. Use Smart Groups for Scoping

**Example Smart Groups:**

```
Name: macOS Needs Upgrade to 15
Criteria:
  - Operating System Version | less than | 15.0
  - Architecture Type | is | arm64 or x86_64

Name: Department - IT
Criteria:
  - Department | is | Information Technology

Name: macOS Upgrade - Exclude VIPs
Criteria:
  - Building | is | Executive Office
```

### 3. Document Your Configuration

Keep a record of your settings:

```
Organization: Acme Corporation
Profile Name: macOS Upgrade Wrapper Configuration
Last Modified: 2025-11-06
Settings:
  - INSTALLER_OS: 15
  - MAX_DEFERS: 3
  - MAX_ABORTS: 3
  - FORCE_TIMEOUT_SECONDS: 259200 (3 days)
```

### 4. Monitor Deployment

```bash
# Create Extension Attribute to track configuration source
#!/bin/bash
log_line=$(tail -1 /var/log/erase-install-wrapper.log 2>/dev/null | grep "Configuration loaded")

if [[ "$log_line" == *"managed preferences"* ]]; then
    echo "<result>Configuration Profile</result>"
elif [[ "$log_line" == *"script defaults"* ]]; then
    echo "<result>Script Defaults</result>"
else
    echo "<result>Unknown</result>"
fi
```

---

## Migration Checklist

### Moving from v1.7.x to v2.0

- [ ] Document current script settings
- [ ] Create Configuration Profile with matching settings
- [ ] Scope profile to test group (5-10 Macs)
- [ ] Deploy v2.0 wrapper to test group
- [ ] Verify configuration loading from managed preferences
- [ ] Test complete upgrade workflow
- [ ] Expand scope to broader pilot (50-100 Macs)
- [ ] Monitor for issues (1 week)
- [ ] Deploy to production (all Macs)
- [ ] Verify all Macs using Configuration Profile
- [ ] Document new change management process

---

## Support

**Quick Diagnostics:**
1. Run: `sudo /Library/Management/erase-install/erase-install-defer-wrapper.sh --show-config`
2. Check JSON exists: `ls -la /Library/Managed\ Preferences/com.macjediwizard.eraseinstall.config.json`
3. Validate JSON: `plutil -lint /Library/Managed\ Preferences/com.macjediwizard.eraseinstall.config.json`
4. Check wrapper log: `tail -50 /var/log/erase-install-wrapper.log | grep -i CONFIG`
5. Force Jamf update: `sudo jamf policy`

**Still having issues?**
- Test with custom config: `--config=/tmp/test.json --show-config`
- Check for validation warnings in log
- Open GitHub issue with log excerpts and `--show-config` output

---

## Reference Files

- **JSON Template:** `com.macjediwizard.eraseinstall.config.json`
- **Detailed Guide:** `V2.0_JSON_CONFIG_IMPLEMENTATION.md`
- **Testing Checklist:** `V2.0_TESTING_CHECKLIST.md`
- **Main README:** `README.md`

---

**Made with ❤️ by MacJediWizard Consulting, Inc.**
