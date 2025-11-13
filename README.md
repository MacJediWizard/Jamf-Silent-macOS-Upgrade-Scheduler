# Jamf Silent macOS Upgrade Scheduler

A silent macOS upgrade orchestration wrapper for [Graham Pugh's erase-install](https://github.com/grahampugh/erase-install),  
designed for enterprise environments using Jamf Pro or other MDMs.

This script silently pre-caches macOS installers and prompts users only at the final decision point, balancing user flexibility with enforced upgrade deadlines.
Now with **JSON-based configuration management** (v2.0), **automatic dependency installation**, **test mode features**, **pre-authentication notice**, **snooze functionality**, **login-time installation**, **emergency abort functionality**, and **comprehensive diagnostics**.

---

## Features

### ✨ v2.0 - JSON Configuration Management
- 📝 **JSON-based configuration** - Manage all settings via easy-to-read JSON files
- 🎛️ **Centralized management** - Control settings from Jamf Configuration Profiles
- 🏢 **Per-department configs** - Deploy different settings to different groups
- ⚡ **Instant updates** - Change settings without redeploying the script
- 🔄 **Backwards compatible** - Falls back to script defaults if no JSON present
- 📚 **Complete documentation** - Ready-to-use JSON templates and Jamf guides

### Core Features
- 🚀 Silent installer download and caching
- 🛡 Minimal user interruption
- 🔐 Pre-authentication notice for standard users to prepare for admin prompts
- ⏳ 24-hour deferral support (up to 3 times)
- ⏰ Snooze option for short-term deferrals (1–4 hours)
- 🆘 Emergency abort functionality for scheduled installations (up to 3 times)
- 🧪 Test mode with quick 5-minute deferrals and OS version check bypass
- 🔒 Forced upgrade after 72 hours or 3 deferrals
- 📅 Flexible scheduling options (today, tomorrow, or at next login)
- 🔐 Robust directory-based locking mechanism to prevent race conditions
- 🎯 Enhanced UI handling with proper user context display
- 🛠 Full dry-run testing with erase-install's `--test-run`
- 📦 Auto-installs erase-install and swiftDialog if missing
- ✍️ Configurable dialog text, button labels, and window position
- 🔄 Robust process tracking and cleanup procedures
- 📊 Comprehensive system diagnostics for troubleshooting
- ✅ Enterprise-grade error handling, structured logging (INFO/WARN/ERROR/DEBUG)
- ⚙️ Improved time handling with proper base-10 conversion  

---

## Requirements

- macOS 11 or newer  
- [erase-install](https://github.com/grahampugh/erase-install) v37.0 or later  
- [swiftDialog](https://github.com/bartreardon/swiftDialog) installed on client Macs  
- (Optionally: Jamf Pro to manage deployment)  

---

## Jamf Deployment Model

To provide a smooth upgrade experience with minimal disruption, this tool is designed to work with **three separate Jamf policies**:

### 1. Deploy Wrapper Script to Persistent Location (Required First)

**⚠️ CRITICAL:** The wrapper script **must be deployed to a persistent location** on each Mac for deferrals, scheduling, and abort functionality to work properly.

**Why this is required:**
- When users defer installation, the script creates a LaunchDaemon to run 24 hours later
- When users schedule for a specific time, a LaunchDaemon is created for that time
- These LaunchDaemons need to call the script from a persistent disk location
- If the script only exists in Jamf policy memory, deferrals and scheduling will fail

**Jamf Policy: Deploy Wrapper Script**

Create a policy with the following script to deploy the wrapper to a persistent location:

```bash
#!/bin/bash
# Jamf Policy: Deploy Wrapper Script

echo "Deploying macOS upgrade wrapper script..."

# Create directory
mkdir -p /Library/Management/erase-install

# Download directly from GitHub (always gets latest version)
curl -L -o /Library/Management/erase-install/erase-install-defer-wrapper.sh \
  "https://github.com/MacJediWizard/Jamf-Silent-macOS-Upgrade-Scheduler/releases/download/v1.7.2/erase-install-defer-wrapper.sh"

# Make executable
chmod +x /Library/Management/erase-install/erase-install-defer-wrapper.sh

# Verify deployment
if [ -x "/Library/Management/erase-install/erase-install-defer-wrapper.sh" ]; then
  echo "✅ Script deployed successfully to: /Library/Management/erase-install/erase-install-defer-wrapper.sh"
  ls -lh /Library/Management/erase-install/erase-install-defer-wrapper.sh
else
  echo "❌ ERROR: Script deployment failed"
  exit 1
fi
```

**Jamf Policy Configuration:**

```
General:
  Display Name: Deploy macOS Upgrade Wrapper Script
  Trigger: Enrollment Complete, Recurring Check-in, or Custom
  Execution Frequency: Once per computer

Scripts:
  Priority: Before
  Script: [Upload the deployment script above]

Scope:
  Targets: All computers or specific smart groups
```

**How the script auto-detects its location:**
- The wrapper automatically detects where it's located on disk (lines 356-369)
- It stores this path and uses it when creating LaunchDaemons
- Works regardless of where you deploy it (recommended: `/Library/Management/erase-install/`)

---

### 2. Installer Caching Policy

Run this policy ahead of time to silently download and cache the macOS installer. This ensures that the upgrade can begin immediately when triggered later by the wrapper, without the delay of downloading.

**Jamf policy script:**

```bash
sudo /Library/Management/erase-install/erase-install.sh \
  --download \
  --os 15 \
  --no-fs \
  --check-power \
  --min-drive-space 50 \
  --overwrite \
  --silent
```

**Note:** The `--os 15` parameter is critical to ensure you're downloading the correct macOS version. Without it, erase-install will default to the latest available version.

This policy should be scheduled to run during business hours or off-peak times, ensuring that the installer is already cached locally when needed.

---

### 3. Wrapper Execution Policy

The third policy executes the wrapper script from its persistent location. It handles:

- Prompting the user via SwiftDialog
- Displaying pre-authentication notice for standard users
- Tracking deferrals and enforcing upgrade deadlines
- Managing emergency abort functionality for scheduled installations
- Scheduling installations for later in the day or next login
- Initiating immediate upgrades if required

**Jamf Policy: Execute Wrapper Script**

```bash
#!/bin/bash
# Execute the deployed wrapper script

/Library/Management/erase-install/erase-install-defer-wrapper.sh
```

**Jamf Policy Configuration:**

```
General:
  Display Name: macOS Upgrade - Start Process
  Trigger: Self Service, Custom, or Recurring Check-in
  Execution Frequency: Ongoing

Scripts:
  Script: [Upload the execution script above]

Scope:
  Targets: Computers that need upgrading
  Exclusions: Smart Group "macOS Upgrade Script Currently Running" (see duplicate prevention section)
```

**How it works:**
- Script executes from persistent location (`/Library/Management/erase-install/`)
- Creates LaunchDaemons that reference the same persistent path
- LaunchDaemons can trigger the script for deferrals/scheduling without Jamf connectivity
- Script remains available offline for local execution

---

## Preventing Duplicate Policy Executions

The wrapper script includes built-in locking mechanisms to prevent simultaneous executions. However, when deployed as a Jamf policy, additional safeguards are recommended to prevent Jamf from triggering the policy multiple times while it's still running (in "Pending" state).

### Smart Group Exclusion with Extension Attribute

This Jamf-native solution automatically excludes computers from the policy scope while the script is running, without requiring any modifications to the wrapper script.

**Step 1: Create Extension Attribute**

Create a new Extension Attribute in Jamf Pro:

```
Display Name: macOS Upgrade Script Status
Description: Detects if the upgrade wrapper is currently running
Data Type: String
Input Type: Script
```

**Extension Attribute Script:**

```bash
#!/bin/bash
# Check if upgrade wrapper is currently running

if [ -f "/tmp/erase-install-wrapper-main.lock" ] || \
   [ -f "/var/run/erase-install-wrapper.lock" ]; then
    echo "<result>Running</result>"
    exit 0
fi

if pgrep -f "erase-install-defer-wrapper.sh" > /dev/null 2>&1; then
    echo "<result>Running</result>"
    exit 0
fi

if launchctl list | grep -q "com.macjediwizard.eraseinstall.schedule"; then
    echo "<result>Running</result>"
    exit 0
fi

echo "<result>Not Running</result>"
```

**Step 2: Create Smart Group**

```
Name: macOS Upgrade Script Currently Running
Criteria:
  - macOS Upgrade Script Status | is | Running
```

**Step 3: Add Exclusion to Your Wrapper Policy**

```
Policy → Scope Tab:
  Targets: [Your deployment group]
  Exclusions:
    - Smart Group: "macOS Upgrade Script Currently Running"
```

**Step 4: Enable Inventory Updates**

In your wrapper policy:

```
Maintenance Tab:
  [x] Update Inventory
```

**How it works:**
- Policy starts → Script creates lock file
- Inventory update → Extension Attribute detects "Running"
- Smart Group includes computer → Policy automatically excludes it
- Script completes → Next inventory update shows "Not Running"
- Smart Group removes computer → Policy can run again

**Benefits:**
- ✅ No script modifications required
- ✅ Fully Jamf-native solution
- ✅ Works with any trigger type (check-in, login, custom, Self Service)
- ✅ Automatic detection and exclusion
- ✅ Compatible with all wrapper features (deferrals, scheduling, abort)

---

## Configuration

### ✨ v2.0 - JSON Configuration (Recommended)

The recommended way to configure the wrapper is using **JSON configuration files** deployed via Jamf Configuration Profiles. This allows you to:

- 📝 Manage all settings from Jamf Pro (no script editing required)
- ⚡ Update settings instantly (changes apply on next policy run)
- 🏢 Deploy different configs to different departments
- 📋 Use human-readable JSON format
- 🔍 Debug with `--show-config` parameter
- 🎯 Test with custom configs using `--config` parameter

**Quick Start:**

1. Copy `com.macjediwizard.eraseinstall.config.json` template
2. Edit settings as needed
3. Deploy via Jamf Configuration Profile (Files and Processes payload)
4. Place at: `/Library/Managed Preferences/com.macjediwizard.eraseinstall.config.json`

**Configuration Priority (Highest to Lowest):**
1. Custom JSON (`--config=/path/to/file.json` parameter)
2. Managed JSON (`/Library/Managed Preferences/...`)
3. Local JSON (`/Library/Preferences/...`)
4. Script Defaults (User Configuration Section)

**Command-Line Parameters:**
```bash
# Display version information
./erase-install-defer-wrapper.sh --version

# Display help and usage
./erase-install-defer-wrapper.sh --help

# Display current configuration
./erase-install-defer-wrapper.sh --show-config

# Use custom config file
./erase-install-defer-wrapper.sh --config=/tmp/test-config.json

# Bypass OS version check (testing)
./erase-install-defer-wrapper.sh --test-os-check
```

**Documentation:**
- **Quick Start**: See `JAMF_CONFIG_PROFILE_QUICK_START.md`
- **Technical Details**: See `V2.0_JSON_CONFIG_IMPLEMENTATION.md`
- **JSON Template**: See `com.macjediwizard.eraseinstall.config.json`

### Script Defaults (v1.x compatibility)

If no JSON configuration is present, the script falls back to these hardcoded defaults:

| Variable | Purpose | Default |
|----------|---------|---------|
| `SCRIPT_VERSION` | Current version of this script | `2.0.0` |
| `INSTALLER_OS` | Target macOS version to upgrade to | `15` |
| `MAX_DEFERS` | Maximum allowed 24-hour deferrals | `3` |
| `MAX_ABORTS` | Maximum allowed emergency aborts | `3` |
| `FORCE_TIMEOUT_SECONDS` | Force install after timeout | `259200` |
| `PLIST` | Preferences file location | `/Library/Preferences/com.macjediwizard.eraseinstall.plist` |
| `SCRIPT_PATH` | Path to erase-install script | `/Library/Management/erase-install/erase-install.sh` |
| `DIALOG_BIN` | Path to SwiftDialog binary | `/Library/Management/erase-install/Dialog.app/Contents/MacOS/Dialog` |
| `TEST_MODE` | Enable dry-run testing mode | `false` |
| `SKIP_OS_VERSION_CHECK` | Bypass OS version checking in test mode | `false` |
| `AUTO_INSTALL_DEPENDENCIES` | Auto-install erase-install and swiftDialog | `true` |
| `DEBUG_MODE` | Enable verbose debug logs | `false` |
| `MAX_LOG_SIZE_MB` | Max log file size before rotation | `10` |
| `MAX_LOG_FILES` | Number of log files to keep | `5` |
| `DIALOG_TITLE` | Dialog window title text | `"macOS Upgrade Required"` |
| `DIALOG_MESSAGE` | Dialog main message | `"Please install macOS ${INSTALLER_OS}. Select an action:"` |
| `DIALOG_INSTALL_NOW_TEXT` | Text for 'Install Now' option | `"Install Now"` |
| `DIALOG_SCHEDULE_TODAY_TEXT` | Text for 'Schedule Today' option | `"Schedule Today"` |
| `DIALOG_DEFER_TEXT` | Text for 'Defer 24 Hours' option | `"Defer 24 Hours"` |
| `DIALOG_DEFER_TEXT_TEST_MODE` | Text for test mode defer option | `"Defer 5 Minutes (TEST MODE)"` |
| `ABORT_BUTTON_TEXT` | Text for emergency abort button | `"Abort (Emergency)"` |
| `DIALOG_ICON` | Dialog icon (SF Symbol or path) | `"SF=gear"` |
| `DIALOG_POSITION` | Dialog window position on screen | `"topright"` |
| `SHOW_AUTH_NOTICE` | Enable pre-authentication notice | `true` |
| `AUTH_NOTICE_TITLE` | Title for auth notice dialog | `"Admin Access Required"` |
| `AUTH_NOTICE_MESSAGE` | Message for auth notice | `"You will be prompted for admin credentials..."` |
| `AUTH_NOTICE_BUTTON` | Text for auth notice button | `"I'm Ready to Continue"` |
| `AUTH_NOTICE_TIMEOUT` | Timeout in seconds (0 = no timeout) | `60` |
| `AUTH_NOTICE_ICON` | Icon for auth notice dialog | `"SF=lock.shield"` |

---

## Emergency Abort Functionality

Version 1.7.0 introduces comprehensive emergency abort functionality for scheduled installations:

- **Abort Button**: Configurable "Abort (Emergency)" button appears in scheduled installation dialogs
- **Abort Limits**: Users can abort up to 3 times before reaching force install mode
- **Automatic Rescheduling**: After abort, installation is automatically rescheduled with configurable delay
- **Abort Enforcement**: After 3 aborts, scheduled dialogs show no abort button (force install mode)
- **Counter Reset**: Abort counts reset to 0 after successful installation completion
- **Independent Tracking**: Abort counts are separate from deferral counts for flexible policy enforcement

---

## Pre-Authentication Notice Feature

To improve user experience in environments where users operate with standard accounts but need temporary admin privileges for installation, version 1.7.0 includes a pre-authentication notice:

- **User Notification**: Displays a dialog informing users they'll need admin credentials before the actual prompt appears
- **Preparation Time**: Allows standard users to obtain admin privileges via Jamf Connect or Self Service
- **Customizable**: Full control over message text, timeout, and appearance
- **Toggle Control**: Can be disabled in environments where it's not needed

This feature is particularly valuable for organizations using Jamf Connect or Self Service for temporary admin privilege escalation.

---

## Testing Features

The script includes several features to simplify testing and QA workflows:

### Test Mode

When `TEST_MODE=true`:
- Dialog displays "TEST MODE" indicator in title
- Deferral periods are shortened to 5 minutes instead of 24 hours
- Dialog shows "Defer 5 Minutes (TEST MODE)" instead of "Defer 24 Hours"
- Abort defer periods are shortened for faster testing

### OS Version Check Bypass

When `SKIP_OS_VERSION_CHECK=true`:
- Script proceeds with upgrade workflow even if system is already at the target OS version
- Provides detailed OS version comparison logs with "what would happen" messages
- Can be enabled via command line with `--test-os-check` parameter

These testing features allow you to test the complete workflow without waiting for long deferral periods or having to downgrade test systems.

---

## Recent Updates

### v2.0.0 (2025-11-06) - MAJOR RELEASE

- 🎉 **NEW: JSON Configuration Management** - Manage all wrapper settings via JSON files
- 📝 **JSON Support**: Load settings from Jamf Configuration Profiles or local JSON files
- 🎛️ **Three-tier priority**: Managed JSON (Jamf) > Local JSON > Script Defaults
- 🏢 **Per-department configs**: Deploy different JSON configs to different groups
- ⚡ **Instant updates**: Change settings in Jamf without redeploying script
- 🔄 **Backwards compatible**: Falls back to hardcoded defaults if no JSON present
- 📚 **Complete documentation**: JSON templates, Jamf deployment guides, quick start guide
- 🛠️ **Native parsing**: Uses macOS plutil (no external dependencies)
- ✅ **50+ settings**: All User Configuration Section options available in JSON
- 📋 **Example configs**: Standard, Aggressive, QA/Testing configurations included

### v1.7.2 (2025-11-05)

- 🔥 **CRITICAL FIX**: Fixed `get_available_macos_version()` to filter by INSTALLER_OS major version
- 🐛 **Fixed**: Function was calling erase-install --list without --os parameter, returning macOS 26.x
- 🐛 **Fixed**: SOFA fallback now searches for matching major version instead of using latest
- ✅ **Impact**: targetOSVersion now correctly set to latest macOS 15.x instead of 26.x
- ✅ **Impact**: Version checks now compare against correct target version
- ✅ **Impact**: Eliminates false "OS not at target" detections

### v1.7.1 (2025-11-05)

- 🔥 **CRITICAL FIX**: Added missing `--os` parameter to erase-install command
- 🐛 **Fixed**: Script now correctly passes INSTALLER_OS setting to erase-install.sh
- 🐛 **Fixed**: erase-install was defaulting to latest macOS (15.2.6/build 26) instead of configured version
- ✅ **Impact**: Script now correctly uses cached macOS 15 installer if available
- ✅ **Impact**: Downloads specific macOS 15 version instead of latest available
- 📊 **Impact**: Reduces bandwidth usage by utilizing cached installers
- 📚 **Added**: Documentation for preventing duplicate Jamf policy executions

### v1.7.0 (2025-08-04)

- 🎉 **PRODUCTION READY**: Fixed all critical bugs preventing enterprise deployment
- 🔧 **Fixed scheduled installation execution**: Resolved syntax error preventing scheduled installations from running
- 🔧 **Fixed counter reset logic**: Added missing reset functionality to scheduled installation workflow
- 🔧 **Fixed race condition**: Eliminated abort count corruption after successful installations
- 🔧 **Enhanced abort functionality**: Complete abort cycle now works with proper enforcement and reset
- ✅ **Verified complete system integration**: All three core systems (defer, abort, scheduled) work seamlessly
- ✅ **Enterprise testing complete**: Comprehensive validation of all user workflows and edge cases
- 📊 **Improved logging and diagnostics**: Enhanced debugging capabilities for scheduled installation issues

---

## Usage

1. Deploy all three policies to your Jamf environment **in this order**:
    - **Deploy Wrapper Script** (Policy #1): Deploys script to persistent location on Mac
    - **Installer Caching** (Policy #2): Fetches the macOS installer in the background
    - **Wrapper Execution** (Policy #3): Manages prompts, deferrals, aborts, and scheduling
2. Customize dialog text, deferral limits, and abort settings at the top of the script (before deployment)
3. Configure the pre-authentication notice based on your environment needs
4. Implement duplicate prevention using Extension Attribute and Smart Group (see above)
5. Test using `TEST_MODE=true` and `SKIP_OS_VERSION_CHECK=true` for quick testing
6. Run with `--test-os-check` parameter for one-time test mode activation
7. Monitor logs and user deferral/abort history via the preference plist

---

## User Experience Flow

1. **Initial Prompt**: User is presented with three options:
   - Install Now: Proceeds immediately to installation
   - Schedule Today: Lets user select a time later today for installation
   - Defer 24 Hours: Postpones the installation (up to max deferrals)

2. **Pre-Authentication Notice**: Before credentials are requested, users see a dialog explaining they'll need admin access.

3. **Scheduled Installation with Abort**: When scheduled time arrives, users see:
   - Continue button to proceed with installation
   - Abort (Emergency) button to postpone installation (up to max aborts)

4. **Admin Authentication**: Graham's erase-install script requests admin credentials.

5. **Installation Process**: The macOS upgrade proceeds with user-facing progress indicators.

6. **Counter Management**: After successful installation, both deferral and abort counts reset to 0.

---

## License

This project is licensed under the MIT License. See the LICENSE file for more details.

---

## Author

> Made with ❤️ by [MacJediWizard Consulting, Inc.](https://macjediwizard.com)