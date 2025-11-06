# Changelog

All notable changes to this project will be documented in this file.

## [1.7.2] - 2025-11-05
### 🔥 CRITICAL FIX - Version Detection Returns Wrong macOS Version

#### Fixed - get_available_macos_version() Not Filtering by INSTALLER_OS
- **CRITICAL FIX**: Fixed `get_available_macos_version()` to filter by INSTALLER_OS major version
- **Root Cause**: Function called `erase-install --list` without `--os` parameter, returning all macOS versions
- **Previous Behavior**: Function returned macOS 26.x (Tahoe) as latest, stored as targetOSVersion in plist
- **Resolution**:
  - Added `--os "${INSTALLER_OS}"` to erase-install --list call (line 1414)
  - Updated SOFA fallback to loop through versions and match major version (lines 1450-1465)
- **Impact**:
  - targetOSVersion now correctly set to latest macOS 15.x instead of 26.x
  - Version checks now compare against correct target version
  - Script behavior now matches INSTALLER_OS configuration
  - Eliminates false "OS not at target" detections

---

## [1.7.1] - 2025-11-05
### 🔥 CRITICAL FIX - Target macOS Version Not Being Passed to erase-install

#### Fixed - Missing --os Parameter
- **CRITICAL FIX**: Added missing `--os` parameter when calling erase-install.sh
- **Root Cause**: Script set `INSTALLER_OS="15"` but never passed `--os 15` to erase-install command
- **Previous Behavior**: erase-install defaulted to latest available macOS (15.2.6/build 26) ignoring INSTALLER_OS setting
- **Resolution**: Added `--os $INSTALLER_OS` parameter to command builder (line 4472-4476)
- **Impact**:
  - Script now correctly uses cached macOS 15 installer if available
  - Downloads specific macOS 15 version instead of latest available
  - Honors INSTALLER_OS configuration setting
  - Prevents unexpected OS version installations
  - Reduces bandwidth usage by utilizing cached installers

---

## [1.7.0] - 2025-08-04
### 🎉 PRODUCTION READY - Fixed Critical Scheduled Installation and Counter Reset Bugs

#### Fixed - Scheduled Installation Execution
- **CRITICAL FIX**: Fixed helper script syntax error preventing scheduled installations from executing
- **Root Cause**: Orphaned `else` statement in helper script template causing bash syntax error
- **Resolution**: Corrected `if/else/fi` structure in helper script template around line 2829
- **Impact**: Scheduled installations now execute properly when "Continue Now" is clicked

#### Fixed - Race Condition in Counter Management  
- **CRITICAL FIX**: Fixed race condition causing abort count corruption after successful installations
- **Root Cause**: Watchdog script processing stale abort signals after installation completed
- **Resolution**: Added installation completion check before abort processing in watchdog template
- **Impact**: Abort counts no longer get corrupted (jumping from 0 to 3) after successful installations

#### Fixed - Counter Reset Logic for Scheduled Installations
- **CRITICAL FIX**: Added missing reset logic to scheduled installation workflow
- **Root Cause**: Reset logic only existed in main script's `run_erase_install()`, not in watchdog template
- **Resolution**: Added comprehensive counter reset logic to watchdog script after successful installation
- **Impact**: Both immediate and scheduled installations now properly reset deferral and abort counts to 0

#### Fixed - Watchdog Abort Processing
- **CRITICAL FIX**: Prevented watchdog script from processing abort logic after successful installation
- **Root Cause**: Watchdog continued abort detection and increment logic even after installation completed
- **Resolution**: Added installation success check to skip abort processing when no longer needed
- **Impact**: Eliminates spurious abort count increments and ensures clean installation completion

### Enhanced - Complete System Integration
- **ENHANCED**: All three core systems now work together seamlessly:
- **Deferral System**: 0/3 → 1/3 → 2/3 → 3/3 → force install → reset to 0/3 ✅
- **Abort System**: 0/3 → 1/3 → 2/3 → 3/3 → no abort button → reset to 0/3 ✅  
- **Scheduled Installation**: Dialog → Continue → Installation → Counter Reset ✅
- **ENHANCED**: Comprehensive logging and error handling for debugging scheduled installation issues
- **ENHANCED**: Robust state management with proper counter persistence and reset functionality

### Testing Results - Complete Validation
- ✅ **Deferral System**: Tested complete 0→1→2→3→force install→reset cycle
- ✅ **Abort System**: Tested complete 0→1→2→3→no abort button→reset cycle  
- ✅ **Scheduled Installation**: Verified dialog appears, installation executes, counters reset
- ✅ **Force Install Modes**: Confirmed both defer and abort limits properly enforced
- ✅ **Counter Resets**: Verified reset works for both immediate and scheduled installations
- ✅ **Race Condition**: Confirmed abort counts no longer get corrupted after installation
- ✅ **Syntax Errors**: Confirmed scheduled installations execute without script failures

