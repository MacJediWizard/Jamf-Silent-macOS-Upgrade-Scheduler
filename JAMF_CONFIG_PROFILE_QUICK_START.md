# Jamf Configuration Profile - Quick Start Guide

## 5-Minute Setup for v2.0

This guide shows the fastest way to deploy Configuration Profile management for the macOS Upgrade Wrapper.

---

## Step 1: Upload Configuration Profile to Jamf (2 minutes)

### Method A: Upload Existing Plist (Recommended)

1. Go to **Computers → Configuration Profiles → New**
2. **General Tab:**
   - Display Name: `macOS Upgrade Wrapper Configuration`
   - Distribution Method: `Install Automatically`
   - Level: `Computer Level`

3. **Application & Custom Settings:**
   - Click **Configure**
   - Click **Upload** (paperclip icon)
   - Select: `com.macjediwizard.eraseinstall.config.example.plist`
   - Click **Upload**

4. **Scope Tab:**
   - Target: `All Computers` (or your specific group)

5. Click **Save**

### Method B: Manual Entry (If you prefer)

1. **Application & Custom Settings:**
   - Click **Configure**
   - Preference Domain: `com.macjediwizard.eraseinstall.config`
   - Click **Add** for each setting:

   | Key | Type | Value |
   |-----|------|-------|
   | INSTALLER_OS | String | 15 |
   | MAX_DEFERS | Integer | 3 |
   | MAX_ABORTS | Integer | 3 |
   | TEST_MODE | Boolean | false |
   | DEBUG_MODE | Boolean | false |
   | DIALOG_TITLE | String | macOS Upgrade Required |

   *(See example plist for complete settings list)*

---

## Step 2: Verify Deployment (1 minute)

On any Mac in scope:

```bash
# Check if profile installed
sudo profiles list | grep macjediwizard

# Read settings
sudo defaults read /Library/Managed\ Preferences/com.macjediwizard.eraseinstall.config

# Test specific setting
sudo defaults read /Library/Managed\ Preferences/com.macjediwizard.eraseinstall.config INSTALLER_OS
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

```xml
<key>INSTALLER_OS</key>
<string>15</string>

<key>MAX_DEFERS</key>
<integer>3</integer>

<key>MAX_ABORTS</key>
<integer>3</integer>

<key>FORCE_TIMEOUT_SECONDS</key>
<integer>259200</integer>  <!-- 3 days -->

<key>TEST_MODE</key>
<false/>

<key>DEBUG_MODE</key>
<false/>

<key>SHOW_AUTH_NOTICE</key>
<true/>
```

### Configuration 2: Aggressive Enforcement (IT/Security Teams)

```xml
<key>MAX_DEFERS</key>
<integer>1</integer>

<key>MAX_ABORTS</key>
<integer>1</integer>

<key>FORCE_TIMEOUT_SECONDS</key>
<integer>86400</integer>  <!-- 1 day -->

<key>DIALOG_TITLE</key>
<string>⚠️ URGENT: Security Update Required</string>
```

### Configuration 3: Flexible Deployment (Standard Users)

```xml
<key>MAX_DEFERS</key>
<integer>5</integer>

<key>MAX_ABORTS</key>
<integer>5</integer>

<key>FORCE_TIMEOUT_SECONDS</key>
<integer>604800</integer>  <!-- 7 days -->

<key>SHOW_AUTH_NOTICE</key>
<true/>

<key>AUTH_NOTICE_TIMEOUT</key>
<integer>0</integer>  <!-- No timeout -->
```

### Configuration 4: Testing/QA Environment

```xml
<key>TEST_MODE</key>
<true/>

<key>SKIP_OS_VERSION_CHECK</key>
<true/>

<key>DEBUG_MODE</key>
<true/>

<key>MAX_DEFERS</key>
<integer>99</integer>

<key>DIALOG_TITLE</key>
<string>[QA TEST] macOS Upgrade</string>
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

### Check Profile Status
```bash
# List all configuration profiles
sudo profiles list

# Show specific profile
sudo profiles show | grep -A 20 macjediwizard
```

### Check Settings
```bash
# View all managed settings
sudo defaults read /Library/Managed\ Preferences/com.macjediwizard.eraseinstall.config

# Check specific setting
sudo defaults read /Library/Managed\ Preferences/com.macjediwizard.eraseinstall.config INSTALLER_OS
```

### Force Profile Update
```bash
# Re-run Jamf check-in
sudo jamf policy

# Or force specific policy
sudo jamf policy -id <policy_id>
```

### Check Wrapper Log
```bash
# See configuration source
tail -50 /var/log/erase-install-wrapper.log | grep "Configuration loaded"

# Should show:
# [INFO] Configuration loaded from managed preferences (Configuration Profile)
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

**If settings aren't applying:**
1. Check profile installed: `sudo profiles list | grep macjediwizard`
2. Check managed prefs exist: `ls /Library/Managed\ Preferences/`
3. Check wrapper log: `tail /var/log/erase-install-wrapper.log`
4. Force Jamf update: `sudo jamf policy`

**Still having issues?**
- Open GitHub issue with log excerpts
- Include output of troubleshooting commands above

---

## Reference Files

- **Example Plist:** `com.macjediwizard.eraseinstall.config.example.plist`
- **Detailed Guide:** `V2.0_CONFIG_PROFILE_IMPLEMENTATION.md`
- **Main README:** `README.md`

---

**Made with ❤️ by MacJediWizard Consulting, Inc.**
