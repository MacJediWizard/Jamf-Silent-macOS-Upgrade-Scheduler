# Changelog

## [1.2.0] - 2025-04-29
### Added
- Auto-installation of missing dependencies (erase-install, swiftDialog)
- `AUTO_INSTALL_DEPENDENCIES` flag for controlling automatic installs
- Updated README to reflect new features

### Changed
- Dependency check process improved to install or exit cleanly

---

## [1.1.0] - 2025-04-28
### Added
- Hardened enterprise version of the wrapper script
- Dependency validation (erase-install, swiftDialog)
- Improved LaunchDaemon lifecycle management
- Unified logging system
- Dynamic config section (timeout values, max deferrals)
- Smarter plist management (self-healing missing values)

### Changed
- Internal restructuring for clarity and reliability
- Dry-run (test mode) integration improved for scheduling and installs

---

## [1.0.1] - 2025-04-28
### Added
- MIT license and professional header
- Integrated erase-install `--test-run` mode

---

## [1.0.0] - 2025-04-28
### Initial Version
- Working wrapper for erase-install
- Supports 24-hour deferrals (up to 3 times)
- Schedule installation for later today
- Minimal user interface using swiftDialog