# Jamf Silent macOS Upgrade Scheduler

A silent macOS upgrade orchestration wrapper for [Graham Pugh's erase-install](https://github.com/grahampugh/erase-install),  
designed for enterprise environments using Jamf Pro or other MDMs.

This script silently pre-caches macOS installers and prompts users only at the final decision point, balancing user flexibility with enforced upgrade deadlines.  
Now with **automatic dependency installation**, **test mode features**, **pre-authentication notice**, **snooze functionality**, **login-time installation**, **emergency abort functionality**, and **comprehensive diagnostics**.

---

## Features

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

To provide a smooth upgrade experience with minimal disruption, this tool is designed to work with **two separate Jamf policies**:

### 1. Installer Caching Policy

Run this policy ahead of time to silently download and cache the macOS installer. This ensures that the upgrade can begin immediately when triggered later by the wrapper, without the delay of downloading.

**Jamf policy script:**

```bash
sudo /Library/Management/erase-install/erase-install.sh \
  --download \
  --os=15 \
  --no-fs \
  --check-power \
  --min-drive-space=50 \
  --overwrite \
  --silent
```

This policy should be scheduled to run during business hours or off-peak times, ensuring that the installer is already cached locally when needed.

### 2. Wrapper Execution Policy

The second policy runs this wrapper script. It handles:

- Prompting the user via SwiftDialog
- Displaying pre-authentication notice for standard users
- Tracking deferrals and enforcing upgrade deadlines
- Managing emergency abort functionality for scheduled installations
- Scheduling installations for later in the day or next login
- Initiating immediate upgrades if required

This script is fully self-contained and **remains available offline** after deployment, allowing it to be triggered by LaunchDaemons, login hooks, or local schedules without requiring Jamf network connectivity.

---

## Configuration

At the top of the script, these options are configurable:

| Variable | Purpose | Default |
|----------|---------|---------|
| `SCRIPT_VERSION` | Current version of this script | `1.7.0` |
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

## Recent Updates (v1.7.0)

- 🎉 **PRODUCTION READY**: Fixed all critical bugs preventing enterprise deployment
- 🔧 **Fixed scheduled installation execution**: Resolved syntax error preventing scheduled installations from running
- 🔧 **Fixed counter reset logic**: Added missing reset functionality to scheduled installation workflow  
- 🔧 **Fixed race condition**: Eliminated abort count corruption after successful installations
- 🔧 **Enhanced abort functionality**: Complete abort cycle now works with proper enforcement and reset
- ✅ **Verified complete system integration**: All three core systems (defer, abort, scheduled) work seamlessly
- ✅ **Enterprise testing complete**: Comprehensive validation of all user workflows and edge cases
- 📊 **Improved logging and diagnostics**: Enhanced debugging capabilities for scheduled installation issues
- 🚀 **Ready for production deployment**: No known critical bugs remaining

---

## Usage

1. Deploy both policies to your Jamf environment:
    - **Installer Caching**: fetches the installer in the background
    - **Wrapper Execution**: manages prompts, deferrals, aborts, and scheduling
2. Customize dialog text, deferral limits, and abort settings at the top of the script
3. Configure the pre-authentication notice based on your environment needs
4. Test using `TEST_MODE=true` and `SKIP_OS_VERSION_CHECK=true` for quick testing
5. Run with `--test-os-check` parameter for one-time test mode activation
6. Monitor logs and user deferral/abort history via the preference plist

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