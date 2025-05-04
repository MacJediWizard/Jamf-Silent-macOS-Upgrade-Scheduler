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
- ⏰ Snooze option for short-term deferrals (1–4 hours)  
- 🔒 Forced upgrade after 72 hours or 3 deferrals  
- 📅 Flexible scheduling options (today, tomorrow, or at next login)  
- 🔐 Robust directory-based locking mechanism to prevent race conditions  
- 🎯 Enhanced UI handling with proper user context display  
- 🛠 Full dry-run testing with erase-install’s `--test-run`  
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
- Tracking deferrals and enforcing upgrade deadlines
- Scheduling installations for later in the day or next login
- Initiating immediate upgrades if required

This script is fully self-contained and **remains available offline** after deployment, allowing it to be triggered by LaunchDaemons, login hooks, or local schedules without requiring Jamf network connectivity.

---

## Configuration

At the top of the script, these options are configurable:

| Variable                     | Purpose                                        | Default |
|-----------------------------|------------------------------------------------|---------|
| `SCRIPT_VERSION`            | Current version of this script                 | `1.5.2` |
| `INSTALLER_OS`              | Target macOS version to upgrade to             | `15`    |
| `MAX_DEFERS`                | Maximum allowed 24-hour deferrals              | `3`     |
| `FORCE_TIMEOUT_SECONDS`     | Force install after timeout                    | `259200`|
| `PLIST`                     | Preferences file location                      | `/Library/Preferences/com.macjediwizard.eraseinstall.plist` |
| `SCRIPT_PATH`               | Path to erase-install script                   | `/Library/Management/erase-install/erase-install.sh` |
| `DIALOG_BIN`                | Path to SwiftDialog binary                     | `/Library/Management/erase-install/Dialog.app/Contents/MacOS/Dialog` |
| `TEST_MODE`                 | Enable dry-run testing mode                    | `false` |
| `AUTO_INSTALL_DEPENDENCIES` | Auto-install erase-install and swiftDialog     | `true`  |
| `DEBUG_MODE`                | Enable verbose debug logs                      | `false` |
| `MAX_LOG_SIZE_MB`           | Max log file size before rotation              | `10`    |
| `MAX_LOG_FILES`             | Number of log files to keep                    | `5`     |
| `DIALOG_TITLE`              | Dialog window title text                       | `"macOS Upgrade Required"` |
| `DIALOG_MESSAGE`            | Dialog main message                            | `"Please install macOS ${INSTALLER_OS}. Select an action:"` |
| `DIALOG_INSTALL_NOW_TEXT`  | Text for 'Install Now' option                  | `"Install Now"` |
| `DIALOG_SCHEDULE_TODAY_TEXT`| Text for 'Schedule Today' option               | `"Schedule Today"` |
| `DIALOG_DEFER_TEXT`         | Text for 'Defer 24 Hours' option               | `"Defer 24 Hours"` |
| `DIALOG_ICON`               | Dialog icon (SF Symbol or path)                | `"SF=gear"` |
| `DIALOG_POSITION`           | Dialog window position on screen               | `"topright"` |

---

## Recent Updates (v1.5.2)

- 🛠 Fixed octal parsing errors in time calculation functions  
- 🕗 Handled leading zeros in times like 08:00 and 09:00  
- 🧠 Improved time validation and parsing using base-10 conversion  
- 📉 Enhanced error messages for formatting issues  
- 🔄 Reorganized configuration variables for consistency  
- 🧱 Standardized time handling across scheduling and deferral logic  

---

## Usage

1. Deploy both policies to your Jamf environment:
    - **Installer Caching**: fetches the installer in the background
    - **Wrapper Execution**: manages prompts, deferrals, and scheduling
2. Customize dialog text and deferral limits at the top of the script
3. Test using `TEST_MODE=true` for dry-run validation
4. Monitor logs and user deferral history via the preference plist

---

## Scheduling Options

The script provides the following user-facing options:

- **Install Now** – Start installation immediately  
- **Schedule Today** – Choose a time later in the day  
- **Defer 24 Hours** – Postpone installation for one day (max 3 times)  

Once the deferral limit or 72-hour window is reached, only Install Now and Schedule Today are presented.

---

## License

This project is licensed under the MIT License. See the LICENSE file for more details.

---

## Author

> Made with ❤️ by [MacJediWizard Consulting, Inc.](https://macjediwizard.com)