### Production Status
- 🚀 **ENTERPRISE READY**: All critical bugs fixed, complete functionality verified
- 🚀 **TESTED**: Comprehensive testing of all user workflows and edge cases completed
- 🚀 **STABLE**: No known bugs remaining, ready for production deployment
- 🚀 **DOCUMENTED**: Full changelog and documentation updated for deployment

---

## [1.6.5] - 2025-07-07
### Fixed - Deferral State Management
- **CRITICAL FIX**: Removed premature `reset_deferrals()` calls from "Install Now" and "Schedule Today" cases
- **CRITICAL FIX**: Removed premature `reset_all_counters()` call from force install case  
- **ENHANCED**: Added proper `reset_all_counters()` only after successful `run_erase_install()` completion
- **VERIFIED**: Deferral progression now works correctly: 0/3 → 1/3 → 2/3 → 3/3
- **VERIFIED**: Force install dialog correctly shows only "Install Now" and "Schedule Today" (no defer option) after max deferrals reached

### Fixed - Emergency Abort Functionality  
- **CRITICAL FIX**: Enhanced abort button detection in helper script with comprehensive logging
- **CRITICAL FIX**: Improved abort signal file creation and verification process
- **CRITICAL FIX**: Enhanced watchdog abort processing with detailed step-by-step logging
- **CRITICAL FIX**: Improved abort daemon creation and loading verification with retry logic
- **CRITICAL FIX**: **NEW** - Fixed abort context scheduling failure when rescheduling from abort daemon
- **ENHANCED**: Added detailed abort count increment verification and error handling
- **ENHANCED**: Added comprehensive time calculation logging for abort reschedule
- **ENHANCED**: Added daemon loading verification with multiple fallback methods
- **ENHANCED**: **NEW** - Added abort context detection and selective cleanup during rescheduling
- **VERIFIED**: Emergency abort now properly creates and loads abort daemons for rescheduling
- **VERIFIED**: **NEW** - Complete abort workflow: abort → daemon execution → rescheduling → new daemon creation

### Testing Improvements
- **ENHANCED**: Added extensive debug logging throughout abort processing workflow
- **ENHANCED**: Added abort signal file creation verification with sudo fallback
- **ENHANCED**: Added daemon plist validation and loading status verification
- **ENHANCED**: Added user notification improvements for abort confirmation
- **ENHANCED**: **NEW** - Added daemon creation verification with fallback detection methods
- **ENHANCED**: **NEW** - Added abort context logging for troubleshooting scheduling issues

### Technical Details
- Fixed helper script abort detection to properly create `/var/tmp/erase-install-abort-{run_id}` files
- Enhanced watchdog script abort processing with detailed logging at each step
- Improved abort daemon loading with `launchctl load`, `bootstrap`, and `kickstart` fallback methods
- Added comprehensive verification of abort daemon presence in launchctl after loading
- Enhanced abort count increment verification with plist read-back confirmation
- **NEW**: Fixed abort context scheduling with `RUNNING_FROM_ABORT_DAEMON` detection
- **NEW**: Added selective LaunchDaemon cleanup to preserve abort functionality during rescheduling
- **NEW**: Enhanced scheduled daemon creation verification to ensure successful completion

### Production Status
- ✅ **COMPLETE**: Deferral system fully functional (3 deferrals max with proper progression)
- ✅ **COMPLETE**: Abort system fully functional (3 aborts max with automatic rescheduling)  
- ✅ **COMPLETE**: State management integration (defer/abort count tracking across executions)
- ✅ **COMPLETE**: Force install enforcement (removes defer option after limits reached)
- ✅ **COMPLETE**: Abort context scheduling (successful rescheduling from abort daemon execution)
- 🚀 **READY**: Production deployment with comprehensive deferral and abort functionality

---

## 1.6.4 - 2025-07-07
### Fixed
- Fixed critical issue with second deferral not working properly
- Resolved state management inconsistency in deferral logic by using increment_defer_count() function instead of direct plist manipulation
- Fixed state variables not being refreshed after defer count increments
- Ensured proper synchronization of CURRENT_DEFER_COUNT and FORCE_INSTALL variables

### Improved
- Simplified get_deferral_state() function to remove duplicate variable exports
- Enhanced state consistency by adding automatic state refresh after defer count changes
- Improved reliability of deferral workflow for both test mode and production deferrals

