# Example Configurations

This directory contains example JSON configuration files for different deployment scenarios.

## 📁 Available Examples

### `config-minimal.json`
**Use Case:** Quick start, minimal configuration
**Description:** Only sets essential values (INSTALLER_OS, MAX_DEFERS), uses defaults for everything else
**Best For:** Testing, simple deployments

```bash
# Test with minimal config
sudo /Library/Management/erase-install/erase-install-defer-wrapper.sh --config=examples/config-minimal.json --show-config
```

---

### `config-production.json`
**Use Case:** Standard enterprise production deployment
**Description:** Balanced settings with 3 deferrals, 3-day timeout, auth notice enabled
**Best For:** Most organizations, standard deployment

**Key Settings:**
- MAX_DEFERS: 3
- FORCE_TIMEOUT_SECONDS: 259200 (3 days)
- MAX_ABORTS: 3
- SHOW_AUTH_NOTICE: true

---

### `config-aggressive.json`
**Use Case:** IT/Security teams, critical security updates
**Description:** Minimal deferrals (1), short timeout (24 hours), urgent messaging
**Best For:** Security-critical updates, early adopter groups

**Key Settings:**
- MAX_DEFERS: 1
- FORCE_TIMEOUT_SECONDS: 86400 (1 day)
- MAX_ABORTS: 1
- Dialog title includes ⚠️ URGENT warning

---

### `config-flexible.json`
**Use Case:** Standard users with flexible schedules
**Description:** Extended deferrals (5), long timeout (7 days), friendly messaging
**Best For:** Creative teams, users with flexible deadlines

**Key Settings:**
- MAX_DEFERS: 5
- FORCE_TIMEOUT_SECONDS: 604800 (7 days)
- MAX_ABORTS: 5
- Friendly dialog messaging

---

### `config-testing.json`
**Use Case:** QA/Testing environments
**Description:** Test mode enabled, no reboots, unlimited deferrals, debug logging
**Best For:** Testing workflows, QA validation, development

**Key Settings:**
- TEST_MODE: true
- DEBUG_MODE: true
- PREVENT_ALL_REBOOTS: true
- SKIP_OS_VERSION_CHECK: true
- MAX_DEFERS: 99
- Extended logging

---

## 🚀 How to Use These Examples

### Method 1: Test Locally with --config Parameter

```bash
# View configuration without running
sudo /Library/Management/erase-install/erase-install-defer-wrapper.sh --config=examples/config-production.json --show-config

# Run with test configuration
sudo /Library/Management/erase-install/erase-install-defer-wrapper.sh --config=examples/config-testing.json
```

### Method 2: Deploy via Jamf Configuration Profile

1. Choose an example configuration
2. Copy to local system or customize
3. Upload to Jamf:
   - **Computers → Configuration Profiles → New**
   - **Files and Processes** payload
   - Upload JSON file
   - Destination: `/Library/Managed Preferences/com.macjediwizard.eraseinstall.config.json`
   - Scope to target computers

### Method 3: Deploy via Jamf Script

```bash
#!/bin/bash
# Copy example config to managed preferences

# Choose one:
CONFIG_TYPE="production"  # or: testing, aggressive, flexible, minimal

curl -L -o /tmp/config.json \
  "https://raw.githubusercontent.com/MacJediWizard/Jamf-Silent-macOS-Upgrade-Scheduler/main/examples/config-${CONFIG_TYPE}.json"

sudo mkdir -p "/Library/Managed Preferences"
sudo cp /tmp/config.json "/Library/Managed Preferences/com.macjediwizard.eraseinstall.config.json"
sudo chmod 644 "/Library/Managed Preferences/com.macjediwizard.eraseinstall.config.json"
sudo chown root:wheel "/Library/Managed Preferences/com.macjediwizard.eraseinstall.config.json"

echo "✅ Deployed ${CONFIG_TYPE} configuration"
```

---

## 🎯 Choosing the Right Configuration

| Scenario | Recommended Config | Reason |
|----------|-------------------|--------|
| **First deployment** | `config-production.json` | Balanced, well-tested settings |
| **Testing/QA** | `config-testing.json` | No reboots, extended deferrals |
| **Security patch** | `config-aggressive.json` | Minimal deferrals, urgent messaging |
| **Creative users** | `config-flexible.json` | Extended time, friendly messaging |
| **Simple test** | `config-minimal.json` | Quick start, minimal changes |

---

## 📝 Customizing Configurations

### Quick Edits

You can edit any example file and test immediately:

```bash
# 1. Copy example to temp location
cp examples/config-production.json /tmp/my-config.json

# 2. Edit with your preferred editor
nano /tmp/my-config.json

# 3. Test your changes
sudo /Library/Management/erase-install/erase-install-defer-wrapper.sh --config=/tmp/my-config.json --show-config

# 4. Deploy via Jamf when ready
```

### Common Customizations

**Change macOS version:**
```json
"core_settings": {
  "INSTALLER_OS": "16"  ← Change to target version
}
```

**Adjust deferral limit:**
```json
"core_settings": {
  "MAX_DEFERS": 5  ← Increase or decrease
}
```

**Change timeout:**
```json
"core_settings": {
  "FORCE_TIMEOUT_SECONDS": 172800  ← 2 days instead of 3
}
```

**Customize dialog message:**
```json
"main_dialog": {
  "DIALOG_TITLE": "Your Company - macOS Upgrade",
  "DIALOG_MESSAGE": "Your custom message here..."
}
```

---

## ✅ Validation

Before deploying, validate your JSON:

```bash
# Validate syntax
plutil -lint examples/config-production.json

# View entire config
plutil -p examples/config-production.json

# Test with wrapper
sudo /Library/Management/erase-install/erase-install-defer-wrapper.sh --config=examples/config-production.json --show-config
```

---

## 📚 Additional Resources

- **Main README**: `../README.md`
- **JSON Implementation Guide**: `../V2.0_JSON_CONFIG_IMPLEMENTATION.md`
- **Quick Start Guide**: `../JAMF_CONFIG_PROFILE_QUICK_START.md`
- **Testing Checklist**: `../V2.0_TESTING_CHECKLIST.md`
- **Complete JSON Template**: `../com.macjediwizard.eraseinstall.config.json`

---

**Made with ❤️ by MacJediWizard Consulting, Inc.**
