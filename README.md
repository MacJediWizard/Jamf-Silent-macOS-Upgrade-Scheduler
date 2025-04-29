# Jamf Silent macOS Upgrade Scheduler

A silent macOS upgrade orchestration wrapper for [Graham Pugh's erase-install](https://github.com/grahampugh/erase-install), designed for enterprise environments using Jamf Pro or other MDMs.

This script silently pre-caches macOS installers and prompts users only at the final decision point, balancing user flexibility with enforced upgrade deadlines.  
Now with **automatic dependency installation** for `erase-install` and `swiftDialog` if missing!

---

## Features

- 🚀 Silent installer download and caching
- 🛡 Minimal user interruption
- ⏳ 24-hour deferral support (up to 3 times)
- 🔒 Forced upgrade after 72 hours or 3 deferrals
- 📅 User scheduling via LaunchDaemon
- 🛠 Full dry-run support with erase-install's `--test-run`
- 📦 Auto-installs erase-install and swiftDialog if missing (configurable)
- ✅ Enterprise-grade error handling and dependency validation

---

## Requirements

- macOS 11 or newer
- [erase-install](https://github.com/grahampugh/erase-install) v37.0 or later
- [swiftDialog](https://github.com/bartreardon/swiftDialog) installed on client Macs
- Management via Jamf Pro or other MDM (optional but recommended)

> **Note:** Missing dependencies can now be automatically installed if configured.

---

## Configuration

These options can be set at the top of the script:

| Variable | Description | Default |
|:---------|:------------|:--------|
| `INSTALLER_OS` | Target macOS version to upgrade to | `15` |
| `MAX_DEFERS` | Maximum allowed 24-hour deferrals | `3` |
| `TEST_MODE` | Enable dry-run testing (no real install) | `false` |
| `AUTO_INSTALL_DEPENDENCIES` | Auto-install erase-install and swiftDialog if missing | `true` |

---

## Usage

1. Deploy this script and Graham Pugh’s erase-install to target Macs.
2. Ensure swiftDialog is installed (or let the script auto-install it).
3. Customize script settings if needed.
4. Optionally schedule script via LaunchDaemon or Jamf policy.
5. Monitor activity via `/var/log/erase-install-wrapper.log`.

---

## Scheduling and Deferral Logic

| Scenario | Behavior |
|:---------|:---------|
| User defers | Adds 24 hours (up to 3 times) |
| 3 Deferrals or 72 Hours | No more defer option — must Install Now or Schedule Today |
| User chooses Schedule Today | LaunchDaemon created dynamically for selected time |
| Completely Silent | Runs silently until user decision is needed |

---

## License

This project is licensed under the MIT License. See [LICENSE](./LICENSE) for details.

---

## Author

> Made with ❤️ by [MacJediWizard Consulting, Inc.](https://macjediwizard.com)