### Technical Changes
- Replaced direct `defaults write` calls in deferral logic with proper state management functions
- Added get_installation_state() call after increment_defer_count() to refresh exported variables
- Streamlined backward compatibility function for cleaner code maintenance

---

## 1.6.3 - 2025-05-19
### Added
- Comprehensive validation for watchdog script before execution
- Enhanced verification of critical security parameters
- Improved daemon loading with retry logic
- Better verification of abort schedule daemon

### Fixed
- Local variable issues in cleanup background process
- Inconsistent handling of abort daemon creation and loading
- Improved cleanup process for orphaned daemons
- Enhanced error handling during daemon creation

### Changed
- Refactored daemon loading process for better reliability
- Improved parameter validation approach for watchdog scripts
- Enhanced logging of critical operations for better debugging
- Standardized daemon verification across defer and abort modes

---

## [1.6.2] - 2025-05-19
### Added
- Specialized test functions for different OS version check contexts
- Detailed version component comparison in test logs
- Enhanced watchdog script template with better test mode logging
- New test_deferral_os_check function specifically for testing deferral scenarios
- Improved version extraction from multiple sources (erase-install, SOFA)

### Fixed
- Redundant OS version checks in testing workflow
- Confusing log output during test mode execution
- Inconsistent test behavior between initial and scheduled checks
- Edge cases in version component comparison for minor versions

### Improved
- Separated initial OS check from deferral check in test mode
- More informative test mode logging with clear section markers
- Better diagnostic information in version check test output
- Clearer distinction between test functions and core check functions
- Version detection from multiple sources with better fallback behavior

---

## [1.6.1] - 2025-05-19
### Added
- Version detection from GitHub releases page to always get latest available version
- Multiple download URL patterns with intelligent fallbacks
- File size verification to ensure complete and valid downloads
- Direct script download fallback when package installation fails
- Multiple path checking for more robust dependency detection

### Improved
- Enhanced `install_erase_install` function with more reliable download mechanisms
- Better error handling with detailed logging during dependency installation
- More thorough verification of installed components after download
- Improved path detection for components installed in non-standard locations
- The `dependency_check` function now handles error conditions more gracefully
- Added post-installation verification with comprehensive path checks
- Enhanced version checking to verify functionality, not just presence

---

## [1.6.0] - 2025-05-18
### Added
- Emergency abort functionality for scheduled installations
- Configurable abort button in scheduled installation dialogs
- User-defined abort button text and appearance
- Ability to limit number of aborts with MAX_ABORTS setting
- Automatic rescheduling after abort with configurable defer time
- Added SCHEDULED_CONTINUE_HEIGHT and SCHEDULED_CONTINUE_WIDTH parameters

### Improved
- Enhanced dialog appearance with larger windows and improved readability
- Increased dialog widths and font sizes for better visibility
- Improved mutex handling between UI helper and watchdog script
- Fixed race conditions in multi-process communication
- Strengthened error handling for edge cases in scheduled installations

---

## v1.5.5 - Added Pre-Authentication Notice Feature

- Added configurable pre-authentication notice dialog before admin credentials prompt
- New configuration option to enable/disable the notice dialog
- Customizable messaging to guide users on obtaining admin rights if needed
- Enhanced user experience for standard users in Jamf Connect environments
- Implemented in both direct execution and scheduled installation workflows
- Added dialog customization options (title, message, button text, timeout, icon)
- Test mode compatibility with special indicators

---

## v1.5.4 - Fixed Scheduled Installation Execution
- Fixed critical issue with scheduled installation not running properly
- Corrected command construction in watchdog script to properly pass variables 
- Enhanced error handling and logging for scheduled installations
- Improved variable passing between main script and watchdog script
- Added more detailed execution logs to help with troubleshooting
- Added explicit variable declaration at watchdog script creation time

---

## [1.5.3] - 2025-05-10
### Added
- Comprehensive Test Mode features to streamline development and QA workflows:
- OS Version Check Test Mode to enable testing on systems already at target OS version
- 5-minute quick deferrals when in TEST_MODE instead of waiting 24 hours
- Command-line parameter `--test-os-check` to enable test mode directly
- Custom dialog text showing "Defer 5 Minutes (TEST MODE)" for visual clarity
- Watchdog-ready flag to ensure proper synchronization before trigger creation
- Detailed test function `test_os_version_check()` with comprehensive version logging
- Clear visual indicators and messaging when running in test mode
- Configuration toggle `SKIP_OS_VERSION_CHECK` to enable testing regardless of OS version
- Race condition prevention with synchronization between UI helper and watchdog script

