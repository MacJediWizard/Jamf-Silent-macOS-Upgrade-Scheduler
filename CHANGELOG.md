# Changelog

All notable changes to this project will be documented in this file.

## [1.4.3] – 2025-04-29
### Changed
- Switched to a dropdown UI with a single “OK” button for all three actions (Install Now, Schedule Today, Defer 24 Hours).

---

## [1.4.2] – 2025-04-29
### Added
- Preserve the `--mini` flag for a compact window.
- Added debug logging of SwiftDialog’s exit code and raw output to help troubleshoot empty or malformed responses.

---

## [1.4.1] – 2025-04-29
### Fixed
- Corrected syntax in the install functions (removed stray backslashes before `$(mktemp -d)` calls).

---

## [1.4.0] – 2025-04-29
### Added
- Persist `deferCount` and `firstPromptDate` in the preferences plist so deferral history carries across runs.
- Logic to reset deferral history whenever `SCRIPT_VERSION` is bumped (detects new script release).

---

## [1.3.0] - 2025-04-29
### Added
- Configurable Dialog window positioning (now defaults to `topright`)
- Configurable Dialog text, button labels, and icon via variables at top of script
- Updated script header and CHANGELOG to v1.3.0
- Finalized static configuration for easier Jamf deployment and maintenance

---

## [1.2.0] - 2025-04-29
### Added
- Auto-installation of missing dependencies (erase-install, swiftDialog)
- `AUTO_INSTALL_DEPENDENCIES` flag for optional auto-installs
- Improved dependency checks with clean fallback behavior
- Updated logging to INFO / WARN / ERROR / DEBUG structure
- Safe sudo execution of erase-install

---

## [1.1.0] - 2025-04-28
### Added
- Hardened enterprise version of the wrapper script
- Dependency validation (erase-install, swiftDialog)
- Improved LaunchDaemon lifecycle management
- Unified logging system
- Dynamic config section (timeouts, max deferrals)

---

## [1.0.1] - 2025-04-28
### Added
- MIT License header
- Integrated erase-install `--test-run` mode for dry-run testing

---

## [1.0.0] - 2025-04-28
### Initial Release
- Basic silent orchestration wrapper for erase-install
- Supports up to 3 x 24-hour deferrals
- User prompt via swiftDialog
- Smart enforcement of macOS upgrades