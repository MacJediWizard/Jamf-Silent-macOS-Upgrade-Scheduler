# Jamf Silent macOS Upgrade Scheduler

A silent macOS upgrade orchestration wrapper for [Graham Pugh's erase-install](https://github.com/grahampugh/erase-install),  
designed for enterprise environments using Jamf Pro or other MDMs.

This script silently pre-caches macOS installers and prompts users only at the final decision point, balancing user flexibility with enforced upgrade deadlines.  
Now with **automatic dependency installation**, **dynamic dialog configuration**, and **window positioning** for a better user experience.

---

## Features

- 🚀 Silent installer download and caching
- 🛡 Minimal user interruption
- ⏳ 24-hour deferral support (up to 3 times)
- 🔒 Forced upgrade after 72 hours or 3 deferrals
- 📅 User scheduling via LaunchDaemon with reliable execution tracking
- 🔐 Lock file mechanism to prevent multiple simultaneous executions
- 🎯 Enhanced UI handling with proper user context display
- 🛠 Full dry-run testing with erase-install's `--test-run`
- 📦 Auto-installs erase-install and swiftDialog if missing
- ✍️ Configurable dialog text, button labels, and window position
- 🔄 Robust process tracking and cleanup procedures
- 📊 Resource limits and process control for LaunchDaemons
- ✅ Enterprise-grade error handling, structured logging (INFO/WARN/ERROR/DEBUG)

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
| `INSTALLER_OS` | Target macOS version to upgrade to | `15` |
| `MAX_DEFERS` | Maximum allowed 24-hour deferrals | `3` |
| `TEST_MODE` | Enable dry-run testing mode | `false` |
| `AUTO_INSTALL_DEPENDENCIES` | Auto-install erase-install and swiftDialog | `true` |
| `DEBUG_MODE` | Enable verbose debug logs | `false` |
| `DIALOG_TITLE` | Dialog window title text | `"macOS Upgrade Required"` |
| `DIALOG_MESSAGE` | Dialog main message | `"Please install macOS $INSTALLER_OS."` |
| `DIALOG_INSTALL_NOW_TEXT` | Text for 'Install Now' button | `"Install Now"` |
| `DIALOG_SCHEDULE_TODAY_TEXT` | Text for 'Schedule Today' button | `"Schedule Today"` |
| `DIALOG_DEFER_TEXT` | Text for 'Defer 24 Hours' button | `"Defer 24 Hours"` |
| `DIALOG_ICON` | Dialog window icon (SF Symbol or path) | `"SF=gear"` |
| `DIALOG_POSITION` | Dialog window screen position | `"topright"` |

---

## Usage

1. Deploy the script to client Macs via Jamf Pro or another MDM.
2. Ensure erase-install and swiftDialog are either installed or allow the script to auto-install them.
3. Customize top-of-script variables as needed (macOS version, dialog texts, etc).
4. Launch the script manually, via Jamf policy, or a LaunchDaemon trigger.

---

## License

This project is licensed under the MIT License. See the LICENSE file for more details.

---

## Author

> Made with ❤️ by [MacJediWizard Consulting, Inc.](https://macjediwizard.com)