### Changed
- Modified all OS version check code paths to conditionally bypass based on test mode
- Updated deferral mechanism to use 5-minute intervals in test mode (24 hours in production)
- Enhanced scheduling mechanism to detect and prevent race conditions
- Improved post-installation cleanup to preserve scheduled jobs in test mode
- Centralized log path handling to ensure consistency across all execution contexts
- Expanded error handling in time-related functions with better fallback mechanisms
- Updated the set_options() function to dynamically select deferral text based on mode

### Fixed
- Issue where systems already at target OS couldn't be used for testing upgrade workflows
- Race condition between helper script and watchdog during scheduled installations
- Case statement not recognizing test mode deferral option text
- Inconsistent variable initialization in time validation functions
- Potential issues with octal interpretation of time values
- Improved error handling with fallbacks in time-related functions

---

## [1.5.2] - 2025-05-04
### Fixed
- Fixed octal parsing errors in time calculation functions (resolving "value too great for base" errors)
- Properly handled leading zeros in time values with explicit base-10 conversion
- Corrected handling of scheduled times like 08:00 and 09:00 that were previously misinterpreted
- Enhanced time validation in scheduling functions
- Added explicit base-10 parsing for all time-related operations
- Improved error messages for time formatting issues
- Standardized time handling across scheduling and deferral functions

### Changed
- Updated configuration variables section for more consistent organization
- Reorganized core settings and file paths in configuration section
- Standardized variable naming conventions throughout the script

---

## [1.5.1] - 2025-05-03
### Added
- Directory-based locking mechanism for improved process management
- Detailed lock debugging and status reporting
- Comprehensive stale lock detection and recovery

### Changed
- Replaced file-based locking with more atomic directory-based approach
- Improved lock timeout handling with descriptive error messages
- Enhanced process isolation through robust locking

### Removed
- Eliminated flock command dependency for better cross-platform compatibility
- Removed conditional code paths in locking mechanism for simpler maintenance

### Fixed
- Fixed race condition in lock acquisition process
- Fixed potential deadlocks when multiple instances try to run simultaneously
- Improved cleanup of lock artifacts during process termination
- Enhanced error handling during force-break of stale locks

---

## [1.5.0] - 2025-05-02
### Added
- Snooze functionality for short-term deferrals (1-4 hours)
- "Install at next login" scheduling option
- Comprehensive system diagnostics reporting
- Enhanced progress indication during caching phase

### Improved
- Session management for dialog display across all user contexts
- Privilege separation for core processes
- Script signature verification during runtime
- Visual feedback for approaching scheduled times
- More robust multi-user environment handling

### Fixed
- Dialog appearance issues in certain user session contexts
- Race conditions during LaunchDaemon management
- Improved handling of non-standard LaunchDaemon unloading cases
- Enhanced error recovery during scheduled installations

---

## [1.4.19] - 2025-05-01
### Changed
- Switched from system LaunchDaemon to user LaunchAgent for scheduled installations
- Added multi-layered approach to UI visibility for scheduled runs
- Enhanced console user detection with multiple fallback methods
- Improved environment variable handling for GUI displays

### Fixed
- Resolved critical issue with UI not displaying during scheduled runs
- Added robust user session detection and management
- Implemented AppleScript notification as fallback mechanism
- Fixed environment variable handling for GUI access in scheduled mode

---

## [1.4.18] - 2025-05-01
### Added
- Lock file mechanism to prevent multiple simultaneous scheduled executions
- Process tracking and cleanup for scheduled runs
- Enhanced UI handling for scheduled installations
- Native AppleScript notification as fallback for scheduled alerts
- Multi-layered approach to ensure dialog visibility in all contexts
- SessionCreate key to LaunchDaemon for proper UI session access

### Improved
- Robust console user detection with multiple fallback methods
- Better dialog visibility in scheduled mode with proper user context
- Enhanced cleanup routine with retry mechanism
- Added resource limits and process control to LaunchDaemons
- Standardized environment variables for scheduled runs
- Focus management for dialog windows using AppleScript activation

### Fixed
- Dialog windows failing to appear during scheduled execution
- UI visibility problems when running as root
- Process cleanup and tracking during scheduled executions
- Dialog window positioning and focus in scheduled mode
- Environment variables for proper user session access

---


## [1.4.17] - 2025-04-30
### Added
- Implemented centralized LaunchDaemon control mechanism

### Improved
- Enhanced LaunchDaemon cleanup to find and remove all instances
- Added logging for LaunchDaemon discovery and removal
- Added error handling for failed removals
- Optimized window behavior for different installation paths
- Streamlined "Install Now" path to go directly to installation without countdown

