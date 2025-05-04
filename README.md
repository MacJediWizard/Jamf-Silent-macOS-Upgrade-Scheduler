# Jamf Silent macOS Upgrade Scheduler

A silent macOS upgrade orchestration wrapper for [Graham Pugh's erase-install](https://github.com/grahampugh/erase-install),  
designed for enterprise environments using Jamf Pro or other MDMs.

This script silently pre-caches macOS installers and prompts users only at the final decision point, balancing user flexibility with enforced upgrade deadlines.  
Now with **automatic dependency installation**, **snooze functionality**, **login-time installation**, and **comprehensive diagnostics**.

---

## Features

- 🚀 Silent installer download and caching
- 🛡 Minimal user interruption
- ⏳ 24-hour deferral support (up to 3 times)
- ⏰ Snooze option for short-term deferrals (1-4 hours)
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

## Configuration

At the top of the script, these options are configurable:

| Variable | Purpose | Default |
|:---------|:--------|:--------|
| `SCRIPT_VERSION` | Current version of this script | `1.5.2` |
| `INSTALLER_OS` | Target macOS version to upgrade to | `15` |
| `MAX_DEFERS` | Maximum allowed 24-hour deferrals | `3` |
| `FORCE_TIMEOUT_SECONDS` | Force install after timeout | `259200` |
| `PLIST` | Preferences file location | `/Library/Preferences/com.macjediwizard.eraseinstall.plist` |
| `SCRIPT_PATH` | Path to erase-install script | `/Library/Management/erase-install/erase-install.sh` |
| `DIALOG_BIN` | Path to SwiftDialog binary | `/Library/Management/erase-install/Dialog.app/Contents/MacOS/Dialog` |
| `TEST_MODE` | Enable dry-run testing mode | `false` |
| `AUTO_INSTALL_DEPENDENCIES` | Auto-install erase-install and swiftDialog | `true` |
| `DEBUG_MODE` | Enable verbose debug logs | `false` |
| `MAX_LOG_SIZE_MB` | Maximum log file size before rotation | `10` |
| `MAX_LOG_FILES` | Number of log files to keep when rotating | `5` |
| `DIALOG_TITLE` | Dialog window title text | `"macOS Upgrade Required"` |
| `DIALOG_MESSAGE` | Dialog main message | `"Please install macOS ${INSTALLER_OS}. Select an action:"` |
| `DIALOG_INSTALL_NOW_TEXT` | Text for 'Install Now' option | `"Install Now"` |
| `DIALOG_SCHEDULE_TODAY_TEXT` | Text for 'Schedule Today' option | `"Schedule Today"` |
| `DIALOG_DEFER_TEXT` | Text for 'Defer 24 Hours' option | `"Defer 24 Hours"` |
| `DIALOG_ICON` | Dialog window icon (SF Symbol or path) | `"SF=gear"` |
| `DIALOG_POSITION` | Dialog window screen position | `"topright"` |

---

## Recent Updates (v1.5.2)

- Fixed octal parsing errors in time calculation functions
- Properly handled leading zeros in time values with explicit base-10 conversion
- Corrected handling of scheduled times like 08:00 and 09:00
- Enhanced time validation in scheduling functions
- Updated configuration variables for more consistent organization
- Improved error messages for time formatting issues

---

## Usage

1. Deploy the script to client Macs via Jamf Pro or another MDM.
2. Ensure erase-install and swiftDialog are either installed or allow the script to auto-install them.
3. Customize top-of-script variables as needed (macOS version, dialog texts, etc).
4. Launch the script manually, via Jamf policy, or a LaunchDaemon trigger.

---

## Scheduling Options

The script provides multiple scheduling options:

- **Install Now**: Begins installation immediately
- **Schedule Today**: Allows selecting a time later today 
- **Defer 24 Hours**: Postpones for 24 hours (up to configured maximum)

---

## License

This project is licensed under the MIT License. See the LICENSE file for more details.

---

## Author

> Made with ❤️ by [MacJediWizard Consulting, Inc.](https://macjediwizard.com)