### Fixed
- Fixed time formatting in printf commands to prevent "invalid number" errors
- Improved handling of time values with leading zeros
- Fixed duplicate window display in "Install Now" workflow
- Ensured proper LaunchDaemon creation/removal for scheduled installations

---

## [1.4.16] - 2025-04-30
### Fixed
- Fixed printf errors when formatting times with leading zeros (like 08:00, 09:30)
- Added explicit base-10 interpretation to prevent octal parsing errors

---

## [1.4.15] - 2025-04-30
### Changed
- Removed --mini flag from all SwiftDialog commands to fix window display issues
- Increased window dimensions for better display of UI elements:
  - Main dialog: 250×550 (was 200×500)
  - Scheduling dialog: 280×500 (was 230×450)
  - Countdown window: 180×450 (was 140×380)

### Fixed
- Fixed issues with dropdown lists being cut off or partially visible
- Improved overall user experience with properly sized dialog windows

---

## [1.4.14] - 2025-04-30
### Added
- Implemented automatic continue functionality when countdown reaches zero
- Added --mini flag to all SwiftDialog commands for consistent window sizing

### Fixed
- Enhanced secondary schedule window with proper countdown timer
- Improved countdown display with continuous updates and progress bar
- Better user experience with clear countdown progress indication

---

## [1.4.13] - 2025-04-30
### Fixed
- Fixed scheduled installation countdown window not appearing when installation was scheduled for later
- Modified LaunchDaemon creation to ensure wrapper script is called with proper parameters
- Ensured consistent user experience between immediate and scheduled installations

---

## [1.4.12] - 2025-04-30
### Fixed
- SwiftDialog `SelectedOption` parsing reliability when multiline or non-jq JSON
- Logging of times now consistently zero-padded (`13:00` instead of `13:0`)
- `create_scheduled_launchdaemon` now safely unloads active LaunchDaemons using `bootout`
- Deferral expiration now properly routes to `show_preinstall` instead of direct install
- Improved fallback for missing SwiftDialog selection fields

### Improved
- LaunchDaemon creation logging now includes padded timestamps
- Safer handling of deferral logic edge cases near 72h timeout window

---

## [1.4.11] - 2025-04-28
### Fixed
- LaunchDaemon consistency: ensured proper recreation and loading when scheduling times
- Improved error handling during LaunchDaemon creation
- Resolved edge case where LaunchDaemon was not recreated if a malformed time was selected

### Improved
- Logging system enhanced with rotation based on log size (10MB max, 5 backups)
- Timestamps and log messages standardized across all log levels
- Added debug-level tracing of SwiftDialog raw output and exit codes

---

## [1.4.10] – 2025-04-30
### Fixed
- Resolved Bash error when parsing scheduled times like `08:00` or `09:00`:
- Bash interpreted these as octal numbers, causing `value too great for base` errors.
- Updated all time parsing logic to use `10#` base-10 safety in arithmetic operations.

---

## [1.4.9] – 2025-04-29
### Added
- Enhanced logging system with log rotation
- Additional logging levels (TRACE, VERBOSE, SYSTEM, AUDIT)
- System information logging at startup
- Automatic log file management and rotation
- Expanded logging contexts for better debugging

### Changed
- Improved log format consistency
- Enhanced log file permissions handling
- Added size-based log rotation with configurable limits

---

## [1.4.8] – 2025-04-29
### Added
- Enhanced dropdown menu UI with proper SwiftDialog select interface
- Added automatic deferral reset after successful install or scheduling
- Implemented 24-hour re-prompt scheduling for deferrals
- Dynamic dropdown options based on available deferrals

### Changed
- Improved selection handling and validation
- Better JSON output parsing from SwiftDialog
- Updated LaunchDaemon handling for deferrals and scheduling
- Improved scheduling dialog with dynamic time slots and tomorrow options

### Fixed
- Fixed dropdown selection parsing from SwiftDialog output
- Corrected deferral count tracking and reset logic
- Resolved issues with option visibility after max deferrals

---

## [1.4.7] – 2025-04-29
### Fixed
- Fixed JSON parsing to correctly extract dropdown selections from nested SwiftDialog output structure.

---

## [1.4.6] – 2025-04-29
### Changed
- Switched to dropdown UI with three options (Install Now, Schedule Today, Defer 24 Hours) via SwiftDialog.

---

## [1.4.5] – 2025-04-29
### Changed
- Reverted to multi-button UI: Install Now, Schedule Today, Defer 24 Hours.

---

## [1.4.4] – 2025-04-29
### Changed
- Updated logging functions to use simplified `date +'%Y-%m-%d %H:%M:%S'` syntax.

---

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