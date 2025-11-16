#!/bin/bash

# Strict error handling for production reliability
# Exit on errors, undefined variables, and pipeline failures
set -euo pipefail

# Error trap for debugging
error_handler() {
    local line_number=$1
    local bash_lineno=$2
    local command="$3"
    local error_code=$4

    echo "[CRITICAL ERROR] Script failed at line ${line_number} (in function called from line ${bash_lineno})" >&2
    echo "[CRITICAL ERROR] Command: ${command}" >&2
    echo "[CRITICAL ERROR] Exit code: ${error_code}" >&2
    echo "[CRITICAL ERROR] Please check logs at: ${WRAPPER_LOG:-/var/log/erase-install-wrapper.log}" >&2

    # Cleanup on error if possible
    if declare -f cleanup_on_error >/dev/null 2>&1; then
        cleanup_on_error || true
    fi

    exit "${error_code}"
}

# Set error trap
trap 'error_handler ${LINENO} ${BASH_LINENO} "$BASH_COMMAND" $?' ERR

#######################################################################################################################################################################
#
# MacJediWizard Consulting, Inc.
# Copyright (c) 2025 MacJediWizard Consulting, Inc.
# All rights reserved.
# Created by: William Grzybowski
#
# Project: Jamf Silent macOS Upgrade Scheduler
# Script: erase-install-defer-wrapper.sh
#
# Description:
# A silent macOS upgrade orchestration wrapper for Graham Pugh's erase-install, designed for enterprise environments using Jamf Pro or other MDMs.
# - Silently caches macOS installers
# - Prompts users with a dropdown selection in SwiftDialog for three actions
# - Allows 24-hour deferral (up to 3 times per script version)
# - Forces install after max deferral or timeout (72 hours)
# - Supports scheduling install later today
# - Fully supports erase-install's --test-run for dry-run testing
# - Automatically installs missing dependencies if enabled
# - Configurable dialog text, dropdown options, and window positioning
#
# Requirements:
# - macOS 11+
# - erase-install v37.0+
# - swiftDialog installed on client Macs
#
# License:
# This script is licensed under the MIT License.
# See the LICENSE file in the root of this repository.
#
# CHANGELOG:
# v2.0.0 - MAJOR RELEASE: JSON-based configuration management
#         - NEW: JSON configuration file support for centralized settings management
#         - NEW: Managed preferences support for Jamf Configuration Profile deployment
#         - NEW: load_json_config() function loads settings from JSON with fallback to script defaults
#         - NEW: Four-tier configuration priority: Custom (--config) > Managed JSON > Local JSON > Script Defaults
#         - NEW: --show-config command to display current configuration without running script
#         - NEW: --config=/path/to/file.json parameter to specify custom JSON config location
#         - NEW: Configuration validation with warnings for invalid values
#         - NEW: Enhanced configuration logging showing all loaded settings
#         - ENHANCED: All User Configuration Section settings can now be controlled via JSON
#         - ENHANCED: Instant settings updates via Jamf without redeploying script
#         - ENHANCED: Per-department configuration support with different JSON configs
#         - ENHANCED: Command-line parameter processing for custom configs and testing
#         - BACKWARDS COMPATIBLE: Falls back to hardcoded defaults if no JSON present
#         - DOCUMENTATION: Complete JSON config examples and Jamf deployment guides
#         - JAMF READY: Deploy JSON via Configuration Profile Files and Processes payload
#         - CRITICAL FIX: Actually implemented --os parameter in run_erase_install() function
#         - NOTE: v1.7.1 claimed to fix this but implementation was missing from run_erase_install()
#         - FIXED: Script now correctly passes INSTALLER_OS to erase-install.sh in ALL execution paths
#         - IMPACT: Ensures cached installers are used and correct OS version is downloaded
# v1.7.2 - CRITICAL FIX: Fixed version detection to filter by INSTALLER_OS major version
#         - FIXED: get_available_macos_version() now uses --os parameter with erase-install --list
#         - FIXED: SOFA fallback now searches for matching major version instead of using latest
#         - IMPACT: targetOSVersion now correctly set to latest macOS 15.x instead of 26.x
#         - IMPACT: Version checks now compare against correct target version
# v1.7.1 - CRITICAL FIX: Added missing --os parameter to erase-install command
#         - FIXED: Script now passes INSTALLER_OS setting to erase-install using --os parameter
#         - FIXED: erase-install was defaulting to latest macOS (15.2.6/build 26) instead of configured version
#         - IMPACT: Script now correctly uses cached macOS 15 installer if available
#         - IMPACT: Downloads specific macOS 15 version instead of latest available
#         - IMPACT: Reduces bandwidth usage by utilizing cached installers
# v1.7.0 - PRODUCTION READY: Fixed critical scheduled installation and counter reset bugs
#         - FIXED: Helper script syntax error preventing scheduled installations from executing
#         - FIXED: Race condition causing abort count corruption after successful installations
#         - FIXED: Missing reset logic in scheduled installations (counters stayed at max values)
#         - FIXED: Watchdog script abort processing after successful installation completion
#         - ENHANCED: Added comprehensive reset logic to scheduled installation workflow
#         - ENHANCED: Improved error handling and logging for scheduled installation debugging
#         - VERIFIED: Complete deferral system working (0/3 → 1/3 → 2/3 → 3/3 → force install → reset)
#         - VERIFIED: Complete abort system working (0/3 → 1/3 → 2/3 → 3/3 → no abort button → reset)
#         - VERIFIED: Scheduled installations execute properly with UI and complete with counter reset
# v1.6.5 - COMPLETE: Fixed deferral state persistence and abort functionality with scheduling
#         - FIXED: Removed premature reset calls that were clearing deferral state too early
#         - FIXED: Added proper reset only after successful installation completion
#         - FIXED: Enhanced abort button detection with comprehensive logging
#         - FIXED: Improved abort daemon creation and loading verification
#         - FIXED: Added detailed abort signal file creation and validation
#         - FIXED: Enhanced watchdog abort processing with step-by-step logging
#         - FIXED: CRITICAL abort context scheduling failure when rescheduling from abort daemon
#         - VERIFIED: Deferral progression now works correctly (0/3 → 1/3 → 2/3 → 3/3)
#         - VERIFIED: Force install correctly shows only "Install Now" and "Schedule Today" after max deferrals
#         - VERIFIED: Emergency abort now properly reschedules installations with working daemon creation
#         - VERIFIED: Complete abort workflow: abort → daemon execution → rescheduling → new daemon creation
#         - PRODUCTION READY: Both deferral and abort systems fully functional and tested
# v1.6.4 - Fixed critical second deferral issue
#         - Resolved state management inconsistency in deferral logic
#         - Fixed state variables not being refreshed after defer count increments  
#         - Improved reliability of deferral workflow for both test and production modes
#         - Simplified get_deferral_state() function and enhanced state consistency
#         - Replaced direct plist manipulation with proper state management functions
# v1.6.3 - Improved reliability of LaunchDaemon creation and loading
#         - Added script validation for watchdog and abort daemons
#         - Enhanced parameter verification to ensure critical settings are maintained
#         - Fixed local variable issues in watchdog cleanup process
#         - Improved abort functionality to match defer reliability
#         - Added better daemon verification for both scheduled and abort modes
# v1.6.2 - Enhanced OS version check testing
#         - Added specialized test functions for different OS version check contexts
#         - Separated initial OS check from deferral check in test mode
#         - Fixed redundant version checks in testing workflow
#         - Improved test logging with detailed version component comparison
#         - Enhanced watchdog template with more comprehensive test logging
#         - Added test_deferral_os_check function for scheduled installations
#         - Improved version extraction from erase-install and SOFA sources
# v1.6.1 - Enhanced dependency management functionality
#         - Improved download mechanism for erase-install with GitHub releases version detection
#         - Added robust URL pattern handling with multiple fallback methods
#         - Enhanced verification of installed components with comprehensive path checking
#         - Added version detection from GitHub releases page to always get latest version
#         - Improved error handling with detailed logging during dependency installation
#         - Added file size verification to ensure complete downloads
#         - Enhanced post-installation verification with multiple path checks
#         - Fixed direct script download as fallback when package download fails
# v1.6.0 - Added emergency abort functionality for scheduled installations
#         - Configurable abort button in scheduled installation dialogs 
#         - User-defined abort button text and appearance
#         - Ability to limit number of aborts with MAX_ABORTS setting
#         - Automatic rescheduling after abort with configurable defer time
#         - Enhanced dialog appearance with larger windows and improved readability
#         - Increased dialog widths and font sizes for better visibility
#         - Added SCHEDULED_CONTINUE_HEIGHT and SCHEDULED_CONTINUE_WIDTH parameters
#         - Improved mutex handling between UI helper and watchdog script
#         - Fixed race conditions in multi-process communication
#         - Strengthened error handling for edge cases in scheduled installations
# v1.5.5 - Added pre-authentication notice dialog for standard users with Jamf Connect
#         - Feature can be enabled/disabled via SHOW_AUTH_NOTICE configuration
#         - Customizable dialog to inform users before admin credentials are requested
#         - Implemented in both direct and scheduled installation workflows
#         - Added dialog appearance and behavior customization options
#         - Enhanced user experience for environments using Jamf Connect or Self Service
# v1.5.4 - Fixed scheduled installation execution issues
#         - Corrected command construction in watchdog script
#         - Enhanced variable passing between main script and watchdog script
#         - Improved error handling and logging
# v1.5.3 - Added comprehensive Test Mode features to streamline development and QA
#         - Added OS Version Check Test Mode to bypass version checking for testing
#         - Implemented 5-minute quick deferrals in TEST_MODE instead of 24 hours 
#         - Added SKIP_OS_VERSION_CHECK toggle in feature settings
#         - Added command-line --test-os-check parameter support
#         - Fixed race condition between UI helper and watchdog script with mutex flag
#         - Enhanced time validation with better error handling and robust fallbacks
#         - Improved post-installation cleanup to preserve test resources
#         - Centralized log path handling for consistent logging across contexts
#         - Added test-specific dialog text for clear visual indicators in test mode
# v1.5.2 - Fixed 24-hour time calculation issues with proper base-10 conversion
#         - Corrected octal parsing errors in time handling functions
#         - Enhanced time validation in scheduling functions
#         - Improved error handling for time-based operations
#         - Updated configuration variables for more consistent organization
# v1.5.1 - Implemented robust directory-based locking mechanism
#         - Removed flock dependency for improved cross-platform compatibility
#         - Enhanced lock acquisition and release with better error handling
#         - Fixed race conditions in lock management
#         - Improved stale lock detection and recovery
# v1.5.0 - Added snooze functionality and login-time installation scheduling
#         - Implemented comprehensive system diagnostics reporting
#         - Enhanced session management for dialog display in all contexts
#         - Improved privilege separation for core processes
#         - Added visual feedback for approaching scheduled times
#         - Fixed dialog visibility issues and race conditions during LaunchDaemon management
#         - Hardened script with enhanced error recovery during scheduled installations
# v1.4.18 - Enhanced scheduled execution reliability and UI display
#         - Fixed dialog visibility issues in scheduled mode with multi-layered approach
#         - Added native AppleScript notification as fallback for scheduled alerts
#         - Improved console user detection with multiple fallback methods
#         - Enhanced LaunchDaemon with SessionCreate for proper UI interaction
#         - Added lock file mechanism to prevent multiple simultaneous executions
#         - Improved scheduled installation UI visibility and user context handling
#         - Added process tracking and enhanced cleanup procedures
#
########################################################################################################################################################################
########################################################################################################################################################################
#
# User Configuration Section
#
# This section contains all configurable options for the erase-install-defer-wrapper.sh
# Modify these settings to customize the behavior of the script
#
########################################################################################################################################################################
#
# ---- Core Settings ----
SCRIPT_VERSION="2.0.0"              # Current version of this script
INSTALLER_OS="15"                   # Target macOS version number to install in prompts
MAX_DEFERS=3                        # Maximum number of times a user can defer installation
FORCE_TIMEOUT_SECONDS=259200        # Force installation after timeout (72 hours = 259200 seconds)
#
# ---- File Paths ----
PLIST="/Library/Preferences/com.macjediwizard.eraseinstall.plist"  # Preferences file location
SCRIPT_PATH="/Library/Management/erase-install/erase-install.sh"    # Grham Pugh Erase-Install Script Path
DIALOG_BIN="/Library/Management/erase-install/Dialog.app/Contents/MacOS/Dialog"   # Grham Pugh Swift Dialog Path
[ ! -x "$DIALOG_BIN" ] && DIALOG_BIN="/usr/local/bin/dialog"    # Fallback to traditional location if primary doesn't exist
LAUNCHDAEMON_LABEL="com.macjediwizard.eraseinstall.schedule"       # Label for LaunchDaemon
LAUNCHDAEMON_PATH="/Library/LaunchDaemons/${LAUNCHDAEMON_LABEL}.plist"  # Path to LaunchDaemon
#
# ---- Feature Toggles ----
TEST_MODE=false                      # Set to false for production (when true, deferrals are shortened to 5 minutes)
PREVENT_ALL_REBOOTS=false            # SAFETY FEATURE: Set to true to prevent any reboots during testing
SKIP_OS_VERSION_CHECK=false         # Set to true to skip OS version checking for testing purposes
AUTO_INSTALL_DEPENDENCIES=true      # Automatically install erase-install and SwiftDialog if missing
DEBUG_MODE=false                     # Enable detailed logging
#
# ---- Logging Configuration ----
MAX_LOG_SIZE_MB=10                  # Maximum log file size before rotation
MAX_LOG_FILES=5                     # Number of log files to keep when rotating
#
# ---- Main Dialog UI Configuration ----
DIALOG_TITLE="macOS Upgrade Required"          # Title shown on main dialog
DIALOG_TITLE_TEST_MODE="$DIALOG_TITLE\n                (TEST MODE)"   # Title for main dialog Test Mode
DIALOG_MESSAGE="Please install macOS ${INSTALLER_OS}. Select an action:"  # Main message text
DIALOG_ICON="SF=gear,weight=bold,size=128"                         # Icon (SF Symbol or path to image)
DIALOG_POSITION="topright"                     # Dialog position: topleft, topright, center, bottomleft, bottomright
DIALOG_HEIGHT=250                              # Dialog height in pixels
DIALOG_WIDTH=650                               # Dialog width in pixels
DIALOG_MESSAGEFONT="size=16"                   # Font size for dialog message
#
# ---- Dialog Button/Option Text ----
DIALOG_INSTALL_NOW_TEXT="Install Now"          # Text for immediate installation option
DIALOG_SCHEDULE_TODAY_TEXT="Schedule Today"    # Text for schedule option
DIALOG_DEFER_TEXT="Defer 24 Hours"             # Text for deferral option
DIALOG_DEFER_TEXT_TEST_MODE="Defer 5 Minutes   (TEST MODE)"  # Text for deferral option in test mode
DIALOG_CONFIRM_TEXT="Confirm"                  # Button text for confirmation dialogs
#
# ---- Pre-installation Dialog ----
PREINSTALL_TITLE="macOS Upgrade Starting"      # Title for pre-installation dialog
PREINSTALL_TITLE_TEST_MODE="$PREINSTALL_TITLE\n                (TEST MODE)"   # Title for pre-installation dialog Test Mode
PREINSTALL_MESSAGE="Your scheduled macOS upgrade is ready to begin.\n\nThe upgrade will start automatically in 60 seconds, or click Continue to begin now."  # Message text
PREINSTALL_PROGRESS_TEXT_MESSAGE="Installation will begin in 60 seconds..."   # Progress Text Message
PREINSTALL_CONTINUE_TEXT="Continue Now"        # Button text for continue button
PREINSTALL_COUNTDOWN=60                        # Countdown duration in seconds
PREINSTALL_HEIGHT=350                          # Height of pre-installation dialog
PREINSTALL_WIDTH=650                           # Width of pre-installation dialog
PREINSTALL_DIALOG_MESSAGEFONT="size=16"        # Font size for pre-installation dialog message
#
# ---- Scheduled Installation Dialog ----
SCHEDULED_TITLE="macOS Upgrade Scheduled"      # Title for scheduled dialog
SCHEDULED_TITLE_TEST_MODE="$SCHEDULED_TITLE\n                (TEST MODE)"   # Title for scheduled dialog Test Mode
SCHEDULED_MESSAGE="Your scheduled macOS upgrade is ready to begin.\n\nThe upgrade will start automatically in 60 seconds,\n\n or click Continue to begin now."  # Message text
SCHEDULED_PROGRESS_TEXT_MESSAGE="Installation will begin in 60 seconds....."   # Progress Text Message
SCHEDULED_CONTINUE_TEXT="Continue Now"        # Button text for continue button
SCHEDULED_COUNTDOWN=60                        # Countdown duration in seconds
SCHEDULED_HEIGHT=250                          # Height of scheduled dialog
SCHEDULED_WIDTH=650                           # Width of scheduled dialog
SCHEDULED_CONTINUE_HEIGHT=350                 # Height of scheduled dialog
SCHEDULED_CONTINUE_WIDTH=750                  # Width of scheduled dialog
SCHEDULED_DIALOG_MESSAGEFONT="size=16"        # Font size for scheduled dialog message                                 # Text for Info Text on left of window
#
# ---- Error Dialog Configuration ----
ERROR_DIALOG_TITLE="Invalid Time"              # Title for error dialog
ERROR_DIALOG_MESSAGE="The selected time is invalid.\nPlease select a valid time (00:00-23:59)."  # Error message
ERROR_DIALOG_ICON="SF=exclamationmark.triangle" # Icon for error dialog
ERROR_DIALOG_HEIGHT=350                        # Height of error dialog
ERROR_DIALOG_WIDTH=650                         # Width of error dialog
ERROR_CONTINUE_TEXT="OK"                       # Button text for continue button
#
# ---- Options passed to erase-install.sh ----
# These settings control which arguments are passed to Graham Pugh's script
REBOOT_DELAY=60                    # Delay in seconds before rebooting
REINSTALL=true                     # true=reinstall, false=erase and install
NO_FS=true                         # Skip file system creation
CHECK_POWER=true                   # Check if on AC power before installing
POWER_WAIT_LIMIT=300               # Wait time in seconds for power connection (default is 60)
# IMPORTANT: For laptops with very low battery, you may need to increase this value.
# This setting controls how long erase-install will wait for AC power to be connected
# before proceeding with installation. In environments with laptops frequently
# running on battery, consider increasing this value to give users more time
# to connect power when prompted.
MIN_DRIVE_SPACE=50                 # Minimum free drive space in GB
CLEANUP_AFTER_USE=true             # Clean up temp files after use
#
# ---- Authentication Notice Configuration ----
SHOW_AUTH_NOTICE=true                     # Set to false to disable the pre-authentication notice
AUTH_NOTICE_TITLE="Admin Access Required"  # Title for the authentication notice dialog
AUTH_NOTICE_TITLE_TEST_MODE="$AUTH_NOTICE_TITLE\n            (TEST MODE)"   # Title for auth notice dialog Test Mode
AUTH_NOTICE_MESSAGE="You will be prompted for admin credentials to complete the macOS upgrade.\n\nIf you do not have admin access, please use Jamf Connect or Self Service to elevate your permissions before continuing."  # Message to display
AUTH_NOTICE_BUTTON="I'm Ready to Continue" # Text for the continue button
AUTH_NOTICE_TIMEOUT=0                    # Timeout in seconds (0 = no timeout)
AUTH_NOTICE_ICON="SF=lock.shield"         # Icon (SF Symbol or path to image)
AUTH_NOTICE_HEIGHT=300                    # Dialog height in pixels
AUTH_NOTICE_WIDTH=750                     # Dialog width in pixels
#
# ---- Abort Button Configuration ----
ENABLE_ABORT_BUTTON=true                 # Enable/disable abort button in scheduled dialogs
ABORT_BUTTON_TEXT="Abort (Emergency)"    # Text for abort button
ABORT_DEFER_MINUTES=5                    # Minutes to defer when abort is used
MAX_ABORTS=3                             # Maximum number of abort actions allowed
ABORT_COUNTDOWN=15                      # Seconds to wait before abort takes effect
ABORT_HEIGHT=250                         # Dialog height in pixels
ABORT_WIDTH=750                          # Dialog width in pixels
ABORT_ICON="SF=exclamationmark.triangle" # Icon for error dialog
#
########################################################################################################################################################################
#
# ========================================
# JSON Configuration Loading (v2.0)
# ========================================
#
#######################################
# Get console user with multiple fallback methods
# Arguments:
#   None
# Returns:
#   Console username or empty string
#######################################
get_console_user() {
    local console_user=""

    # Method 1: stat on /dev/console
    console_user=$(stat -f%Su /dev/console 2>/dev/null || echo "")

    # Method 2: who command
    if [[ -z "$console_user" || "$console_user" == "root" ]]; then
        console_user=$(who | grep "console" | awk '{print $1}' | head -n1)
    fi

    # Method 3: scutil
    if [[ -z "$console_user" || "$console_user" == "root" ]]; then
        console_user=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && !/loginwindow/ { print $3 }')
    fi

    # Method 4: ls -l on /dev/console
    if [[ -z "$console_user" || "$console_user" == "root" ]]; then
        console_user=$(ls -l /dev/console 2>/dev/null | awk '{print $3}')
    fi

    echo "$console_user"
}

#######################################
# SECURITY: Validate positive integer within range
# Arguments:
#   $1 - Value to validate
#   $2 - Default value
#   $3 - Max value (optional, default 999999)
#   $4 - Allow zero (optional, default true)
# Returns:
#   Validated value or default
#######################################
validate_positive_integer() {
    local value="$1"
    local default="$2"
    local max="${3:-999999}"
    local allow_zero="${4:-true}"

    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        echo "$default"
        return 1
    fi

    if [[ "$allow_zero" != "true" && "$value" -eq 0 ]]; then
        echo "$default"
        return 1
    fi

    if [[ "$value" -gt "$max" ]]; then
        echo "$default"
        return 1
    fi

    echo "$value"
    return 0
}

#######################################
# SECURITY: Escape special characters for sed replacement
# Arguments:
#   $1 - String to escape
# Returns:
#   Escaped string safe for sed
#######################################
escape_sed() {
    printf '%s\n' "$1" | sed -e 's/[\/&|]/\\&/g'
}

#######################################
# SECURITY: Validate and sanitize file path
# Arguments:
#   $1 - Path to validate
#   $2 - Expected prefix (optional)
# Returns:
#   0 if valid, 1 if invalid
#######################################
validate_path() {
    local path="$1"
    local expected_prefix="${2:-}"

    # SECURITY FIX (Issue #27): Check for symbolic links
    if [[ -L "$path" ]]; then
        echo "[ERROR] Symbolic links not allowed: $path" >&2
        return 1
    fi

    # SECURITY FIX (Issue #27): Check for path traversal (including URL-encoded)
    if [[ "$path" == *".."* ]] || [[ "$path" == *"%2e"* ]] || [[ "$path" == *"%2E"* ]]; then
        echo "[ERROR] Path traversal detected in: $path" >&2
        return 1
    fi

    # SECURITY FIX (Issue #27): Use realpath for canonical resolution
    local canonical_path=""
    if [[ -e "$path" ]]; then
        # Use perl for canonical path (realpath not always available)
        canonical_path=$(perl -MCwd -e 'print Cwd::abs_path shift' "$path" 2>/dev/null)
        if [[ -z "$canonical_path" ]]; then
            echo "[ERROR] Cannot resolve canonical path: $path" >&2
            return 1
        fi

        # Verify no symlinks in path hierarchy
        local check_path="$canonical_path"
        while [[ "$check_path" != "/" ]]; do
            if [[ -L "$check_path" ]]; then
                echo "[ERROR] Symlink in path hierarchy: $check_path" >&2
                return 1
            fi
            check_path=$(dirname "$check_path")
        done
    else
        canonical_path="$path"
    fi

    # Validate against expected prefix
    if [[ -n "$expected_prefix" ]]; then
        local canonical_prefix
        if [[ -e "$expected_prefix" ]]; then
            canonical_prefix=$(perl -MCwd -e 'print Cwd::abs_path shift' "$expected_prefix" 2>/dev/null)
        else
            canonical_prefix="$expected_prefix"
        fi

        if [[ ! "$canonical_path" == "$canonical_prefix"* ]]; then
            echo "[ERROR] Path outside allowed directory: $canonical_path" >&2
            return 1
        fi
    fi

    # Check for null bytes
    if [[ "$path" == *$'\0'* ]]; then
        echo "[ERROR] Null byte detected in path" >&2
        return 1
    fi

    return 0
}

#######################################
# SECURITY: Create secure temporary file with mktemp
# Arguments:
#   $1 - Template name (e.g., "dialog-script")
#   $2 - Extension (optional, e.g., ".sh")
# Returns:
#   Path to created temp file
#######################################
create_secure_temp() {
    local template="$1"
    local extension="${2:-.tmp}"
    local temp_file

    temp_file=$(mktemp "/tmp/${template}.XXXXXXXXXX${extension}") || {
        echo "[ERROR] Failed to create secure temporary file" >&2
        return 1
    }

    # Set restrictive permissions immediately
    chmod 600 "$temp_file" || {
        rm -f "$temp_file"
        echo "[ERROR] Failed to set permissions on temporary file" >&2
        return 1
    }

    echo "$temp_file"
}

#######################################
# SECURITY: Create secure temporary directory with mktemp
# Arguments:
#   $1 - Template name (e.g., "download-pkg")
# Returns:
#   Path to created temp directory
#######################################
create_secure_temp_dir() {
    local template="$1"
    local temp_dir

    # Create temp directory with secure template
    temp_dir=$(mktemp -d "/tmp/${template}.XXXXXXXXXX") || {
        echo "[ERROR] Failed to create secure temporary directory" >&2
        return 1
    }

    # Set restrictive permissions immediately (700 - owner only)
    chmod 700 "$temp_dir" || {
        rm -rf "$temp_dir"
        echo "[ERROR] Failed to set permissions on temporary directory" >&2
        return 1
    }

    echo "$temp_dir"
}

#######################################
# SECURITY: Verify downloaded package integrity
# Arguments:
#   $1 - Path to package file
#   $2 - Package name (for logging)
# Returns:
#   0 if verification passes, 1 if fails
#######################################
verify_package_integrity() {
    local pkg_path="$1"
    local pkg_name="${2:-package}"

    if [[ ! -f "$pkg_path" ]]; then
        log_error "Package file not found: $pkg_path"
        return 1
    fi

    # 1. Verify minimum file size (prevent empty/truncated downloads)
    local file_size=$(stat -f%z "$pkg_path" 2>/dev/null || echo "0")
    if [[ $file_size -lt 1000000 ]]; then
        log_error "${pkg_name}: File too small (${file_size} bytes) - likely corrupted"
        return 1
    fi
    log_info "${pkg_name}: Size check passed (${file_size} bytes)"

    # 2. Verify package signature (Apple code signing)
    log_info "${pkg_name}: Verifying package signature..."
    if ! pkgutil --check-signature "$pkg_path" >/dev/null 2>&1; then
        log_warn "${pkg_name}: Package signature verification failed or not signed"
        log_warn "${pkg_name}: This may be expected for some packages, continuing with caution"
        # Don't fail - some legitimate packages may not be signed
        # But log it for security audit trail
        logger -t "erase-install-wrapper" -p user.warning "Unsigned package detected: $pkg_path"
    else
        log_info "${pkg_name}: Package signature verified successfully"
        # Log signature details for audit
        local sig_info=$(pkgutil --check-signature "$pkg_path" 2>&1 | head -5)
        log_debug "${pkg_name}: Signature info: $sig_info"
    fi

    # 3. Verify file type (should be package or disk image)
    local file_type=$(file -b "$pkg_path")
    if [[ ! "$file_type" =~ (xar archive|disk image|Zip archive) ]]; then
        log_error "${pkg_name}: Invalid file type: $file_type"
        return 1
    fi
    log_info "${pkg_name}: File type verified: $file_type"

    # 4. For .pkg files, verify basic plist structure
    if [[ "$pkg_path" == *.pkg ]]; then
        if ! pkgutil --payload-files "$pkg_path" >/dev/null 2>&1; then
            log_error "${pkg_name}: Package structure validation failed"
            return 1
        fi
        log_info "${pkg_name}: Package structure validated"
    fi

    # All checks passed
    log_info "${pkg_name}: All integrity checks passed"
    return 0
}

#######################################
# SECURITY: Atomically install LaunchDaemon with correct permissions
# Arguments:
#   $1 - Source daemon plist path
#   $2 - Destination path in /Library/LaunchDaemons
# Returns:
#   0 if successful, 1 if failed
#######################################
install_daemon_secure() {
    local source_path="$1"
    local dest_path="$2"

    if [[ ! -f "$source_path" ]]; then
        log_error "Source daemon file not found: $source_path"
        return 1
    fi

    # SECURITY FIX (Issue #26): Validate plist before installation
    if ! plutil -lint "$source_path" >/dev/null 2>&1; then
        log_error "Daemon plist validation failed: $source_path"
        return 1
    fi
    log_debug "Daemon plist validated: $source_path"

    # SECURITY FIX (Issue #26): Use install command for atomic operation
    # This sets ownership and permissions in a single atomic operation
    # eliminating the race condition window
    if ! sudo install -m 644 -o root -g wheel "$source_path" "$dest_path" 2>/dev/null; then
        log_error "Failed to install daemon atomically to: $dest_path"
        return 1
    fi

    # Verify the installation was successful
    if [[ ! -f "$dest_path" ]]; then
        log_error "Daemon file not found after installation: $dest_path"
        return 1
    fi

    # Verify permissions are correct (644)
    local perms=$(stat -f %Lp "$dest_path" 2>/dev/null)
    if [[ "$perms" != "644" ]]; then
        log_error "Daemon permissions incorrect: $perms (expected 644)"
        return 1
    fi

    # Verify ownership is correct (root:wheel)
    local owner=$(stat -f %Su:%Sg "$dest_path" 2>/dev/null)
    if [[ "$owner" != "root:wheel" ]]; then
        log_error "Daemon ownership incorrect: $owner (expected root:wheel)"
        return 1
    fi

    log_info "Daemon installed securely: $dest_path"
    return 0
}

#######################################
# SECURITY: Safely terminate processes with graceful shutdown
# Arguments:
#   $1 - Process pattern to match (for pgrep)
#   $2 - Timeout in seconds (optional, default 5)
# Returns:
#   0 if processes terminated, 1 if error
#######################################
kill_process_safely() {
    local process_pattern="$1"
    local timeout="${2:-5}"

    # SECURITY FIX (Issue #29): Use pgrep instead of ps|grep|awk
    local pids
    pids=$(pgrep -f "$process_pattern" 2>/dev/null) || return 0

    if [[ -z "$pids" ]]; then
        return 0
    fi

    log_info "Found processes matching '$process_pattern': $pids"

    # Send SIGTERM for graceful shutdown
    for pid in $pids; do
        if kill -0 "$pid" 2>/dev/null; then
            log_info "Sending SIGTERM to PID $pid for graceful shutdown"
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done

    # Wait for graceful termination
    local waited=0
    while [[ $waited -lt $timeout ]]; do
        pids=$(pgrep -f "$process_pattern" 2>/dev/null)
        if [[ -z "$pids" ]]; then
            log_info "Processes terminated gracefully"
            return 0
        fi
        sleep 1
        ((waited++))
    done

    # Force kill if still running after timeout
    pids=$(pgrep -f "$process_pattern" 2>/dev/null)
    if [[ -n "$pids" ]]; then
        log_warn "Processes did not terminate gracefully, sending SIGKILL to: $pids"
        for pid in $pids; do
            if kill -0 "$pid" 2>/dev/null; then
                kill -KILL "$pid" 2>/dev/null || true
            fi
        done

        # Final verification
        sleep 1
        pids=$(pgrep -f "$process_pattern" 2>/dev/null)
        if [[ -n "$pids" ]]; then
            log_error "Failed to terminate processes: $pids"
            return 1
        fi
    fi

    log_info "All matching processes terminated"
    return 0
}

#######################################
# Apply branding to dialog parameters
# Arguments:
#   $1 - Dialog title
#   $2 - Dialog message
#   $3 - Dialog icon
# Returns:
#   Prints three lines: branded_title, branded_message, branded_icon
#######################################
apply_branding() {
    local title="$1"
    local message="$2"
    local icon="$3"
    local branded_title="$title"
    local branded_message="$message"
    local branded_icon="$icon"

    # Only apply branding if enabled
    if [[ "$ENABLE_BRANDING" == "true" ]]; then
        # Add company name to title if enabled
        if [[ "$SHOW_COMPANY_NAME_IN_TITLE" == "true" ]] && [[ -n "$COMPANY_NAME" ]]; then
            branded_title="${COMPANY_NAME} - ${title}"
        fi

        # Add support contact to message if enabled
        if [[ "$SHOW_SUPPORT_IN_MESSAGE" == "true" ]] && [[ -n "$SUPPORT_CONTACT" ]]; then
            branded_message="${message}\n\n---\n${SUPPORT_CONTACT}"
        fi

        # Use company logo if enabled and file exists
        if [[ "$USE_COMPANY_LOGO" == "true" ]] && [[ -f "$COMPANY_LOGO" ]]; then
            branded_icon="$COMPANY_LOGO"
        fi
    fi

    # Output results (one per line for easy parsing)
    echo "$branded_title"
    echo "$branded_message"
    echo "$branded_icon"
}

# This function loads configuration from JSON files with fallback to script defaults
# Priority: Managed JSON (Jamf) > Local JSON > Script defaults
#
# JSON file locations:
#   - /Library/Managed Preferences/com.macjediwizard.eraseinstall.config.json (Jamf deployed)
#   - /Library/Preferences/com.macjediwizard.eraseinstall.config.json (local)
#

#######################################
# Load configuration from JSON file with fallback to defaults
# Globals:
#   All configuration variables from User Configuration Section
# Arguments:
#   None
# Returns:
#   0 if JSON loaded successfully, 1 if using script defaults
#######################################
load_json_config() {
    local managed_json="/Library/Managed Preferences/com.macjediwizard.eraseinstall.config.json"
    local local_json="/Library/Preferences/com.macjediwizard.eraseinstall.config.json"
    local config_file=""
    local config_source="script defaults"
    local json_loaded=false

    # Check for custom config path (command-line override) - highest priority
    if [[ -n "$CUSTOM_CONFIG_PATH" ]]; then
        if [ -f "$CUSTOM_CONFIG_PATH" ]; then
            config_file="$CUSTOM_CONFIG_PATH"
            config_source="custom configuration (--config parameter)"
            json_loaded=true
            echo "[CONFIG] Using custom JSON configuration: $CUSTOM_CONFIG_PATH" >&2
        else
            echo "[CONFIG] ERROR: Custom config file not found: $CUSTOM_CONFIG_PATH" >&2
            echo "[CONFIG] Falling back to standard configuration search" >&2
        fi
    fi

    # Check for managed configuration (Jamf deployed) - second priority
    if [[ -z "$config_file" ]] && [ -f "$managed_json" ]; then
        config_file="$managed_json"
        config_source="managed configuration (Jamf)"
        json_loaded=true
        echo "[CONFIG] Found managed JSON configuration: $managed_json" >&2
    # Check for local configuration - third priority
    elif [[ -z "$config_file" ]] && [ -f "$local_json" ]; then
        config_file="$local_json"
        config_source="local configuration"
        json_loaded=true
        echo "[CONFIG] Found local JSON configuration: $local_json" >&2
    elif [[ -z "$config_file" ]]; then
        echo "[CONFIG] No JSON configuration found, using script defaults from User Configuration Section" >&2
        return 1
    fi

    # Validate JSON syntax before attempting to read
    if ! plutil -lint "$config_file" > /dev/null 2>&1; then
        echo "[CONFIG] ERROR: JSON syntax invalid in $config_file - falling back to script defaults" >&2
        return 1
    fi

    echo "[CONFIG] JSON syntax validated successfully" >&2

    # Helper function to read JSON value with plutil
    read_json() {
        local json_path="$1"
        local default_value="$2"
        local value=""

        # Use plutil to extract value (native macOS tool, no dependencies)
        value=$(plutil -extract "$json_path" raw "$config_file" 2>/dev/null || echo "")

        # If extraction failed or empty, use default
        if [ -z "$value" ]; then
            echo "$default_value"
        else
            echo "$value"
        fi
    }

    # Load Core Settings
    SCRIPT_VERSION=$(read_json "core_settings.SCRIPT_VERSION" "2.0.0")
    INSTALLER_OS=$(read_json "core_settings.INSTALLER_OS" "15")
    MAX_DEFERS=$(read_json "core_settings.MAX_DEFERS" "3")
    FORCE_TIMEOUT_SECONDS=$(read_json "core_settings.FORCE_TIMEOUT_SECONDS" "259200")

    # Load File Paths
    PLIST=$(read_json "file_paths.PLIST" "/Library/Preferences/com.macjediwizard.eraseinstall.plist")
    SCRIPT_PATH=$(read_json "file_paths.SCRIPT_PATH" "/Library/Management/erase-install/erase-install.sh")
    DIALOG_BIN=$(read_json "file_paths.DIALOG_BIN" "/Library/Management/erase-install/Dialog.app/Contents/MacOS/Dialog")
    LAUNCHDAEMON_LABEL=$(read_json "file_paths.LAUNCHDAEMON_LABEL" "com.macjediwizard.eraseinstall.schedule")
    LAUNCHDAEMON_PATH=$(read_json "file_paths.LAUNCHDAEMON_PATH" "/Library/LaunchDaemons/${LAUNCHDAEMON_LABEL}.plist")

    # SECURITY: Validate file paths to prevent path traversal
    if ! validate_path "$PLIST" "/Library/Preferences"; then
        echo "[CONFIG] WARNING: Invalid PLIST path, using default" >&2
        PLIST="/Library/Preferences/com.macjediwizard.eraseinstall.plist"
    fi

    if ! validate_path "$SCRIPT_PATH" "/Library/Management"; then
        echo "[CONFIG] WARNING: Invalid SCRIPT_PATH, using default" >&2
        SCRIPT_PATH="/Library/Management/erase-install/erase-install.sh"
    fi

    if ! validate_path "$DIALOG_BIN"; then
        echo "[CONFIG] WARNING: Invalid DIALOG_BIN path, using default" >&2
        DIALOG_BIN="/Library/Management/erase-install/Dialog.app/Contents/MacOS/Dialog"
    fi

    # Validate LaunchDaemon label (should be reverse domain notation)
    if [[ ! "$LAUNCHDAEMON_LABEL" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        echo "[CONFIG] WARNING: Invalid LAUNCHDAEMON_LABEL format, using default" >&2
        LAUNCHDAEMON_LABEL="com.macjediwizard.eraseinstall.schedule"
    fi

    if ! validate_path "$LAUNCHDAEMON_PATH" "/Library/LaunchDaemons"; then
        echo "[CONFIG] WARNING: Invalid LAUNCHDAEMON_PATH, using default" >&2
        LAUNCHDAEMON_PATH="/Library/LaunchDaemons/${LAUNCHDAEMON_LABEL}.plist"
    fi

    # Fallback for DIALOG_BIN if primary doesn't exist
    [ ! -x "$DIALOG_BIN" ] && DIALOG_BIN=$(read_json "file_paths.DIALOG_BIN_FALLBACK" "/usr/local/bin/dialog")

    # Load Feature Toggles
    TEST_MODE=$(read_json "feature_toggles.TEST_MODE" "false")
    PREVENT_ALL_REBOOTS=$(read_json "feature_toggles.PREVENT_ALL_REBOOTS" "false")
    SKIP_OS_VERSION_CHECK=$(read_json "feature_toggles.SKIP_OS_VERSION_CHECK" "false")
    AUTO_INSTALL_DEPENDENCIES=$(read_json "feature_toggles.AUTO_INSTALL_DEPENDENCIES" "true")
    DEBUG_MODE=$(read_json "feature_toggles.DEBUG_MODE" "false")

    # Load Logging Configuration
    MAX_LOG_SIZE_MB=$(read_json "logging.MAX_LOG_SIZE_MB" "10")
    MAX_LOG_FILES=$(read_json "logging.MAX_LOG_FILES" "5")

    # Load Branding Configuration
    ENABLE_BRANDING=$(read_json "branding.ENABLE_BRANDING" "false")
    COMPANY_NAME=$(read_json "branding.COMPANY_NAME" "Your Company Name")
    COMPANY_LOGO=$(read_json "branding.COMPANY_LOGO" "/Library/Management/branding/logo.png")
    SUPPORT_CONTACT=$(read_json "branding.SUPPORT_CONTACT" "IT Support: support@company.com or ext. 1234")
    SHOW_COMPANY_NAME_IN_TITLE=$(read_json "branding.SHOW_COMPANY_NAME_IN_TITLE" "true")
    SHOW_SUPPORT_IN_MESSAGE=$(read_json "branding.SHOW_SUPPORT_IN_MESSAGE" "true")
    USE_COMPANY_LOGO=$(read_json "branding.USE_COMPANY_LOGO" "true")
    LOGO_WIDTH=$(read_json "branding.LOGO_WIDTH" "128")
    LOGO_HEIGHT=$(read_json "branding.LOGO_HEIGHT" "128")

    # Load Main Dialog Settings
    DIALOG_TITLE=$(read_json "main_dialog.DIALOG_TITLE" "macOS Upgrade Required")
    DIALOG_TITLE_TEST_MODE=$(read_json "main_dialog.DIALOG_TITLE_TEST_MODE" "$DIALOG_TITLE\n                (TEST MODE)")
    DIALOG_MESSAGE=$(read_json "main_dialog.DIALOG_MESSAGE" "Please install macOS ${INSTALLER_OS}. Select an action:")
    DIALOG_ICON=$(read_json "main_dialog.DIALOG_ICON" "SF=gear,weight=bold,size=128")
    DIALOG_POSITION=$(read_json "main_dialog.DIALOG_POSITION" "topright")
    DIALOG_HEIGHT=$(read_json "main_dialog.DIALOG_HEIGHT" "250")
    DIALOG_WIDTH=$(read_json "main_dialog.DIALOG_WIDTH" "650")
    DIALOG_MESSAGEFONT=$(read_json "main_dialog.DIALOG_MESSAGEFONT" "size=16")
    DIALOG_INSTALL_NOW_TEXT=$(read_json "main_dialog.DIALOG_INSTALL_NOW_TEXT" "Install Now")
    DIALOG_SCHEDULE_TODAY_TEXT=$(read_json "main_dialog.DIALOG_SCHEDULE_TODAY_TEXT" "Schedule Today")
    DIALOG_DEFER_TEXT=$(read_json "main_dialog.DIALOG_DEFER_TEXT" "Defer 24 Hours")
    DIALOG_DEFER_TEXT_TEST_MODE=$(read_json "main_dialog.DIALOG_DEFER_TEXT_TEST_MODE" "Defer 5 Minutes   (TEST MODE)")
    DIALOG_CONFIRM_TEXT=$(read_json "main_dialog.DIALOG_CONFIRM_TEXT" "Confirm")

    # Load Pre-installation Dialog Settings
    PREINSTALL_TITLE=$(read_json "preinstall_dialog.PREINSTALL_TITLE" "macOS Upgrade Starting")
    PREINSTALL_TITLE_TEST_MODE=$(read_json "preinstall_dialog.PREINSTALL_TITLE_TEST_MODE" "$PREINSTALL_TITLE\n                (TEST MODE)")
    PREINSTALL_MESSAGE=$(read_json "preinstall_dialog.PREINSTALL_MESSAGE" "Your scheduled macOS upgrade is ready to begin.\n\nThe upgrade will start automatically in 60 seconds, or click Continue to begin now.")
    PREINSTALL_PROGRESS_TEXT_MESSAGE=$(read_json "preinstall_dialog.PREINSTALL_PROGRESS_TEXT_MESSAGE" "Installation will begin in 60 seconds...")
    PREINSTALL_CONTINUE_TEXT=$(read_json "preinstall_dialog.PREINSTALL_CONTINUE_TEXT" "Continue Now")
    PREINSTALL_COUNTDOWN=$(read_json "preinstall_dialog.PREINSTALL_COUNTDOWN" "60")
    PREINSTALL_HEIGHT=$(read_json "preinstall_dialog.PREINSTALL_HEIGHT" "350")
    PREINSTALL_WIDTH=$(read_json "preinstall_dialog.PREINSTALL_WIDTH" "650")
    PREINSTALL_DIALOG_MESSAGEFONT=$(read_json "preinstall_dialog.PREINSTALL_DIALOG_MESSAGEFONT" "size=16")

    # Load Scheduled Dialog Settings
    SCHEDULED_TITLE=$(read_json "scheduled_dialog.SCHEDULED_TITLE" "macOS Upgrade Scheduled")
    SCHEDULED_TITLE_TEST_MODE=$(read_json "scheduled_dialog.SCHEDULED_TITLE_TEST_MODE" "$SCHEDULED_TITLE\n                (TEST MODE)")
    SCHEDULED_MESSAGE=$(read_json "scheduled_dialog.SCHEDULED_MESSAGE" "Your scheduled macOS upgrade is ready to begin.\n\nThe upgrade will start automatically in 60 seconds,\n\n or click Continue to begin now.")
    SCHEDULED_PROGRESS_TEXT_MESSAGE=$(read_json "scheduled_dialog.SCHEDULED_PROGRESS_TEXT_MESSAGE" "Installation will begin in 60 seconds.....")
    SCHEDULED_CONTINUE_TEXT=$(read_json "scheduled_dialog.SCHEDULED_CONTINUE_TEXT" "Continue Now")
    SCHEDULED_COUNTDOWN=$(read_json "scheduled_dialog.SCHEDULED_COUNTDOWN" "60")
    SCHEDULED_HEIGHT=$(read_json "scheduled_dialog.SCHEDULED_HEIGHT" "250")
    SCHEDULED_WIDTH=$(read_json "scheduled_dialog.SCHEDULED_WIDTH" "650")
    SCHEDULED_CONTINUE_HEIGHT=$(read_json "scheduled_dialog.SCHEDULED_CONTINUE_HEIGHT" "350")
    SCHEDULED_CONTINUE_WIDTH=$(read_json "scheduled_dialog.SCHEDULED_CONTINUE_WIDTH" "750")
    SCHEDULED_DIALOG_MESSAGEFONT=$(read_json "scheduled_dialog.SCHEDULED_DIALOG_MESSAGEFONT" "size=16")

    # Load Error Dialog Settings
    ERROR_DIALOG_TITLE=$(read_json "error_dialog.ERROR_DIALOG_TITLE" "Invalid Time")
    ERROR_DIALOG_MESSAGE=$(read_json "error_dialog.ERROR_DIALOG_MESSAGE" "The selected time is invalid.\nPlease select a valid time (00:00-23:59).")
    ERROR_DIALOG_ICON=$(read_json "error_dialog.ERROR_DIALOG_ICON" "SF=exclamationmark.triangle")
    ERROR_DIALOG_HEIGHT=$(read_json "error_dialog.ERROR_DIALOG_HEIGHT" "350")
    ERROR_DIALOG_WIDTH=$(read_json "error_dialog.ERROR_DIALOG_WIDTH" "650")
    ERROR_CONTINUE_TEXT=$(read_json "error_dialog.ERROR_CONTINUE_TEXT" "OK")

    # Load erase-install Options
    REBOOT_DELAY=$(read_json "erase_install_options.REBOOT_DELAY" "60")
    REINSTALL=$(read_json "erase_install_options.REINSTALL" "true")
    NO_FS=$(read_json "erase_install_options.NO_FS" "true")
    CHECK_POWER=$(read_json "erase_install_options.CHECK_POWER" "true")
    POWER_WAIT_LIMIT=$(read_json "erase_install_options.POWER_WAIT_LIMIT" "300")
    MIN_DRIVE_SPACE=$(read_json "erase_install_options.MIN_DRIVE_SPACE" "50")
    CLEANUP_AFTER_USE=$(read_json "erase_install_options.CLEANUP_AFTER_USE" "true")

    # Load Authentication Notice Settings
    SHOW_AUTH_NOTICE=$(read_json "auth_notice.SHOW_AUTH_NOTICE" "true")
    AUTH_NOTICE_TITLE=$(read_json "auth_notice.AUTH_NOTICE_TITLE" "Admin Access Required")
    AUTH_NOTICE_TITLE_TEST_MODE=$(read_json "auth_notice.AUTH_NOTICE_TITLE_TEST_MODE" "$AUTH_NOTICE_TITLE\n            (TEST MODE)")
    AUTH_NOTICE_MESSAGE=$(read_json "auth_notice.AUTH_NOTICE_MESSAGE" "You will be prompted for admin credentials to complete the macOS upgrade.\n\nIf you do not have admin access, please use Jamf Connect or Self Service to elevate your permissions before continuing.")
    AUTH_NOTICE_BUTTON=$(read_json "auth_notice.AUTH_NOTICE_BUTTON" "I'm Ready to Continue")
    AUTH_NOTICE_TIMEOUT=$(read_json "auth_notice.AUTH_NOTICE_TIMEOUT" "0")
    AUTH_NOTICE_ICON=$(read_json "auth_notice.AUTH_NOTICE_ICON" "SF=lock.shield")
    AUTH_NOTICE_HEIGHT=$(read_json "auth_notice.AUTH_NOTICE_HEIGHT" "300")
    AUTH_NOTICE_WIDTH=$(read_json "auth_notice.AUTH_NOTICE_WIDTH" "750")

    # Load Abort Button Settings
    ENABLE_ABORT_BUTTON=$(read_json "abort_button.ENABLE_ABORT_BUTTON" "true")
    ABORT_BUTTON_TEXT=$(read_json "abort_button.ABORT_BUTTON_TEXT" "Abort (Emergency)")
    ABORT_DEFER_MINUTES=$(read_json "abort_button.ABORT_DEFER_MINUTES" "5")
    MAX_ABORTS=$(read_json "abort_button.MAX_ABORTS" "3")
    ABORT_COUNTDOWN=$(read_json "abort_button.ABORT_COUNTDOWN" "15")
    ABORT_HEIGHT=$(read_json "abort_button.ABORT_HEIGHT" "250")
    ABORT_WIDTH=$(read_json "abort_button.ABORT_WIDTH" "750")
    ABORT_ICON=$(read_json "abort_button.ABORT_ICON" "SF=exclamationmark.triangle")

    # SECURITY: Validate all numeric settings
    local validated_value

    # Core settings
    validated_value=$(validate_positive_integer "$INSTALLER_OS" "15" "99" "false")
    if [[ "$validated_value" != "$INSTALLER_OS" ]]; then
        echo "[CONFIG] WARNING: INSTALLER_OS ($INSTALLER_OS) is invalid, using default: 15" >&2
        INSTALLER_OS="15"
    fi

    validated_value=$(validate_positive_integer "$MAX_DEFERS" "3" "100" "true")
    if [[ "$validated_value" != "$MAX_DEFERS" ]]; then
        echo "[CONFIG] WARNING: MAX_DEFERS ($MAX_DEFERS) is invalid, using default: 3" >&2
        MAX_DEFERS="3"
    fi

    validated_value=$(validate_positive_integer "$MAX_ABORTS" "3" "100" "true")
    if [[ "$validated_value" != "$MAX_ABORTS" ]]; then
        echo "[CONFIG] WARNING: MAX_ABORTS ($MAX_ABORTS) is invalid, using default: 3" >&2
        MAX_ABORTS="3"
    fi

    validated_value=$(validate_positive_integer "$FORCE_TIMEOUT_SECONDS" "259200" "604800" "false")
    if [[ "$validated_value" != "$FORCE_TIMEOUT_SECONDS" ]]; then
        echo "[CONFIG] WARNING: FORCE_TIMEOUT_SECONDS ($FORCE_TIMEOUT_SECONDS) is invalid, using default: 259200" >&2
        FORCE_TIMEOUT_SECONDS="259200"
    fi

    # erase-install options
    validated_value=$(validate_positive_integer "$REBOOT_DELAY" "60" "3600" "true")
    if [[ "$validated_value" != "$REBOOT_DELAY" ]]; then
        echo "[CONFIG] WARNING: REBOOT_DELAY ($REBOOT_DELAY) is invalid, using default: 60" >&2
        REBOOT_DELAY="60"
    fi

    validated_value=$(validate_positive_integer "$POWER_WAIT_LIMIT" "300" "7200" "true")
    if [[ "$validated_value" != "$POWER_WAIT_LIMIT" ]]; then
        echo "[CONFIG] WARNING: POWER_WAIT_LIMIT ($POWER_WAIT_LIMIT) is invalid, using default: 300" >&2
        POWER_WAIT_LIMIT="300"
    fi

    validated_value=$(validate_positive_integer "$MIN_DRIVE_SPACE" "50" "500" "false")
    if [[ "$validated_value" != "$MIN_DRIVE_SPACE" ]]; then
        echo "[CONFIG] WARNING: MIN_DRIVE_SPACE ($MIN_DRIVE_SPACE) is invalid, using default: 50" >&2
        MIN_DRIVE_SPACE="50"
    fi

    # Dialog dimensions and timeouts
    validated_value=$(validate_positive_integer "$DIALOG_HEIGHT" "250" "2000" "false")
    [[ "$validated_value" != "$DIALOG_HEIGHT" ]] && DIALOG_HEIGHT="250"

    validated_value=$(validate_positive_integer "$DIALOG_WIDTH" "650" "3000" "false")
    [[ "$validated_value" != "$DIALOG_WIDTH" ]] && DIALOG_WIDTH="650"

    validated_value=$(validate_positive_integer "$PREINSTALL_COUNTDOWN" "60" "600" "false")
    [[ "$validated_value" != "$PREINSTALL_COUNTDOWN" ]] && PREINSTALL_COUNTDOWN="60"

    validated_value=$(validate_positive_integer "$SCHEDULED_COUNTDOWN" "60" "600" "false")
    [[ "$validated_value" != "$SCHEDULED_COUNTDOWN" ]] && SCHEDULED_COUNTDOWN="60"

    validated_value=$(validate_positive_integer "$AUTH_NOTICE_TIMEOUT" "0" "600" "true")
    [[ "$validated_value" != "$AUTH_NOTICE_TIMEOUT" ]] && AUTH_NOTICE_TIMEOUT="0"

    validated_value=$(validate_positive_integer "$ABORT_COUNTDOWN" "15" "600" "false")
    [[ "$validated_value" != "$ABORT_COUNTDOWN" ]] && ABORT_COUNTDOWN="15"

    validated_value=$(validate_positive_integer "$ABORT_DEFER_MINUTES" "5" "1440" "false")
    [[ "$validated_value" != "$ABORT_DEFER_MINUTES" ]] && ABORT_DEFER_MINUTES="5"

    # Logging settings
    validated_value=$(validate_positive_integer "$MAX_LOG_SIZE_MB" "10" "100" "false")
    [[ "$validated_value" != "$MAX_LOG_SIZE_MB" ]] && MAX_LOG_SIZE_MB="10"

    validated_value=$(validate_positive_integer "$MAX_LOG_FILES" "5" "50" "false")
    [[ "$validated_value" != "$MAX_LOG_FILES" ]] && MAX_LOG_FILES="5"

    # Branding settings validation
    validated_value=$(validate_positive_integer "$LOGO_WIDTH" "128" "512" "false")
    [[ "$validated_value" != "$LOGO_WIDTH" ]] && LOGO_WIDTH="128"

    validated_value=$(validate_positive_integer "$LOGO_HEIGHT" "128" "512" "false")
    [[ "$validated_value" != "$LOGO_HEIGHT" ]] && LOGO_HEIGHT="128"

    # Validate company logo path if branding is enabled
    if [[ "$ENABLE_BRANDING" == "true" ]] && [[ "$USE_COMPANY_LOGO" == "true" ]]; then
        if [[ ! -f "$COMPANY_LOGO" ]]; then
            echo "[CONFIG] WARNING: Company logo not found at $COMPANY_LOGO - will use default icon" >&2
            USE_COMPANY_LOGO="false"
        fi
    fi

    # Log configuration summary
    echo "[CONFIG] ========================================" >&2
    echo "[CONFIG] Configuration loaded from: $config_source" >&2
    echo "[CONFIG] ========================================" >&2
    echo "[CONFIG] Core Settings:" >&2
    echo "[CONFIG]   Target macOS Version: ${INSTALLER_OS}" >&2
    echo "[CONFIG]   Max Deferrals: ${MAX_DEFERS}" >&2
    echo "[CONFIG]   Max Aborts: ${MAX_ABORTS}" >&2
    echo "[CONFIG]   Force Timeout: ${FORCE_TIMEOUT_SECONDS}s ($(($FORCE_TIMEOUT_SECONDS / 3600))h)" >&2
    echo "[CONFIG] Feature Toggles:" >&2
    echo "[CONFIG]   Test Mode: ${TEST_MODE}" >&2
    echo "[CONFIG]   Debug Mode: ${DEBUG_MODE}" >&2
    echo "[CONFIG]   Skip OS Check: ${SKIP_OS_VERSION_CHECK}" >&2
    echo "[CONFIG]   Prevent Reboots: ${PREVENT_ALL_REBOOTS}" >&2
    echo "[CONFIG] Branding:" >&2
    echo "[CONFIG]   Enabled: ${ENABLE_BRANDING}" >&2
    if [[ "$ENABLE_BRANDING" == "true" ]]; then
        echo "[CONFIG]   Company Name: ${COMPANY_NAME}" >&2
        echo "[CONFIG]   Use Logo: ${USE_COMPANY_LOGO}" >&2
        [[ "$USE_COMPANY_LOGO" == "true" ]] && echo "[CONFIG]   Logo Path: ${COMPANY_LOGO}" >&2
        echo "[CONFIG]   Show Support Info: ${SHOW_SUPPORT_IN_MESSAGE}" >&2
    fi
    echo "[CONFIG] ========================================" >&2

    return 0
}

########################################################################################################################################################################
#
# ---------- Very Early Abort Detection ----------
#
# Define a very early function to detect abort daemons before any logging starts
detect_abort_daemon_early() {
  # Check environment variable first - most reliable method
  if [[ "${ERASE_INSTALL_ABORT_DAEMON:-}" == "true" ]]; then
    echo "[EARLY DETECTION] Running from abort daemon detected via environment variable"
    return 0
  fi

  # Check command-line arguments
  for arg in "$@"; do
    if [[ "$arg" == "--from-abort-daemon" ]]; then
      echo "[EARLY DETECTION] Running from abort daemon detected via command-line argument"
      return 0
    fi
  done

  # Check parent process - less reliable but useful as backup
  if [ -n "$PPID" ]; then
    # Use ps with simple output and grep to minimize dependencies
    parent_cmd=$(ps -p "$PPID" -o command= 2>/dev/null || echo "")
    if [[ "$parent_cmd" == *"com.macjediwizard.eraseinstall.abort"* ]]; then
      echo "[EARLY DETECTION] Running from abort daemon detected via parent process"
      return 0
    fi
  fi

  # Not from abort daemon
  return 1
}

# Set VERY early flag for abort daemon detection before ANY initialization
# Keep this global variable at the script level for backward compatibility
RUNNING_FROM_ABORT_DAEMON=false

# Perform early detection and set global flag
if detect_abort_daemon_early "$@"; then
  RUNNING_FROM_ABORT_DAEMON=true
  echo "[EARLY] Script running from abort daemon - will preserve abort daemon during cleanup"
  # Export the variable so child processes know we're from abort daemon
  export ERASE_INSTALL_ABORT_DAEMON=true
else
  echo "[EARLY] Script running in normal mode (not from abort daemon)"
fi

# ---------- Immediate Boot Cleanup ----------
# Clean up any lingering locks from a prior execution
if [ -f "/tmp/erase-install-wrapper-main.lock" ]; then
  rm -f "/tmp/erase-install-wrapper-main.lock" 2>/dev/null
fi
if [ -f "/var/run/erase-install-wrapper.lock" ]; then
  rm -f "/var/run/erase-install-wrapper.lock" 2>/dev/null
fi
# Close any potentially open file descriptors
for fd in {200..210}; do
  eval "exec $fd>&-" 2>/dev/null
done

# ---------------- Configuration ----------------
CURRENT_RUN_ID=""

# ---------------- Centralized Log Path Setup ----------------
setup_log_path() {
  if [[ $EUID -eq 0 ]]; then
    # Running as root - use system log location
    WRAPPER_LOG="/var/log/erase-install-wrapper.log"
    LOG_DIR="/var/log"
  else
    # Running as regular user - use user-accessible location
    WRAPPER_LOG="$HOME/Library/Logs/erase-install-wrapper.log"
    LOG_DIR="$HOME/Library/Logs"
  fi
  # Export these variables to ensure all functions use the same paths
  export WRAPPER_LOG LOG_DIR
}

# Call this function immediately
setup_log_path

# Determine absolute path for script regardless of how it was called
# This ensures compatibility with Jamf and other deployment methods
if [[ -L "${0}" ]]; then
  # Handle symlinks
  WRAPPER_PATH="$(readlink -f "${0}" 2>/dev/null || readlink "${0}")"
else
  WRAPPER_PATH="${0}"
fi

# Convert to absolute path if not already
if [[ ! "${WRAPPER_PATH}" = /* ]]; then
  # Get the directory of the script and combine with basename
  WRAPPER_PATH="$(cd "$(dirname "${0}")" 2>/dev/null && pwd)/$(basename "${0}")"
fi

# ---------------- Logging Configuration ----------------
# Log paths are now set by setup_log_path() function

# ---------------- Logging Functions ----------------

init_logging() {
  # Create log directory if it doesn't exist
  [[ -d "${LOG_DIR}" ]] || mkdir -p "${LOG_DIR}"
  
  # Log rotation logic
  if [[ -f "${WRAPPER_LOG}" ]]; then
    local current_size; current_size=$(du -m "${WRAPPER_LOG}" 2>/dev/null | cut -f1)
    if [[ ${current_size} -gt ${MAX_LOG_SIZE_MB} ]]; then
      for i in $(seq $((MAX_LOG_FILES-1)) -1 1); do
        [[ -f "${WRAPPER_LOG}.${i}" ]] && mv "${WRAPPER_LOG}.${i}" "${WRAPPER_LOG}.$((i+1))"
      done
      mv "${WRAPPER_LOG}" "${WRAPPER_LOG}.1"
    fi
  fi
  
  # Create log file with proper permissions
  touch "${WRAPPER_LOG}" 2>/dev/null || {
    # If touch fails, use a fallback location but don't change WRAPPER_LOG
    local fallback_log="/Users/Shared/erase-install-wrapper.log"
    log_warn "Unable to write to $WRAPPER_LOG, trying fallback: $fallback_log"
    touch "$fallback_log" 2>/dev/null
    
    # Only if fallback succeeds, update the path
    if [[ -f "$fallback_log" ]]; then
      WRAPPER_LOG="$fallback_log"
      LOG_DIR="/Users/Shared"
      export WRAPPER_LOG LOG_DIR
    fi
  }
  
  # SECURITY FIX (Issue #30): Set restrictive permissions to prevent information disclosure
  # Log files contain sensitive configuration and timing information
  if [[ -f "${WRAPPER_LOG}" ]]; then
    chmod 600 "${WRAPPER_LOG}" 2>/dev/null
    chown root:wheel "${WRAPPER_LOG}" 2>/dev/null
    # Make parent directory writable by all users if needed
    if [[ "${LOG_DIR}" == "/Users/Shared" ]]; then
      chmod 777 "${LOG_DIR}" 2>/dev/null
    fi
  fi
  
  # Log initialization message
  printf "[INFO]    [%s] Log initialized at: %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "${WRAPPER_LOG}" | tee -a "${WRAPPER_LOG}" 2>/dev/null
}

# Safe logging functions that won't fail if log file isn't writable
log_info()   { printf "[INFO]    [%s] %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1" | tee -a "${WRAPPER_LOG}" 2>/dev/null; }
log_warn()   { printf "[WARN]    [%s] %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1" | tee -a "${WRAPPER_LOG}" 2>/dev/null; }
log_error()  { printf "[ERROR]   [%s] %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1" | tee -a "${WRAPPER_LOG}" 2>/dev/null >&2; }
log_debug()  { [[ "${DEBUG_MODE}" = true ]] && printf "[DEBUG]   [%s] %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1" | tee -a "${WRAPPER_LOG}" 2>/dev/null; }
log_system() { printf "[SYSTEM]  [%s] %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1" | tee -a "${WRAPPER_LOG}" 2>/dev/null; }

# Now that logging functions are defined, log the wrapper path
log_info "WRAPPER_PATH resolved to: ${WRAPPER_PATH}"

log_system_info() {
  log_system "Script Version: ${SCRIPT_VERSION}"
  log_system "macOS Version: $(sw_vers -productVersion)"
  log_system "Hardware Model: $(sysctl -n hw.model)"
  log_system "Available Disk Space: $(df -h / | awk 'NR==2 {print $4}')"
  log_system "Current User: $(whoami)"
  log_system "Effective User ID: ${EUID}"
  log_system "Dialog Version: $("${DIALOG_BIN}" --version 2>/dev/null || echo 'Not installed')"
  # Log power-related settings
  log_system "Power Check Setting: ${CHECK_POWER}"
  log_system "Power Wait Limit: ${POWER_WAIT_LIMIT} seconds"
  
  if [ -f "${SCRIPT_PATH}" ]; then
    local erase_install_ver; erase_install_ver=$(grep -m1 -A1 '^# Version of this script' "${SCRIPT_PATH}" | grep -m1 -oE 'version="[^"]+"' | cut -d'"' -f2)
    [[ -z "${erase_install_ver}" ]] && erase_install_ver="Unknown"
    log_system "Erase-Install Version: ${erase_install_ver}"
  else
    log_system "Erase-Install Version: Not installed"
  fi
  
  # Log where we're writing logs to help with debugging
  log_system "Log File Location: ${WRAPPER_LOG}"
}

# Add this function to debug scheduled items - place it after the logging functions
debug_scheduled_item() {
  local item_type="$1"
  local item_path="$2"
  
  log_info "Debugging $item_type: $item_path"
  
  if [ -f "$item_path" ]; then
    log_info "$item_type exists at expected path"
    
    # Check permissions
    local perms=$(ls -la "$item_path" | awk '{print $1}')
    log_info "$item_type permissions: $perms"
    
    # Check ownership
    local owner=$(ls -la "$item_path" | awk '{print $3":"$4}')
    log_info "$item_type ownership: $owner"
    
    # Check calendar interval
    local interval=""
    if plutil -p "$item_path" &>/dev/null; then
      interval=$(plutil -p "$item_path" | grep -A5 "StartCalendarInterval" || echo "No calendar interval found")
      log_info "Calendar interval in $item_type: $interval"
    else
      log_warn "Could not parse $item_type with plutil"
    fi
  else
    log_error "$item_type does not exist at expected path: $item_path"
  fi
}

# Function to show pre-authentication notice
show_auth_notice() {
  # Skip if disabled
  if [[ "${SHOW_AUTH_NOTICE}" != "true" ]]; then
    log_debug "Pre-authentication notice is disabled, skipping"
    return 0
  fi
  
  log_info "Displaying pre-authentication notice"
  
  # Enhanced console user detection for LaunchDaemon context
  local console_user=""
  local console_uid=""

  # Use centralized console user detection function
  console_user=$(get_console_user)
  
  # Get UID with validation
  if [ -n "$console_user" ] && [ "$console_user" != "root" ]; then
    console_uid=$(id -u "$console_user" 2>/dev/null || echo "")
    if [ -z "$console_uid" ] || [ "$console_uid" = "0" ]; then
      log_warn "Failed to get valid UID for user $console_user"
      console_user=""
      console_uid=""
    fi
  fi
  
  log_info "Pre-auth notice: console_user='$console_user', console_uid='$console_uid'"
  
  # For test mode, use a modified title
  local display_title="$AUTH_NOTICE_TITLE"
  [[ "$TEST_MODE" = true ]] && display_title="${AUTH_NOTICE_TITLE_TEST_MODE}"
  
  # Prepare timeout parameters
  local timeout_args=""
  if [[ $AUTH_NOTICE_TIMEOUT -gt 0 ]]; then
    timeout_args="--timer $AUTH_NOTICE_TIMEOUT"
  fi
  
  # Run dialog as user to avoid TCC issues
  local result=1

  if [ -n "$console_uid" ] && [ "$console_uid" != "0" ]; then
    log_info "Running pre-auth dialog as user $console_user to avoid TCC permissions issues"

    # SECURITY FIX: Use mktemp for secure temporary files
    local temp_script
    local result_file
    local exec_log
    temp_script=$(create_secure_temp "preauth-dialog" ".sh") || {
        log_error "Failed to create secure temporary script file"
        return 1
    }
    result_file=$(create_secure_temp "dialog-result" ".txt") || {
        rm -f "$temp_script"
        log_error "Failed to create secure result file"
        return 1
    }
    exec_log=$(create_secure_temp "dialog-exec" ".log") || {
        rm -f "$temp_script" "$result_file"
        log_error "Failed to create secure exec log file"
        return 1
    }

    # Setup cleanup trap for these temp files
    trap 'rm -f "$temp_script" "$result_file" "$exec_log"' RETURN

    cat > "$temp_script" << 'EOFSCRIPT'
#!/bin/bash
export DISPLAY=:0
export HOME="/Users/CONSOLE_USER_PLACEHOLDER"
cd "/Users/CONSOLE_USER_PLACEHOLDER"

# Set up proper environment for SwiftDialog
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Verify SwiftDialog exists
if [ ! -x "DIALOG_BIN_PLACEHOLDER" ]; then
  echo "DIALOG_EXIT_CODE:1" > "RESULT_FILE_PLACEHOLDER"
  exit 1
fi

# Run SwiftDialog
"DIALOG_BIN_PLACEHOLDER" \
  --title "DISPLAY_TITLE_PLACEHOLDER" \
  --message "AUTH_NOTICE_MESSAGE_PLACEHOLDER" \
  --button1text "AUTH_NOTICE_BUTTON_PLACEHOLDER" \
  --icon "AUTH_NOTICE_ICON_PLACEHOLDER" \
  --height AUTH_NOTICE_HEIGHT_PLACEHOLDER \
  --width AUTH_NOTICE_WIDTH_PLACEHOLDER \
  --moveable \
  --position "DIALOG_POSITION_PLACEHOLDER" \
  TIMEOUT_ARGS_PLACEHOLDER

DIALOG_RESULT=$?
echo "DIALOG_EXIT_CODE:$DIALOG_RESULT" > "RESULT_FILE_PLACEHOLDER"
exit 0
EOFSCRIPT
    
    # SECURITY FIX: Replace placeholders with escaped values to prevent sed injection
    local console_user_escaped=$(escape_sed "$console_user")
    local dialog_bin_escaped=$(escape_sed "$DIALOG_BIN")
    local display_title_escaped=$(escape_sed "$display_title")
    local auth_notice_message_escaped=$(escape_sed "$AUTH_NOTICE_MESSAGE")
    local auth_notice_button_escaped=$(escape_sed "$AUTH_NOTICE_BUTTON")
    local auth_notice_icon_escaped=$(escape_sed "$AUTH_NOTICE_ICON")
    local dialog_position_escaped=$(escape_sed "$DIALOG_POSITION")
    local timeout_args_escaped=$(escape_sed "$timeout_args")
    local result_file_escaped=$(escape_sed "$result_file")

    sed -i '' "s|CONSOLE_USER_PLACEHOLDER|$console_user_escaped|g" "$temp_script"
    sed -i '' "s|DIALOG_BIN_PLACEHOLDER|$dialog_bin_escaped|g" "$temp_script"
    sed -i '' "s|DISPLAY_TITLE_PLACEHOLDER|$display_title_escaped|g" "$temp_script"
    sed -i '' "s|AUTH_NOTICE_MESSAGE_PLACEHOLDER|$auth_notice_message_escaped|g" "$temp_script"
    sed -i '' "s|AUTH_NOTICE_BUTTON_PLACEHOLDER|$auth_notice_button_escaped|g" "$temp_script"
    sed -i '' "s|AUTH_NOTICE_ICON_PLACEHOLDER|$auth_notice_icon_escaped|g" "$temp_script"
    sed -i '' "s|AUTH_NOTICE_HEIGHT_PLACEHOLDER|$AUTH_NOTICE_HEIGHT|g" "$temp_script"
    sed -i '' "s|AUTH_NOTICE_WIDTH_PLACEHOLDER|$AUTH_NOTICE_WIDTH|g" "$temp_script"
    sed -i '' "s|DIALOG_POSITION_PLACEHOLDER|$dialog_position_escaped|g" "$temp_script"
    sed -i '' "s|TIMEOUT_ARGS_PLACEHOLDER|$timeout_args_escaped|g" "$temp_script"
    sed -i '' "s|RESULT_FILE_PLACEHOLDER|$result_file_escaped|g" "$temp_script"
    
    # After the sed replacements, add:
    log_debug "Generated temp script content:"
    if [[ "${DEBUG_MODE}" == "true" ]]; then
      cat "$temp_script" | while IFS= read -r line; do
        log_debug "  $line"
      done
    fi
    
    chmod +x "$temp_script"
    chown "$console_user" "$temp_script"
    
    # Execute as the user and capture result
    log_debug "Executing temp script: $temp_script"
    log_debug "Expected result file: $result_file"
    
    # Execute the script using a more reliable method
    log_debug "Executing temp script as user $console_user"
    
    # Method 1: Direct sudo execution (most reliable)
    sudo -u "$console_user" bash "$temp_script" > "$exec_log" 2>&1 &
    local script_pid=$!
    
    log_debug "Started script process with PID: $script_pid"
    
    # Wait for the script to complete or timeout
    local timeout=180
    local counter=0
    local script_completed=false
    
    log_debug "Waiting for temp script completion (PID: $script_pid)..."
    
    # Wait for either the result file to appear or the process to complete
    while [ $counter -lt $timeout ]; do
      # Check if result file exists
      if [ -f "$result_file" ]; then
        log_debug "Result file found after ${counter} seconds"
        script_completed=true
        break
      fi
      
      # Check if the process is still running
      if ! kill -0 $script_pid 2>/dev/null; then
        log_debug "Script process completed after ${counter} seconds"
        # Give it a moment for the result file to be written
        sleep 2
        break
      fi
      
      sleep 1
      counter=$((counter + 1))
      
      # Log progress every 10 seconds
      if [ $((counter % 10)) -eq 0 ]; then
        log_debug "Still waiting for script completion... (${counter}/${timeout} seconds)"
      fi
    done
    
    # Read the result
    if [ -f "$result_file" ]; then
      local dialog_exit_code=""
      dialog_exit_code=$(grep "DIALOG_EXIT_CODE:" "$result_file" | cut -d: -f2 | tr -d ' ')
      
      if [ -n "$dialog_exit_code" ]; then
        result="$dialog_exit_code"
        log_info "SwiftDialog completed with exit code: $result"
      else
        log_warn "Result file exists but couldn't parse exit code, assuming success"
        result=0
      fi
      
      # Clean up result file
      rm -f "$result_file"
    else
      log_warn "No result file found after ${counter} seconds, checking script status"
      
      # Check if the script process is still running
      if kill -0 $script_pid 2>/dev/null; then
        log_warn "Script still running after timeout, killing it"
        kill -TERM $script_pid 2>/dev/null
        sleep 2
        kill -KILL $script_pid 2>/dev/null
      fi
      
      log_warn "Assuming dialog completed successfully"
      result=0
    fi
    
    # Cleanup
    rm -f "$temp_script"
  else
    log_error "No valid console user found for pre-auth dialog"
    result=1
  fi
  
  log_debug "Pre-authentication notice dialog completed with status: $result"
  
  # Give user a moment to prepare
  sleep 0.5
  
  return 0
}

# ---------------- Locking Functions ----------------

# Function to acquire a lock with improved atomicity
acquire_lock() {
  local lock_path="$1"
  local lock_timeout="${2:-60}"  # Default timeout of 60 seconds
  local force_break="${3:-false}" # Parameter to force break locks
  
  local start_time=$(date +%s)
  local end_time=$((start_time + lock_timeout))
  local current_time
  
  # Create lock directory if it doesn't exist
  mkdir -p "$(dirname "$lock_path")" 2>/dev/null
  
  log_debug "Attempting to acquire lock: $lock_path (timeout: ${lock_timeout}s, force_break: ${force_break})"
  
  # If force break is enabled, just remove any existing locks
  if [ "$force_break" = "true" ]; then
    log_warn "Force-break enabled. Removing lock file and directory if they exist."
    # Close any open file descriptors first
    for fd in {200..210}; do
      eval "exec $fd>&-" 2>/dev/null
    done
    log_debug "Closed potential file descriptors"
    
    # Remove both lock file and lock directory
    rm -f "$lock_path" 2>/dev/null
    rm -rf "$lock_path.dir" 2>/dev/null
    sleep 1
  fi
  
  # Try to acquire lock using mkdir (more atomic than file creation)
  while true; do
    current_time=$(date +%s)
    
    # Check for timeout
    if [ $current_time -ge $end_time ]; then
      log_error "Failed to acquire lock after ${lock_timeout} seconds: $lock_path"
      return 1
    fi
    
    # Use mkdir for atomic lock acquisition - safer than file creation
    if mkdir "$lock_path.dir" 2>/dev/null; then
      # We got the lock, create a PID file for debugging
      echo "$(date +'%Y-%m-%d %H:%M:%S') $$" > "$lock_path"
      log_debug "Lock acquired using directory method: $lock_path"
      return 0
    else
      # Check if the lock is stale
      if [ -d "$lock_path.dir" ] && [ -f "$lock_path" ]; then
        # Read the PID from the lock file
        local lock_data=$(cat "$lock_path" 2>/dev/null)
        if [ -n "$lock_data" ]; then
          local lock_timestamp=$(echo "$lock_data" | awk '{print $1" "$2}')
          local lock_pid=$(echo "$lock_data" | awk '{print $3}')
          
          # Convert timestamp to seconds since epoch
          local lock_time=$(date -j -f "%Y-%m-%d %H:%M:%S" "$lock_timestamp" "+%s" 2>/dev/null)
          
          # If the PID doesn't exist, or the lock is older than 10 minutes, break it
          if ! kill -0 "$lock_pid" 2>/dev/null || [ $((current_time - lock_time)) -gt 600 ]; then
            log_warn "Found stale lock (PID: $lock_pid not running or lock too old). Breaking."
            rm -f "$lock_path" 2>/dev/null
            rm -rf "$lock_path.dir" 2>/dev/null
          fi
        else
          # Lock file exists but is empty or unreadable - consider it stale
          log_warn "Found potentially corrupt lock file. Breaking."
          rm -f "$lock_path" 2>/dev/null
          rm -rf "$lock_path.dir" 2>/dev/null
        fi
      fi
    fi
    
    # Sleep briefly before trying again
    sleep 1
  done
}

# Function to release a lock
release_lock() {
  local lock_path="${LOCK_FILE}"
  
  log_debug "Releasing lock: $lock_path"
  
  # Clean up both lock file and directory
  rm -f "$lock_path" 2>/dev/null
  rm -rf "$lock_path.dir" 2>/dev/null
  
  # Close any open file descriptors for good measure
  for fd in {200..210}; do
    eval "exec $fd>&-" 2>/dev/null
  done
  
  return 0
}

# Function to clean up any locks at startup
clean_all_locks() {
  log_info "Cleaning up all potential lock files"
  
  # Clean up lock files
  rm -f "/tmp/erase-install-wrapper-main.lock" 2>/dev/null
  rm -rf "/tmp/erase-install-wrapper-main.lock.dir" 2>/dev/null
  rm -f "/var/run/erase-install-wrapper.lock" 2>/dev/null
  rm -rf "/var/run/erase-install-wrapper.lock.dir" 2>/dev/null
  
  # Close any potentially open file descriptors
  for fd in {200..210}; do
    eval "exec $fd>&-" 2>/dev/null
  done
  
  log_debug "Lock cleanup completed"
}

# ---------------- JSON Output Parsing ----------------

parse_dialog_output() {
  local json_output="$1"
  local key="$2"
  local result=""
  
  if command -v jq >/dev/null 2>&1; then
    result=$(echo "$json_output" | jq -r ".$key // empty" 2>/dev/null)
  fi
  
  if [[ -z "$result" || "$result" == "null" ]]; then
    result=$(echo "$json_output" | awk -F' : ' "/\"$key\"/ {gsub(/^[[:space:]]*\"|\"[[:space:]]*$/, \"\", \$2); print \$2}" | head -n1)
  fi
  
  printf "%s" "$result"
}

########################################################################################################################################################################
#
# ---------------- Script Dependency Management ----------------
#
########################################################################################################################################################################
install_erase_install() {
  # Set a trap to help debug premature exits
  trap 'log_info "Exiting install_erase_install function at line $LINENO"' RETURN
  
  log_info "BEGIN install_erase_install function"

  # SECURITY FIX (Issue #23): Use create_secure_temp_dir() instead of raw mktemp
  local tmp
  tmp=$(create_secure_temp_dir "erase-install-download") || {
    log_error "Failed to create secure temporary directory for download."
    return 1
  }
  
  log_info "Created temporary directory: ${tmp}"
  
  # Define the package path
  local pkg_path="${tmp}/erase-install.pkg"
  local download_success=false
  
  # First, try to get the latest version number from GitHub releases page
  log_info "Determining latest version from GitHub releases page..."
  local latest_ver=""
  local releases_html="${tmp}/releases.html"
  
  if /usr/bin/curl -s -L -o "${releases_html}" "https://github.com/grahampugh/erase-install/releases"; then
    # Try to extract the latest version tag
    latest_ver=$(grep -o 'grahampugh/erase-install/releases/tag/v[0-9.]*' "${releases_html}" | head -1 | grep -o '[0-9.]*')
    
    if [[ -n "${latest_ver}" ]]; then
      log_info "Found latest version from releases page: ${latest_ver}"
      
      # Try the URL pattern that worked - with version in both path and filename
      log_info "Downloading package with version ${latest_ver}..."
      local target_url="https://github.com/grahampugh/erase-install/releases/download/v${latest_ver}/erase-install-${latest_ver}.pkg"
      log_info "Target URL: ${target_url}"
      
      if /usr/bin/curl -L --max-redirs 10 --connect-timeout 30 --retry 3 -o "${pkg_path}" "${target_url}"; then
        # SECURITY FIX (Issue #25): Verify package integrity after download
        if verify_package_integrity "${pkg_path}" "erase-install"; then
          log_info "Package download successful and integrity verified."
          download_success=true
        else
          log_error "Package integrity verification failed - removing potentially compromised file"
          rm -f "${pkg_path}"
          download_success=false
        fi
      else
        log_warn "Download failed from ${target_url}."
      fi
    else
      log_warn "Could not determine latest version from releases page."
    fi
  else
    log_warn "Failed to download releases page."
  fi
  
  # If specific version download failed, try alternative URL patterns
  if [[ "${download_success}" != "true" && -n "${latest_ver}" ]]; then
    log_info "Trying alternative URL patterns with version ${latest_ver}..."
    
    # Try alternative URL patterns with the version
    local alt_urls=(
      "https://github.com/grahampugh/erase-install/releases/download/v${latest_ver}/erase-install.pkg"
      "https://github.com/grahampugh/erase-install/releases/download/v${latest_ver}/erase-install.dmg"
    )
    
    for url in "${alt_urls[@]}"; do
      log_info "Trying URL: ${url}"
      if /usr/bin/curl -L --max-redirs 10 --connect-timeout 30 --retry 3 -o "${pkg_path}" "${url}"; then
        local file_size=$(stat -f%z "${pkg_path}" 2>/dev/null || echo "0")
        # SECURITY FIX (Issue #25): Verify package integrity
        if verify_package_integrity "${pkg_path}" "package"; then
          log_info "Package download successful and integrity verified from: ${url}"
          download_success=true
          break
        else
          log_error "Integrity verification failed from ${url} - removing file"
          rm -f "${pkg_path}"
        fi
      else
        log_warn "Download failed from: ${url}"
      fi
    done
  fi
  
  # If versioned download failed, try generic URLs as last resort
  if [[ "${download_success}" != "true" ]]; then
    log_info "Versioned download failed. Trying generic URLs as last resort..."
    
    local generic_urls=(
      "https://github.com/grahampugh/erase-install/releases/latest/download/erase-install.pkg"
      "https://macadmins.software/latest/erase-install.pkg"
    )
    
    for url in "${generic_urls[@]}"; do
      log_info "Trying generic URL: ${url}"
      if /usr/bin/curl -L --max-redirs 10 --connect-timeout 30 --retry 3 -o "${pkg_path}" "${url}"; then
        local file_size=$(stat -f%z "${pkg_path}" 2>/dev/null || echo "0")
        # SECURITY FIX (Issue #25): Verify package integrity
        if verify_package_integrity "${pkg_path}" "package"; then
          log_info "Package download successful and integrity verified from: ${url}"
          download_success=true
          break
        else
          log_error "Integrity verification failed from ${url} - removing file"
          rm -f "${pkg_path}"
        fi
      else
        log_warn "Download failed from: ${url}"
      fi
    done
  fi
  
  # Direct script download if all package downloads fail
  if [[ "${download_success}" != "true" ]]; then
    log_info "All package download attempts failed. Downloading script directly..."
    
    # Create required directories
    mkdir -p "/Library/Management/erase-install"
    
    # Create the script file directly
    local script_path="/Library/Management/erase-install/erase-install.sh"
    
    # Use the determined version for the raw script URL if available
    local script_url="https://raw.githubusercontent.com/grahampugh/erase-install/main/erase-install.sh"
    if [[ -n "${latest_ver}" ]]; then
      script_url="https://raw.githubusercontent.com/grahampugh/erase-install/v${latest_ver}/erase-install.sh"
    fi
    
    log_info "Downloading erase-install script directly to ${script_path}"
    log_info "Script URL: ${script_url}"
    
    if /usr/bin/curl -L --max-redirs 10 --connect-timeout 30 --retry 3 -o "${script_path}" "${script_url}"; then
      local script_size=$(stat -f%z "${script_path}" 2>/dev/null || echo "0")
      log_info "Downloaded script size: ${script_size} bytes"
      
      if [[ ${script_size} -gt 50000 ]]; then
        log_info "Script download successful (${script_size} bytes)"
        chmod +x "${script_path}"
        SCRIPT_PATH="${script_path}"
        log_info "Made script executable at: ${script_path}"
        download_success=true
        # No need to install package since we directly downloaded the script
        rm -rf "${tmp}"
        return 0
      else
        log_warn "Downloaded script is too small (${script_size} bytes) - likely not valid."
      fi
    else
      log_warn "Script download failed."
    fi
  fi
  
  # Install the package if download succeeded
  if [[ "${download_success}" = "true" ]]; then
    log_info "Installing package with command: /usr/sbin/installer -pkg ${pkg_path} -target /"
    if /usr/sbin/installer -pkg "${pkg_path}" -target /; then
      log_info "Package installation succeeded."
    else
      log_error "Package installation failed."
      rm -rf "${tmp}"
      return 1
    fi
  else
    log_error "All download attempts failed."
    rm -rf "${tmp}"
    return 1
  fi
  
  # Clean up temporary files
  rm -rf "${tmp}"
  
  # Verify the installation
  log_info "Verifying erase-install script..."
  if [[ -x "${SCRIPT_PATH}" ]]; then
    log_info "erase-install installation completed successfully."
    return 0
  else
    # Try looking in standard locations
    for path in "/Library/Management/erase-install/erase-install.sh" "/usr/local/bin/erase-install.sh"; do
      if [[ -x "${path}" ]]; then
        log_info "Found erase-install at: ${path}"
        SCRIPT_PATH="${path}"
        log_info "erase-install installation completed successfully."
        return 0
      fi
    done
    
    log_error "erase-install verification failed - script not found after installation."
    return 1
  fi
}

install_swiftDialog() {
  # Set a trap to help debug premature exits
  trap 'log_info "Exiting install_swiftDialog function at line $LINENO"' RETURN
  
  log_info "BEGIN install_swiftDialog function"
  
  # Create a temporary directory
  local tmp; tmp=$(mktemp -d)
  if [[ ! -d "${tmp}" ]]; then
    log_error "Failed to create temporary directory for download."
    return 1
  fi
  
  log_info "Created temporary directory: ${tmp}"
  
  # Define the package path
  local pkg_path="${tmp}/dialog.pkg"
  local download_success=false
  
  # First, try to get the latest version number from GitHub releases page
  log_info "Determining latest version from GitHub releases page..."
  local latest_ver=""
  local releases_html="${tmp}/releases.html"
  
  if /usr/bin/curl -s -L -o "${releases_html}" "https://github.com/swiftDialog/swiftDialog/releases"; then
    # Try to extract the latest version tag
    latest_ver=$(grep -o 'swiftDialog/swiftDialog/releases/tag/v[0-9.]*' "${releases_html}" | head -1 | grep -o '[0-9.]*')
    
    if [[ -n "${latest_ver}" ]]; then
      log_info "Found latest version from releases page: ${latest_ver}"
      
      # Try the URL pattern with version in both path and filename
      log_info "Downloading package with version ${latest_ver}..."
      local target_url="https://github.com/swiftDialog/swiftDialog/releases/download/v${latest_ver}/dialog-${latest_ver}.pkg"
      log_info "Target URL: ${target_url}"
      
      if /usr/bin/curl -L --max-redirs 10 --connect-timeout 30 --retry 3 -o "${pkg_path}" "${target_url}"; then
        # SECURITY FIX (Issue #25): Verify package integrity after download
        if verify_package_integrity "${pkg_path}" "erase-install"; then
          log_info "Package download successful and integrity verified."
          download_success=true
        else
          log_error "Package integrity verification failed - removing potentially compromised file"
          rm -f "${pkg_path}"
          download_success=false
        fi
      else
        log_warn "Download failed from ${target_url}."
      fi
    else
      log_warn "Could not determine latest version from releases page."
    fi
  else
    log_warn "Failed to download releases page."
  fi
  
  # If specific version download failed, try alternative URL patterns
  if [[ "${download_success}" != "true" && -n "${latest_ver}" ]]; then
    log_info "Trying alternative URL patterns with version ${latest_ver}..."
    
    # Try alternative URL patterns with the version
    local alt_urls=(
      "https://github.com/swiftDialog/swiftDialog/releases/download/v${latest_ver}/dialog.pkg"
      "https://github.com/bartreardon/swiftDialog/releases/download/v${latest_ver}/dialog-${latest_ver}.pkg"
      "https://github.com/bartreardon/swiftDialog/releases/download/v${latest_ver}/dialog.pkg"
    )
    
    for url in "${alt_urls[@]}"; do
      log_info "Trying URL: ${url}"
      if /usr/bin/curl -L --max-redirs 10 --connect-timeout 30 --retry 3 -o "${pkg_path}" "${url}"; then
        local file_size=$(stat -f%z "${pkg_path}" 2>/dev/null || echo "0")
        # SECURITY FIX (Issue #25): Verify package integrity
        if verify_package_integrity "${pkg_path}" "package"; then
          log_info "Package download successful and integrity verified from: ${url}"
          download_success=true
          break
        else
          log_error "Integrity verification failed from ${url} - removing file"
          rm -f "${pkg_path}"
        fi
      else
        log_warn "Download failed from: ${url}"
      fi
    done
  fi
  
  # If versioned download failed, try generic URLs as last resort
  if [[ "${download_success}" != "true" ]]; then
    log_info "Versioned download failed. Trying generic URLs as last resort..."
    
    local generic_urls=(
      "https://github.com/swiftDialog/swiftDialog/releases/latest/download/dialog.pkg"
      "https://github.com/bartreardon/swiftDialog/releases/latest/download/dialog.pkg"
      "https://macadmins.software/latest/dialog.pkg"
    )
    
    for url in "${generic_urls[@]}"; do
      log_info "Trying generic URL: ${url}"
      if /usr/bin/curl -L --max-redirs 10 --connect-timeout 30 --retry 3 -o "${pkg_path}" "${url}"; then
        local file_size=$(stat -f%z "${pkg_path}" 2>/dev/null || echo "0")
        # SECURITY FIX (Issue #25): Verify package integrity
        if verify_package_integrity "${pkg_path}" "package"; then
          log_info "Package download successful and integrity verified from: ${url}"
          download_success=true
          break
        else
          log_error "Integrity verification failed from ${url} - removing file"
          rm -f "${pkg_path}"
        fi
      else
        log_warn "Download failed from: ${url}"
      fi
    done
  fi
  
  # Try to download the app bundle as a ZIP if package download fails
  if [[ "${download_success}" != "true" && -n "${latest_ver}" ]]; then
    log_info "Package download failed. Attempting to download app bundle directly..."
    
    local zip_path="${tmp}/dialog.zip"
    local zip_url="https://github.com/swiftDialog/swiftDialog/releases/download/v${latest_ver}/Dialog-${latest_ver}.app.zip"
    
    log_info "Downloading app zip from: ${zip_url}"
    if /usr/bin/curl -L --max-redirs 10 --connect-timeout 30 --retry 3 -o "${zip_path}" "${zip_url}"; then
      local zip_size=$(stat -f%z "${zip_path}" 2>/dev/null || echo "0")
      log_info "Downloaded zip file size: ${zip_size} bytes"
      
      if [[ ${zip_size} -gt 1000000 ]]; then
        log_info "App bundle download successful. Extracting..."
        
        # Create the application directory
        mkdir -p "/Library/Application Support/Dialog"
        
        # Extract the ZIP file
        if /usr/bin/unzip -o "${zip_path}" -d "/Library/Application Support/Dialog/"; then
          log_info "App bundle extracted successfully."
          
          # Create a symlink
          local app_path="/Library/Application Support/Dialog/Dialog.app/Contents/MacOS/Dialog"
          if [[ -f "${app_path}" ]]; then
            log_info "Found Dialog binary at: ${app_path}"
            chmod +x "${app_path}"
            
            mkdir -p /usr/local/bin
            ln -sf "${app_path}" "/usr/local/bin/dialog"
            DIALOG_BIN="/usr/local/bin/dialog"
            
            log_info "Created symlink to /usr/local/bin/dialog"
            download_success=true
          else
            log_warn "Dialog binary not found in extracted app bundle."
          fi
        else
          log_warn "Failed to extract app bundle."
        fi
      else
        log_warn "Downloaded zip is too small (${zip_size} bytes) - likely not a valid app bundle."
      fi
    else
      log_warn "App bundle download failed."
    fi
  fi
  
  # Install the package if download succeeded
  if [[ "${download_success}" = "true" && -f "${pkg_path}" && "$(stat -f%z "${pkg_path}" 2>/dev/null || echo "0")" -gt 1000000 ]]; then
    log_info "Installing package with command: /usr/sbin/installer -pkg ${pkg_path} -target /"
    if /usr/sbin/installer -pkg "${pkg_path}" -target /; then
      log_info "Package installation succeeded."
    else
      log_error "Package installation failed."
      rm -rf "${tmp}"
      return 1
    fi
  else
    # If we already extracted the app bundle and set up the symlink, we don't need to install the package
    if [[ "${download_success}" != "true" ]]; then
      log_error "All download attempts failed."
      rm -rf "${tmp}"
      return 1
    fi
  fi
  
  # Clean up temporary files
  rm -rf "${tmp}"
  
  # Verify the installation
  log_info "Verifying swiftDialog installation..."
  
  # Known possible locations of Dialog binary
  local possible_paths=(
    "${DIALOG_BIN}"
    "/Library/Application Support/Dialog/Dialog.app/Contents/MacOS/Dialog"
    "/Applications/Dialog.app/Contents/MacOS/Dialog"
    "/usr/local/bin/dialog"
  )
  
  local found=false
  for path in "${possible_paths[@]}"; do
    log_info "Checking for swiftDialog at: ${path}"
    if [[ -f "${path}" ]]; then
      log_info "Found swiftDialog at: ${path}"
      # Make it executable if needed
      if [[ ! -x "${path}" ]]; then
        log_info "Making binary executable"
        chmod +x "${path}"
      fi
      # Update DIALOG_BIN if different from initial value
      if [[ "${DIALOG_BIN}" != "${path}" ]]; then
        log_info "Updating DIALOG_BIN from ${DIALOG_BIN} to ${path}"
        DIALOG_BIN="${path}"
      fi
      found=true
      break
    fi
  done
  
  # Create symlink for convenience if needed
  if [[ "${found}" = "true" && "${DIALOG_BIN}" != "/usr/local/bin/dialog" ]]; then
    log_info "Creating symlink to /usr/local/bin/dialog"
    mkdir -p /usr/local/bin
    ln -sf "${DIALOG_BIN}" "/usr/local/bin/dialog"
  fi
  
  # Final verification with version check
  if [[ "${found}" = "true" ]]; then
    log_info "Testing swiftDialog functionality..."
    if "${DIALOG_BIN}" --version >/dev/null 2>&1; then
      local dialog_version
      dialog_version=$("${DIALOG_BIN}" --version 2>&1 | head -1 || echo "Unknown")
      log_info "swiftDialog installation verified successfully. Version: ${dialog_version}"
      return 0
    else
      log_warn "swiftDialog binary exists but failed version check."
      # Return success anyway since we found the binary
      return 0
    fi
  else
    log_error "swiftDialog installation verification failed - binary not found."
    return 1
  fi
}

dependency_check() {
  local has_error=0
  
  log_info "Starting dependency check..."
  
  # Verify erase-install
  log_info "Checking for erase-install..."
  if [[ ! -x "${SCRIPT_PATH}" ]]; then
    log_info "erase-install not found at ${SCRIPT_PATH}"
    
    if [[ "${AUTO_INSTALL_DEPENDENCIES}" = true ]]; then
      log_info "Auto-install is enabled. Attempting to install erase-install..."
      
      # Explicitly call the function and check its return value
      install_erase_install
      local erase_install_result=$?
      
      log_info "install_erase_install function returned: ${erase_install_result}"
      
      if [[ ${erase_install_result} -ne 0 ]]; then
        log_error "erase-install installation failed with status: ${erase_install_result}"
        log_error "This is a required dependency, cannot continue."
        has_error=1
      else
        log_info "erase-install installation succeeded"
        
        # Verify the installation succeeded
        if [[ ! -x "${SCRIPT_PATH}" ]]; then
          log_error "Post-installation verification failed: erase-install not found at ${SCRIPT_PATH}"
          
          # Check standard locations as fallback
          for path in "/Library/Management/erase-install/erase-install.sh" "/usr/local/bin/erase-install.sh"; do
            if [[ -x "${path}" ]]; then
              log_info "Found erase-install at alternate location: ${path}"
              log_info "Updating SCRIPT_PATH from ${SCRIPT_PATH} to ${path}"
              SCRIPT_PATH="${path}"
              break
            fi
          done
          
          # Final check after searching alternate locations
          if [[ ! -x "${SCRIPT_PATH}" ]]; then
            log_error "Could not find erase-install in any standard location after installation"
            has_error=1
          else
            log_info "Using erase-install at: ${SCRIPT_PATH}"
          fi
        else
          log_info "Verified erase-install exists at: ${SCRIPT_PATH}"
        fi
      fi
    else
      log_error "erase-install missing and auto-install disabled"
      has_error=1
    fi
  else
    log_info "erase-install found at ${SCRIPT_PATH}"
  fi
  
  # Verify swiftDialog
  log_info "Checking for swiftDialog..."
  if [[ ! -x "${DIALOG_BIN}" ]]; then
    log_info "swiftDialog not found at ${DIALOG_BIN}"
    
    if [[ "${AUTO_INSTALL_DEPENDENCIES}" = true ]]; then
      log_info "Auto-install is enabled. Attempting to install swiftDialog..."
      
      # Explicitly call the function and check its return value
      install_swiftDialog
      local dialog_install_result=$?
      
      log_info "install_swiftDialog function returned: ${dialog_install_result}"
      
      if [[ ${dialog_install_result} -ne 0 ]]; then
        log_error "swiftDialog installation failed with status: ${dialog_install_result}"
        log_error "This is a required dependency, cannot continue."
        has_error=1
      else
        log_info "swiftDialog installation succeeded"
        
        # Verify the installation succeeded
        if [[ ! -x "${DIALOG_BIN}" ]]; then
          log_error "Post-installation verification failed: swiftDialog not found at ${DIALOG_BIN}"
          
          # Check standard locations as fallback
          for path in "/usr/local/bin/dialog" "/Library/Application Support/Dialog/Dialog.app/Contents/MacOS/Dialog" "/Applications/Dialog.app/Contents/MacOS/Dialog"; do
            if [[ -x "${path}" ]]; then
              log_info "Found swiftDialog at alternate location: ${path}"
              log_info "Updating DIALOG_BIN from ${DIALOG_BIN} to ${path}"
              DIALOG_BIN="${path}"
              break
            fi
          done
          
          # Final check after searching alternate locations
          if [[ ! -x "${DIALOG_BIN}" ]]; then
            log_error "Could not find swiftDialog in any standard location after installation"
            has_error=1
          else
            log_info "Using swiftDialog at: ${DIALOG_BIN}"
          fi
        else
          log_info "Verified swiftDialog exists at: ${DIALOG_BIN}"
        fi
      fi
    else
      log_error "swiftDialog missing and auto-install disabled"
      has_error=1
    fi
  else
    log_info "swiftDialog found at ${DIALOG_BIN}"
    
    # Verify swiftDialog is functioning correctly
    if ! "${DIALOG_BIN}" --version >/dev/null 2>&1; then
      log_warn "swiftDialog exists but may not be functioning correctly (--version test failed)"
      log_info "Will attempt to reinstall swiftDialog..."
      install_swiftDialog
      local dialog_reinstall_result=$?
      
      if [[ ${dialog_reinstall_result} -ne 0 ]]; then
        log_error "swiftDialog reinstallation failed with status: ${dialog_reinstall_result}"
        has_error=1
      else
        log_info "swiftDialog reinstallation succeeded"
      fi
    else
      log_info "swiftDialog version check successful"
    fi
  fi
  
  if [[ ${has_error} -eq 0 ]]; then
    log_info "All dependencies verified successfully."
  else
    log_error "Some dependencies could not be installed or verified."
  fi
  
  log_info "Dependency check completed with final status: ${has_error}"
  return ${has_error}
}

########################################################################################################################################################################
# ---------------- End Dependency Management ----------------
########################################################################################################################################################################
########################################################################################################################################################################
#
# ---------------- Version Check Functions ----------------
#
########################################################################################################################################################################
get_available_macos_version() {
  # Redirect all log output to stderr instead of stdout
  log_info "Determining latest macOS version..." >&2
  
  # First try erase-install table parsing
  local available_version=""
  local table_success=false
  
  # Create a temporary file for erase-install output
  local tmp_file=$(mktemp)
  
  # Run erase-install with list-only flag, filtered by INSTALLER_OS
  log_info "Running erase-install in list mode for macOS ${INSTALLER_OS}..." >&2
  "${SCRIPT_PATH}" --list --os "${INSTALLER_OS}" > "$tmp_file" 2>&1
  
  # Look for the table header line
  local table_start=$(grep -n "│ IDENTIFIER │" "$tmp_file" | cut -d':' -f1)
  
  if [[ -n "$table_start" ]]; then
    log_info "Found version table at line $table_start" >&2
    
    # Get the first data row (2 lines after the header, which includes the separator line)
    local first_entry_line=$((table_start + 2))
    local first_entry=$(sed -n "${first_entry_line}p" "$tmp_file")
    
    if [[ -n "$first_entry" ]]; then
      # Parse using │ as field separator and extract the version field (field 4)
      available_version=$(echo "$first_entry" | awk -F'│' '{print $4}' | xargs)
      # Strip any ANSI color codes
      available_version=$(echo "$available_version" | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})*)?[m|K]//g")
        
        if [[ -n "$available_version" ]]; then
          log_info "Successfully extracted version from erase-install table: $available_version" >&2
          table_success=true
        fi
    fi
  fi
  
  # If table parsing failed, try SOFA method
  if [[ "$table_success" != "true" ]]; then
    log_info "Table parsing failed, trying SOFA web service fallback..." >&2
    
    # Use the SOFA feed URL
    local feed_url="https://sofafeed.macadmins.io/v1/macos_data_feed.json"
    local json_cache="/tmp/sofa_feed.json"
    
    if curl -s --compressed "$feed_url" -o "$json_cache" 2>/dev/null; then
      log_info "Successfully downloaded SOFA JSON feed" >&2

      # Loop through OSVersions array to find matching major version
      log_info "Searching for macOS ${INSTALLER_OS} in SOFA feed..." >&2
      for i in {0..10}; do
        local os_version=$(/usr/bin/plutil -extract "OSVersions.$i.Latest.ProductVersion" raw "$json_cache" 2>/dev/null | head -n 1)

        if [[ -n "$os_version" ]]; then
          # Extract major version from the found version
          local major_version=$(echo "$os_version" | cut -d. -f1)

          if [[ "$major_version" == "$INSTALLER_OS" ]]; then
            available_version="$os_version"
            log_info "Found matching macOS ${INSTALLER_OS} in SOFA: $available_version" >&2
            break
          fi
        fi
      done

      if [[ -z "$available_version" ]]; then
        log_warn "Could not find macOS ${INSTALLER_OS} in SOFA feed" >&2
      fi
    else
      log_warn "Failed to download SOFA JSON feed" >&2
    fi
  fi
  
  # Clean up
  rm -f "$tmp_file"
  rm -f "/tmp/sofa_feed.json" 2>/dev/null
  
  # If we still don't have a version, use INSTALLER_OS as fallback
  if [[ -z "$available_version" ]]; then
    available_version="$INSTALLER_OS"
    log_info "Using INSTALLER_OS as fallback version: $available_version" >&2
  fi
  
  # Only return the version number, not any logs
  echo "$available_version"
}

test_os_version_check() {
  log_info "===== OS VERSION CHECK TEST MODE ====="
  log_info "Test modes active: TEST_MODE=${TEST_MODE}, SKIP_OS_VERSION_CHECK=${SKIP_OS_VERSION_CHECK}"
  
  # Get current OS version
  local current_os=$(sw_vers -productVersion)
  log_info "Current OS version: $current_os"
  
  # Get target OS version
  local target_os=$(defaults read "${PLIST}" targetOSVersion 2>/dev/null || echo "${INSTALLER_OS}")
  log_info "Target OS version: $target_os"
  
  # Extract major versions for easier comparison logging
  local current_major=$(echo "$current_os" | cut -d. -f1)
  local target_major=$(echo "$target_os" | cut -d. -f1)
  log_info "Current major version: $current_major, Target major version: $target_major"
  
  # Only run the initial OS version check
  log_info "----- INITIAL VERSION CHECK TEST -----"
  if check_os_already_updated; then
    log_info "TEST RESULT: System is already running the target OS version ($current_os >= $target_os)"
    log_info "In normal mode, the script would exit here."
    log_info "Since SKIP_OS_VERSION_CHECK=${SKIP_OS_VERSION_CHECK}, the script will continue anyway."
  else
    log_info "TEST RESULT: System needs to be updated to the target OS version ($current_os < $target_os)"
  fi
  
  # Log detailed version comparison to help with troubleshooting
  log_info "Detailed version comparison:"
  IFS='.' read -ra CURRENT_VER <<< "$current_os"
  IFS='.' read -ra TARGET_VER <<< "$target_os"
  
  log_info "Current version components: ${CURRENT_VER[*]}"
  log_info "Target version components: ${TARGET_VER[*]}"
  
  # Compare each component
  for ((i=0; i<${#CURRENT_VER[@]} && i<${#TARGET_VER[@]}; i++)); do
    if [[ ${CURRENT_VER[i]} -gt ${TARGET_VER[i]} ]]; then
      log_info "Component $i: Current (${CURRENT_VER[i]}) > Target (${TARGET_VER[i]})"
      break
    elif [[ ${CURRENT_VER[i]} -lt ${TARGET_VER[i]} ]]; then
      log_info "Component $i: Current (${CURRENT_VER[i]}) < Target (${TARGET_VER[i]})"
      break
    else
      log_info "Component $i: Current (${CURRENT_VER[i]}) = Target (${TARGET_VER[i]})"
    fi
  done
  
  log_info "===== OS VERSION CHECK TEST COMPLETE ====="
  
  # Return true (0) to allow script to continue regardless of actual OS versions
  return 0
}

test_deferral_os_check() {
  log_info "===== DEFERRAL OS CHECK TEST MODE ====="
  log_info "Test modes active: TEST_MODE=${TEST_MODE}, SKIP_OS_VERSION_CHECK=${SKIP_OS_VERSION_CHECK}"
  
  # Get current OS version
  local current_os=$(sw_vers -productVersion)
  log_info "Current OS version: $current_os"
  
  # Get initial and target OS versions
  local initial_os=$(defaults read "${PLIST}" initialOSVersion 2>/dev/null || echo "$current_os")
  local target_os=$(defaults read "${PLIST}" targetOSVersion 2>/dev/null || echo "${INSTALLER_OS}")
  log_info "Initial OS version (when deferred): $initial_os"
  log_info "Target OS version: $target_os"
  
  # Run the deferral check
  log_info "----- DEFERRAL VERSION CHECK TEST -----"
  if check_if_os_upgraded_during_deferral; then
    log_info "TEST RESULT: OS has been upgraded during deferral period or is already at target."
    log_info "In normal mode, a scheduled installation would exit here."
    log_info "Since SKIP_OS_VERSION_CHECK=${SKIP_OS_VERSION_CHECK}, the script will continue anyway."
  else
    log_info "TEST RESULT: OS has NOT been upgraded during deferral and needs update."
  fi
  
  # Log detailed comparison of current vs initial version
  log_info "Detailed deferral comparison:"
  log_info "Initial version: $initial_os, Current version: $current_os, Target version: $target_os"
  
  # Extract major versions
  local current_major=$(echo "$current_os" | cut -d. -f1)
  local initial_major=$(echo "$initial_os" | cut -d. -f1)
  log_info "Initial major: $initial_major, Current major: $current_major"
  
  # Check if major version changed during deferral
  if [[ $current_major -gt $initial_major ]]; then
    log_info "Major version increased during deferral ($initial_major → $current_major)"
  elif [[ $current_major -eq $initial_major ]]; then
    log_info "Major version unchanged during deferral (still $current_major)"
  else
    log_info "Warning: Current major version ($current_major) is less than initial ($initial_major)"
  fi
  
  log_info "===== DEFERRAL OS CHECK TEST COMPLETE ====="
  
  # Return true (0) to allow script to continue regardless of actual OS versions
  return 0
}

check_os_already_updated() {
  log_info "Checking if OS is already at or above the target version..."
  
  # Get current OS version
  local current_os=$(sw_vers -productVersion)
  log_info "Current OS version: $current_os"
  
  # Get the target OS version from the plist (determined from erase-install)
  local target_os=$(defaults read "${PLIST}" targetOSVersion 2>/dev/null)
  if [[ -z "$target_os" ]]; then
    # If we don't have it stored, get it now
    target_os=$(get_available_macos_version)
    defaults write "${PLIST}" targetOSVersion -string "${target_os}"
  fi
  log_info "Target OS version: $target_os"
  
  # Extract major versions
  local current_major=$(echo "$current_os" | cut -d. -f1)
  local target_major=$(echo "$target_os" | cut -d. -f1)
  
  # Compare major versions
  if [[ $current_major -gt $target_major ]]; then
    log_info "Current OS major version ($current_major) is greater than target major version ($target_major)"
    return 0  # No update needed
  elif [[ $current_major -lt $target_major ]]; then
    log_info "Current OS major version ($current_major) is less than target major version ($target_major)"
    return 1  # Update needed
  else
    # Major versions are equal, compare minor versions
    log_info "Major versions are equal. Checking minor versions..."
    
    # Split versions by dots for comparison
    IFS='.' read -ra CURRENT_VER <<< "$current_os"
    IFS='.' read -ra TARGET_VER <<< "$target_os"
    
    # Compare each component
    for ((i=1; i<${#CURRENT_VER[@]} && i<${#TARGET_VER[@]}; i++)); do
      if [[ ${CURRENT_VER[i]} -gt ${TARGET_VER[i]} ]]; then
        log_info "Current version component ${CURRENT_VER[i]} is greater than target ${TARGET_VER[i]} at position $i"
        return 0  # No update needed
      elif [[ ${CURRENT_VER[i]} -lt ${TARGET_VER[i]} ]]; then
        log_info "Current version component ${CURRENT_VER[i]} is less than target ${TARGET_VER[i]} at position $i"
        return 1  # Update needed
      fi
    done
    
    # If we get here, all compared components are equal
    # If target has more components, check if they're significant
    if [[ ${#TARGET_VER[@]} -gt ${#CURRENT_VER[@]} ]]; then
      for ((i=${#CURRENT_VER[@]}; i<${#TARGET_VER[@]}; i++)); do
        if [[ ${TARGET_VER[i]} -gt 0 ]]; then
          log_info "Target version has additional significant component ${TARGET_VER[i]}"
          return 1  # Update needed
        fi
      done
    fi
    
    # If we get here, versions are compatible
    log_info "Current version $current_os is compatible with target version $target_os"
    return 0  # No update needed
  fi
}

check_if_os_upgraded_during_deferral() {
  log_info "Checking if OS was upgraded during deferral period..."
  
  # Get current OS version
  local current_os=$(sw_vers -productVersion)
  log_info "Current OS version: $current_os"
  
  # Get initial OS version when deferral started
  local initial_os=$(defaults read "${PLIST}" initialOSVersion 2>/dev/null || echo "")
  if [[ -z "$initial_os" ]]; then
    log_info "No initial OS version recorded. Using current OS version."
    defaults write "${PLIST}" initialOSVersion -string "${current_os}"
    initial_os="$current_os"
  fi
  log_info "Initial OS version (when deferred): $initial_os"
  
  # Get target OS version from plist
  local target_os=$(defaults read "${PLIST}" targetOSVersion 2>/dev/null || echo "")
  if [[ -z "$target_os" ]]; then
    log_info "No target OS version recorded. Using value from erase-install."
    target_os=$(get_available_macos_version)
    defaults write "${PLIST}" targetOSVersion -string "${target_os}"
  fi
  log_info "Target OS version: $target_os"
  
  # Extract version components
  local current_major=$(echo "$current_os" | cut -d. -f1)
  local initial_major=$(echo "$initial_os" | cut -d. -f1)
  local target_major=$(echo "$target_os" | cut -d. -f1)
  
  # First, check if OS is already fully up-to-date compared to target
  log_info "Performing exact version comparison..."
  
  # Split versions into components for detailed comparison
  IFS='.' read -ra CURRENT_VER <<< "$current_os"
  IFS='.' read -ra TARGET_VER <<< "$target_os"
  
  # Flag to track if we need to update
  local needs_update=false
  
  # Check if major versions differ
  if [[ ${CURRENT_VER[0]} -lt ${TARGET_VER[0]} ]]; then
    log_info "Current major version (${CURRENT_VER[0]}) is less than target (${TARGET_VER[0]})"
    needs_update=true
  elif [[ ${CURRENT_VER[0]} -eq ${TARGET_VER[0]} ]]; then
    # Major versions match, check minor/patch versions
    log_info "Major versions match, checking minor versions..."
    
    # Compare each component after the major version
    for ((i=1; i<${#CURRENT_VER[@]} && i<${#TARGET_VER[@]}; i++)); do
      if [[ ${CURRENT_VER[i]} -lt ${TARGET_VER[i]} ]]; then
        log_info "Current version component ${CURRENT_VER[i]} is less than target ${TARGET_VER[i]} at position $i"
        needs_update=true
        break
      elif [[ ${CURRENT_VER[i]} -gt ${TARGET_VER[i]} ]]; then
        log_info "Current version component ${CURRENT_VER[i]} is greater than target ${TARGET_VER[i]} at position $i"
        break
      fi
      # If equal, continue to next component
    done
    
    # If target has more components than current, check if they're significant
    if [[ "$needs_update" == "false" && ${#TARGET_VER[@]} -gt ${#CURRENT_VER[@]} ]]; then
      for ((i=${#CURRENT_VER[@]}; i<${#TARGET_VER[@]}; i++)); do
        if [[ ${TARGET_VER[i]} -gt 0 ]]; then
          log_info "Target version has additional significant component ${TARGET_VER[i]}"
          needs_update=true
          break
        fi
      done
    fi
  fi
  
  # If OS is already at or above target version, no update needed
  if [[ "$needs_update" == "false" ]]; then
    log_info "Current OS version ($current_os) is already at or above target version ($target_os)"
    return 0  # No update needed
  fi
  
  # At this point, we know the current version isn't fully up-to-date
  log_info "Current OS version ($current_os) is not fully up-to-date compared to target ($target_os)"
  
  # Now check if a major upgrade occurred during deferral
  if [[ "$current_major" -gt "$initial_major" ]]; then
    log_info "Major OS upgrade detected during deferral (from $initial_os to $current_os)"
    
    # Policy decision: Proceed with update even after major upgrade to ensure full update
    log_info "Although user performed major upgrade, current version isn't at latest minor version"
    log_info "Proceeding with update to ensure system is fully up-to-date"
    return 1  # Proceed with update
  else 
    # No major upgrade detected, update is needed
    log_info "No major OS upgrade detected. Update is needed."
    return 1  # Update needed
  fi
}

########################################################################################################################################################################
# ---------------- End Version Check Functions ----------------
########################################################################################################################################################################
########################################################################################################################################################################
#
# ---------------- Deferral State ----------------
#
########################################################################################################################################################################
# Improved plist management with fallback locations and error handling
init_plist() {
  # Ensure the directory exists with proper error handling
  local plist_dir="$(dirname "${PLIST}")"
  
  # Try to create directory with sudo if needed
  if ! mkdir -p "$plist_dir" 2>/dev/null; then
    if [[ $EUID -ne 0 ]]; then
      log_warn "Cannot create plist directory as user, trying with sudo"
      sudo mkdir -p "$plist_dir" 2>/dev/null || {
        log_error "Failed to create plist directory even with sudo"
        # Fallback to user-accessible location
        PLIST="$HOME/Library/Preferences/com.macjediwizard.eraseinstall.plist"
        export PLIST
        log_info "Using fallback plist location: $PLIST"
        mkdir -p "$(dirname "${PLIST}")" 2>/dev/null
      }
    fi
  fi
  
  # Test write access to plist location
  if ! touch "${PLIST}" 2>/dev/null; then
    if [[ $EUID -ne 0 ]]; then
      log_warn "Cannot write to plist location, trying with sudo"
      sudo touch "${PLIST}" 2>/dev/null || {
        log_error "Cannot write to plist even with sudo, using fallback"
        PLIST="$HOME/Library/Preferences/com.macjediwizard.eraseinstall.plist"
        export PLIST
        touch "${PLIST}" 2>/dev/null
      }
    fi
  fi
  
  # Initialize plist with atomic operations and verification
  if [[ ! -f "${PLIST}" ]]; then
    log_info "Creating new preferences file at ${PLIST}"
    
    # Create temporary plist content
    local temp_plist="/tmp/eraseinstall_init_$$.plist"
    cat > "$temp_plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>scriptVersion</key>
<string>${SCRIPT_VERSION}</string>
<key>deferCount</key>
<integer>0</integer>
<key>firstPromptDate</key>
<string>$(date -u +%s)</string>
<key>abortCount</key>
<integer>0</integer>
</dict>
</plist>
EOF
    
    # Validate and copy to final location
    if plutil -lint "$temp_plist" >/dev/null 2>&1; then
      # SECURITY FIX (Issue #24): Use restrictive permissions (600) to prevent information disclosure
      # Plist contains sensitive timing and deferral state that should only be readable by root
      cp "$temp_plist" "${PLIST}" && chmod 600 "${PLIST}" && chown root:wheel "${PLIST}"
      rm -f "$temp_plist"
      log_info "Successfully created and validated plist with secure permissions (600)"
    else
      log_error "Generated plist failed validation, using defaults commands"
      rm -f "$temp_plist"
      # Fallback to individual defaults commands
      defaults write "${PLIST}" scriptVersion -string "${SCRIPT_VERSION}"
      defaults write "${PLIST}" deferCount -int 0
      defaults write "${PLIST}" firstPromptDate -string "$(date -u +%s)"
      defaults write "${PLIST}" abortCount -int 0
    fi
    
    # Add OS version tracking
    local current_os=$(sw_vers -productVersion)
    defaults write "${PLIST}" initialOSVersion -string "${current_os}"
    
    local available_version
    available_version=$(get_available_macos_version)
    defaults write "${PLIST}" targetOSVersion -string "${available_version}"
    
    log_info "Stored initial OS: $current_os and target OS: $available_version"
  else
    # Existing plist - check for version updates and missing keys
    local ver; ver=$(defaults read "${PLIST}" scriptVersion 2>/dev/null || echo "")
    if [[ "${ver}" != "${SCRIPT_VERSION}" ]]; then
      log_info "New script version detected (${ver} -> ${SCRIPT_VERSION}); resetting counters"
      defaults write "${PLIST}" scriptVersion -string "${SCRIPT_VERSION}"
      defaults write "${PLIST}" deferCount -int 0
      defaults write "${PLIST}" firstPromptDate -string "$(date -u +%s)"
      defaults write "${PLIST}" abortCount -int 0
      
      # Update OS version info
      local current_os=$(sw_vers -productVersion)
      defaults write "${PLIST}" initialOSVersion -string "${current_os}"
      
      local available_version
      available_version=$(get_available_macos_version)
      defaults write "${PLIST}" targetOSVersion -string "${available_version}"
    fi
  fi
  
  # Verify all required keys exist
  local required_keys=("scriptVersion" "deferCount" "firstPromptDate" "abortCount" "initialOSVersion" "targetOSVersion")
  for key in "${required_keys[@]}"; do
    if ! defaults read "${PLIST}" "$key" &>/dev/null; then
      case "$key" in
        "scriptVersion") defaults write "${PLIST}" "$key" -string "${SCRIPT_VERSION}" ;;
        "deferCount"|"abortCount") defaults write "${PLIST}" "$key" -int 0 ;;
        "firstPromptDate") defaults write "${PLIST}" "$key" -string "$(date -u +%s)" ;;
        "initialOSVersion"|"targetOSVersion") 
          local os_ver=$(sw_vers -productVersion)
          defaults write "${PLIST}" "$key" -string "$os_ver" ;;
      esac
      log_info "Added missing plist key: $key"
    fi
  done
  
  # Final verification
  local final_defer_count
  final_defer_count=$(defaults read "${PLIST}" deferCount 2>/dev/null || echo "ERROR")
  if [[ "$final_defer_count" == "ERROR" ]]; then
    log_error "Plist verification failed - unable to read deferCount"
    return 1
  fi
  
  log_info "Plist initialization complete. Current defer count: $final_defer_count"
  return 0
}

reset_deferrals() {
  log_info "Resetting deferral and abort counts."
  defaults write "${PLIST}" deferCount -int 0
  defaults write "${PLIST}" abortCount -int 0
  defaults write "${PLIST}" firstPromptDate -string "$(date -u +%s)"
  
  # Update exported variables
  export CURRENT_DEFER_COUNT=0
  export CURRENT_ABORT_COUNT=0
  export CURRENT_FIRST_DATE=$(date -u +%s)
  export CURRENT_ELAPSED=0
  export CAN_DEFER=true
  export CAN_ABORT=true
  export FORCE_INSTALL=false
  
  log_info "All counters reset successfully."
}

# Centralized state management for deferrals and aborts
get_installation_state() {
  log_info "Checking current installation state..."
  
  # Read all state values with error handling
  local defer_count=$(defaults read "${PLIST}" deferCount 2>/dev/null || echo 0)
  local abort_count=$(defaults read "${PLIST}" abortCount 2>/dev/null || echo 0)
  local first_date=$(defaults read "${PLIST}" firstPromptDate 2>/dev/null || echo 0)
  local script_version=$(defaults read "${PLIST}" scriptVersion 2>/dev/null || echo "")
  
  # Validate defer_count is numeric
  if ! [[ "$defer_count" =~ ^[0-9]+$ ]]; then
    log_warn "Invalid defer_count '$defer_count', resetting to 0"
    defer_count=0
    defaults write "${PLIST}" deferCount -int 0
  fi
  
  # Validate abort_count is numeric  
  if ! [[ "$abort_count" =~ ^[0-9]+$ ]]; then
    log_warn "Invalid abort_count '$abort_count', resetting to 0"
    abort_count=0
    defaults write "${PLIST}" abortCount -int 0
  fi
  
  # Validate first_date is numeric
  if ! [[ "$first_date" =~ ^[0-9]+$ ]]; then
    log_warn "Invalid first_date '$first_date', resetting to now"
    first_date=$(date -u +%s)
    defaults write "${PLIST}" firstPromptDate -string "$first_date"
  fi
  
  local now=$(date -u +%s)
  local elapsed=$((now - first_date))
  
  # Calculate state
  local max_deferrals_reached=false
  local timeout_exceeded=false
  local max_aborts_reached=false
  
  if (( defer_count >= MAX_DEFERS )); then
    max_deferrals_reached=true
  fi
  
  if (( elapsed >= FORCE_TIMEOUT_SECONDS )); then
    timeout_exceeded=true
  fi
  
  if (( abort_count >= MAX_ABORTS )); then
    max_aborts_reached=true
  fi
  
  # Determine overall state
  local can_defer=true
  local can_abort=true
  local force_install=false
  
  if [[ "$max_deferrals_reached" == "true" ]] || [[ "$timeout_exceeded" == "true" ]]; then
    can_defer=false
    force_install=true
  fi
  
  if [[ "$max_aborts_reached" == "true" ]]; then
    can_abort=false
  fi
  
  # Log current state
  local elapsed_hours=$((elapsed / 3600))
  local timeout_hours=$((FORCE_TIMEOUT_SECONDS / 3600))
  
  log_info "=== INSTALLATION STATE SUMMARY ==="
  log_info "Script version: $script_version (current: $SCRIPT_VERSION)"
  log_info "Deferrals used: $defer_count/$MAX_DEFERS"
  log_info "Aborts used: $abort_count/$MAX_ABORTS"
  log_info "Time elapsed: ${elapsed_hours}h/${timeout_hours}h"
  log_info "Max deferrals reached: $max_deferrals_reached"
  log_info "Timeout exceeded: $timeout_exceeded"
  log_info "Max aborts reached: $max_aborts_reached"
  log_info "Can defer: $can_defer"
  log_info "Can abort: $can_abort"
  log_info "Force install: $force_install"
  log_info "=================================="
  
  # Export state variables for other functions
  export CURRENT_DEFER_COUNT="$defer_count"
  export CURRENT_ABORT_COUNT="$abort_count"
  export CURRENT_FIRST_DATE="$first_date"
  export CURRENT_ELAPSED="$elapsed"
  export CAN_DEFER="$can_defer"
  export CAN_ABORT="$can_abort"
  export FORCE_INSTALL="$force_install"
  export DEFERRAL_EXCEEDED="$force_install"  # For backwards compatibility
  
  return 0
}

# ADD THIS FUNCTION after get_installation_state():
get_deferral_state() {
  # Backward compatibility function - calls the new function
  log_debug "get_deferral_state called - redirecting to get_installation_state"
  get_installation_state
}
        
# Increment defer count with validation
increment_defer_count() {
  local old_count="$CURRENT_DEFER_COUNT"
  local new_count=$((old_count + 1))
  
  log_info "Incrementing defer count from $old_count to $new_count"
  
  # Write with verification
  defaults write "${PLIST}" deferCount -int "$new_count"
  
  # Verify the write succeeded
  local verify_count
  verify_count=$(defaults read "${PLIST}" deferCount 2>/dev/null || echo "ERROR")
  if [[ "$verify_count" != "$new_count" ]]; then
    log_error "Failed to save new defer count (expected: $new_count, got: $verify_count)"
    return 1
  fi
  
  # Update exported variable and refresh all state
  export CURRENT_DEFER_COUNT="$new_count"
  
  # Refresh all state variables to ensure consistency
  get_installation_state
  
  log_info "Successfully incremented defer count to $new_count"
  return 0
}

# Increment abort count with validation
increment_abort_count() {
  local old_count="$CURRENT_ABORT_COUNT"
  local new_count=$((old_count + 1))
  
  log_info "Incrementing abort count from $old_count to $new_count"
  
  # Write with verification
  defaults write "${PLIST}" abortCount -int "$new_count"
  
  # Verify the write succeeded
  local verify_count
  verify_count=$(defaults read "${PLIST}" abortCount 2>/dev/null || echo "ERROR")
  if [[ "$verify_count" != "$new_count" ]]; then
    log_error "Failed to save new abort count (expected: $new_count, got: $verify_count)"
    return 1
  fi
  
  # Update exported variable
  export CURRENT_ABORT_COUNT="$new_count"
  log_info "Successfully incremented abort count to $new_count"
  return 0
}
        
# Save active abort daemon to plist for preservation
save_active_abort_daemon() {
  local daemon_label="$1"
  
  if [[ -z "$daemon_label" ]]; then
    log_warn "No daemon label provided to save_active_abort_daemon"
    return 1
  fi
  
  # Verify the daemon exists
  if [ ! -f "/Library/LaunchDaemons/${daemon_label}.plist" ]; then
    log_warn "Cannot save non-existent abort daemon: ${daemon_label}"
    return 1
  fi
  
  # Save the active abort daemon in the plist
  log_info "Saving active abort daemon: $daemon_label"
  defaults write "${PLIST}" activeAbortDaemon -string "${daemon_label}"
  
  # Save the current run ID separately to help with tracking
  local run_id="${daemon_label##*.}"
  if [ -n "$run_id" ]; then
    log_info "Saving abort run ID: $run_id"
    defaults write "${PLIST}" abortRunID -string "$run_id"
  fi
  
  return 0
}

# Reset all counters
reset_all_counters() {
  log_info "Resetting all counters and timers"
  
  defaults write "${PLIST}" deferCount -int 0
  defaults write "${PLIST}" abortCount -int 0
  defaults write "${PLIST}" firstPromptDate -string "$(date -u +%s)"
  
  # Update exported variables
  export CURRENT_DEFER_COUNT=0
  export CURRENT_ABORT_COUNT=0
  export CURRENT_FIRST_DATE=$(date -u +%s)
  export CURRENT_ELAPSED=0
  export CAN_DEFER=true
  export CAN_ABORT=true
  export FORCE_INSTALL=false
  export DEFERRAL_EXCEEDED=false
  
  log_info "All counters reset successfully"
}

# Check if user can perform specific action
can_user_defer() {
  [[ "$CAN_DEFER" == "true" ]]
}

can_user_abort() {
  [[ "$CAN_ABORT" == "true" ]]
}

must_force_install() {
  [[ "$FORCE_INSTALL" == "true" ]]
}

########################################################################################################################################################################
# ---------------- End Deferral State ----------------
########################################################################################################################################################################

# ---------------- LaunchDaemon ----------------

# Function to safely remove all LaunchDaemons
remove_existing_launchdaemon() {
  log_info "Checking for existing LaunchDaemons to remove..."
  local found_count=0
  local removed_count=0
  local is_scheduled=false
  local preserve_abort_daemon=false
  
  # Parse the arguments
  for arg in "$@"; do
    case "$arg" in
      --preserve-scheduled)
        is_scheduled=true
      ;;
      --preserve-abort-daemon)
        preserve_abort_daemon=true
      ;;
    esac
  done
  
  # Check if we have an active relaunch daemon to preserve
  local active_relaunch_daemon=$(defaults read "${PLIST}" activeRelaunchDaemon 2>/dev/null || echo "")
  if [[ -n "$active_relaunch_daemon" ]]; then
    log_info "Found active relaunch daemon in plist: $active_relaunch_daemon"
  fi
  
  # Check if we have an active abort daemon to preserve
  local active_abort_daemon=""
  if [[ "$RUNNING_FROM_ABORT_DAEMON" == "true" ]]; then
    # Try to identify our parent abort daemon
    if [ -n "$PPID" ]; then
      local parent_cmd=$(ps -o command= -p "$PPID" 2>/dev/null || echo "")
      if [[ "$parent_cmd" == *"com.macjediwizard.eraseinstall.abort"* ]]; then
        # Extract the abort daemon label from parent command
        active_abort_daemon=$(echo "$parent_cmd" | grep -o "com\.macjediwizard\.eraseinstall\.abort\.[0-9]\{14\}" | head -1)
        if [[ -n "$active_abort_daemon" ]]; then
          log_info "Found active abort daemon from parent process: $active_abort_daemon"
        fi
      fi
    fi
    
    # Fallback: check plist for stored abort daemon
    if [[ -z "$active_abort_daemon" ]]; then
      active_abort_daemon=$(defaults read "${PLIST}" activeAbortDaemon 2>/dev/null || echo "")
      if [[ -n "$active_abort_daemon" ]]; then
        log_info "Found active abort daemon from plist: $active_abort_daemon"
      fi
    fi
  fi
  
  # First forcefully remove lingering entries from launchctl
  for label in $(launchctl list 2>/dev/null | grep -E "com.macjediwizard.eraseinstall|com.github.grahampugh.erase-install" | awk '{print $3}'); do
    if [ -n "$label" ]; then
      # Skip if this is our active relaunch daemon
      if [[ -n "$active_relaunch_daemon" && "$label" == "$active_relaunch_daemon" ]]; then
        log_info "Preserving active relaunch daemon: $label"
        continue
      fi
      
      # Skip scheduled daemons if we're preserving them
      if [[ "${is_scheduled}" == "true" ]] && sudo launchctl list "${label}" 2>/dev/null | grep -q -- "--scheduled"; then
        log_info "Preserving scheduled daemon: ${label}"
        continue
      fi
      
      # Skip abort daemons if we're preserving them
      if [[ "$preserve_abort_daemon" == "true" && "${label}" == *".abort."* ]]; then
        # Only preserve the specific active abort daemon, not all abort daemons
        if [[ -n "$active_abort_daemon" && "$label" == "$active_abort_daemon" ]]; then
          log_info "Preserving active abort daemon: ${label}"
          continue
        elif [[ -z "$active_abort_daemon" ]]; then
          # If we can't identify the specific one, preserve all abort daemons as safety measure
          log_info "Preserving abort daemon (no specific active daemon identified): ${label}"
          continue
        else
          log_info "Removing non-active abort daemon: ${label}"
          # Don't continue - let it be removed
        fi
      fi
      
      log_info "Force removing lingering daemon: $label"
      launchctl remove "$label" 2>/dev/null || sudo launchctl remove "$label" 2>/dev/null || log_warn "Failed to remove: $label"
      # Also try bootout as a more modern approach
      launchctl bootout system/$label 2>/dev/null || sudo launchctl bootout system/$label 2>/dev/null
    fi
  done
  
  # Check for user-level agents
  for user in $(ls /Users); do
    user_id=$(id -u "$user" 2>/dev/null)
    if [ -n "$user_id" ]; then
      for label in $(launchctl asuser "$user_id" launchctl list 2>/dev/null | grep -E "com.macjediwizard.eraseinstall|com.github.grahampugh.erase-install" | awk '{print $3}'); do
        if [ -n "$label" ]; then
          # Skip if this relates to our active relaunch daemon
          if [[ -n "$active_relaunch_daemon" && "$label" == *"$active_relaunch_daemon"* ]]; then
            log_info "Preserving user-level agent related to active relaunch daemon: $label"
            continue
          fi
          
          log_info "Force removing lingering agent for user $user: $label"
          launchctl asuser "$user_id" sudo -u "$user" launchctl remove "$label" 2>/dev/null || log_warn "Failed to remove: $label"
          # Try another method
          launchctl asuser "$user_id" sudo -u "$user" launchctl unload "/Users/$user/Library/LaunchAgents/$label.plist" 2>/dev/null
          # Also try bootout for agents
          launchctl asuser "$user_id" launchctl bootout gui/$user_id/$label 2>/dev/null
        fi
      done
    fi
  done
  
  # Handle the erase-install startosinstall plist specifically - CRITICAL ADDITION
  if [ -f "/Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist" ]; then
    log_info "Directly handling com.github.grahampugh.erase-install.startosinstall.plist"
    sudo launchctl remove "com.github.grahampugh.erase-install.startosinstall" 2>/dev/null
    sudo launchctl bootout system/com.github.grahampugh.erase-install.startosinstall 2>/dev/null
    sudo rm -f "/Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist"
    log_info "Removed com.github.grahampugh.erase-install.startosinstall.plist"
  fi
  
  # Get a list of loaded daemons
  local loaded_daemons
  loaded_daemons=$(launchctl list 2>/dev/null | grep -E "com.macjediwizard.eraseinstall|com.github.grahampugh.erase-install" | awk '{print $3}' 2>/dev/null || echo "")
  
  if [ -n "${loaded_daemons}" ]; then
    log_debug "Found loaded daemons: ${loaded_daemons}"
    while IFS= read -r label; do
      [ -z "${label}" ] && continue
      
      # Skip if this is our active relaunch daemon
      if [[ -n "$active_relaunch_daemon" && "$label" == "$active_relaunch_daemon" ]]; then
        log_info "Preserving active relaunch daemon: ${label}"
        continue
      fi
      
      # Skip scheduled daemons if we're preserving them
      if [[ "${is_scheduled}" == "true" ]] && sudo launchctl list "${label}" 2>/dev/null | grep -q -- "--scheduled"; then
        log_info "Preserving scheduled daemon: ${label}"
        continue
      fi
      
      # Skip abort daemons if we're preserving them
      if [[ "$preserve_abort_daemon" == "true" && "${label}" == *".abort."* ]]; then
        # Only preserve the specific active abort daemon, not all abort daemons
        if [[ -n "$active_abort_daemon" && "$label" == "$active_abort_daemon" ]]; then
          log_info "Preserving active abort daemon: ${label}"
          continue
        elif [[ -z "$active_abort_daemon" ]]; then
          # If we can't identify the specific one, preserve all abort daemons as safety measure
          log_info "Preserving abort daemon (no specific active daemon identified): ${label}"
          continue
        else
          log_info "Removing non-active abort daemon: ${label}"
          # Don't continue - let it be removed
        fi
      fi
      
      log_info "Unloading daemon: ${label}"
      # Try multiple methods to unload the daemon - most reliable first
      if [ -f "/Library/LaunchDaemons/${label}.plist" ]; then
        if ! sudo launchctl unload -w "/Library/LaunchDaemons/${label}.plist" 2>/dev/null; then
          # Try remove first
          if ! sudo launchctl remove "${label}" 2>/dev/null; then
            # Fall back to bootout with direct label
            if ! sudo launchctl bootout system/${label} 2>/dev/null; then
              log_error "Failed to unload: ${label}"
            else
              log_info "Successfully booted out: ${label}"
            fi
          else
            log_info "Successfully removed daemon: ${label}"
          fi
        else
          log_info "Successfully unloaded: ${label}"
        fi
      else
        # No plist file but service is loaded - try direct removal
        if ! sudo launchctl remove "${label}" 2>/dev/null; then
          # Fall back to bootout
          if ! sudo launchctl bootout system/${label} 2>/dev/null; then
            log_error "Failed to bootout: ${label}"
          else
            log_info "Successfully booted out: ${label}"
          fi
        else
          log_info "Successfully removed daemon: ${label}"
        fi
      fi
    done <<< "${loaded_daemons}"
  else
    log_debug "No loaded daemons found"
  fi
  
  # Find and remove ALL matching plist files, even if not loaded
  while IFS= read -r file; do
    [ -z "${file}" ] && continue
    
    # Get the file label (filename without path or extension)
    local file_label=$(basename "$file" .plist)
    
    # Skip if this is our active relaunch daemon
    if [[ -n "$active_relaunch_daemon" && "$file_label" == "$active_relaunch_daemon" ]]; then
      log_info "Preserving active relaunch daemon file: ${file}"
      continue
    fi
    
    # Skip scheduled daemons if we're preserving them
    if [[ "${is_scheduled}" == "true" ]] && grep -q -- "--scheduled" "${file}" 2>/dev/null; then
      log_info "Preserving scheduled daemon file: ${file}"
      continue
    fi
    
    # Skip abort daemons if we're preserving them
    if [[ "$preserve_abort_daemon" == "true" && "${file}" == *".abort."* ]]; then
      log_info "Preserving abort daemon file: ${file}"
      continue
    fi
    
    ((found_count++))
    log_info "Removing LaunchDaemon file: ${file}"
    if sudo rm -f "${file}"; then
      ((removed_count++))
      log_info "Removed file: ${file}"
    else
      log_error "Failed to remove: ${file}"
      # Try with force - create a more aggressive removal
      sudo rm -f "${file}" 2>/dev/null && log_info "Force removed on second attempt: ${file}"
    fi
  done < <(find /Library/LaunchDaemons -type f -name "*.plist" | grep -E "com.macjediwizard.eraseinstall|com.github.grahampugh.erase-install" 2>/dev/null)
  
  # Also check for user LaunchAgents
  for user in $(ls /Users); do
    if [ -d "/Users/$user/Library/LaunchAgents" ]; then
      while IFS= read -r file; do
        [ -z "${file}" ] && continue
        
        # Get the file label
        local file_label=$(basename "$file" .plist)
        
        # Skip if this relates to our active relaunch daemon
        if [[ -n "$active_relaunch_daemon" && "$file_label" == *"$active_relaunch_daemon"* ]]; then
          log_info "Preserving user agent file related to active relaunch daemon: ${file}"
          continue
        fi
          
        # Skip scheduled agents if we're preserving them
        if [[ "${is_scheduled}" == "true" ]] && grep -q -- "--scheduled" "${file}" 2>/dev/null; then
          log_info "Preserving scheduled agent file: ${file}"
          continue
        fi
        
        # Skip abort agent files if we're preserving them
        if [[ "$preserve_abort_daemon" == "true" && "${file}" == *".abort."* ]]; then
          log_info "Preserving abort agent file: ${file}"
          continue
        fi
        
        ((found_count++))
        log_info "Removing LaunchAgent file: ${file}"
        if sudo -u "$user" rm -f "${file}"; then
          ((removed_count++))
          log_info "Removed file: ${file}"
        else
          log_error "Failed to remove: ${file}"
          # Try with force
          sudo rm -f "${file}" 2>/dev/null && log_info "Force removed on second attempt: ${file}"
        fi
        done < <(find "/Users/$user/Library/LaunchAgents" -type f -name "*.plist" | grep -E "com.macjediwizard.eraseinstall|com.github.grahampugh.erase-install" 2>/dev/null)
      fi
    done
    
    # Final explicit check and removal of known paths
    for file in "${LAUNCHDAEMON_PATH}" "${LAUNCHDAEMON_PATH}.bak" "/Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist"; do
      if [ -f "${file}" ]; then
        # Skip if this is related to our active relaunch daemon
        local this_label=$(basename "$file" .plist)
        if [[ -n "$active_relaunch_daemon" && "$this_label" == "$active_relaunch_daemon" ]]; then
          log_info "Preserving active relaunch daemon file: ${file}"
          continue
        fi
        
        log_warn "Found remaining LaunchDaemon file: ${file}"
        if sudo rm -f "${file}"; then
          log_info "Forcefully removed file: ${file}"
          ((removed_count++))
        else
          log_error "Failed to forcefully remove: ${file}"
        fi
      fi
    done
    
    # Also cleanup helper scripts and watchdog scripts
    # Preserve any related to our active relaunch daemon
    if [[ -n "$active_relaunch_daemon" ]]; then
      # Extract ID from the relaunch daemon label
      local active_id=$(echo "$active_relaunch_daemon" | grep -o '[0-9]\{14\}' || echo "")
      
      if [[ -n "$active_id" ]]; then
        log_info "Preserving watchdog scripts for active ID: $active_id"
        # Remove other watchdog scripts
        sudo find "/Library/Management/erase-install" -name "erase-install-watchdog-*.sh" -not -name "*${active_id}*" -delete 2>/dev/null
      else
        sudo rm -f "/Library/Management/erase-install/erase-install-watchdog-*.sh" 2>/dev/null
      fi
    else
      sudo rm -f "/Library/Management/erase-install/erase-install-watchdog-*.sh" 2>/dev/null
    fi
    
    # For helper scripts in user directories, preserve active ones
    for user in $(ls /Users); do
      if [[ -n "$active_relaunch_daemon" ]]; then
        # Extract ID from the relaunch daemon label
        local active_id=$(echo "$active_relaunch_daemon" | grep -o '[0-9]\{14\}' || echo "")
        
        if [[ -n "$active_id" ]]; then
          # Remove other helper scripts
          sudo -u "$user" find "/Users/$user/Library/Application Support" -name "erase-install-helper-*.sh" -not -name "*${active_id}*" -delete 2>/dev/null
        else
          sudo -u "$user" rm -f "/Users/$user/Library/Application Support/erase-install-helper-*.sh" 2>/dev/null
        fi
      else
        sudo -u "$user" rm -f "/Users/$user/Library/Application Support/erase-install-helper-*.sh" 2>/dev/null
      fi
    done
    
    # Clean up trigger files
    if [[ -n "$active_relaunch_daemon" ]]; then
      # Extract ID from the relaunch daemon label
      local active_id=$(echo "$active_relaunch_daemon" | grep -o '[0-9]\{14\}' || echo "")
      
      if [[ -n "$active_id" ]]; then
        # Remove other trigger files
        sudo find "/var/tmp" -name "erase-install-trigger-*" -not -name "*${active_id}*" -delete 2>/dev/null
      else
        sudo rm -f /var/tmp/erase-install-trigger* 2>/dev/null
      fi
    else
      sudo rm -f /var/tmp/erase-install-trigger* 2>/dev/null
    fi
    
    # Clean up any control files left by erase-install
    sudo rm -f /var/tmp/dialog.* 2>/dev/null
    
    # Final explicit check for any remaining files - use find directly
    log_info "Performing final deep cleanup check for any remaining files"
    for plist in $(sudo find /Library/LaunchDaemons -name "*eraseinstall*.plist" -o -name "*erase-install*.plist" 2>/dev/null); do
      # Skip if this is our active relaunch daemon
      local this_label=$(basename "$plist" .plist)
      if [[ -n "$active_relaunch_daemon" && "$this_label" == "$active_relaunch_daemon" ]]; then
        log_info "Preserving active relaunch daemon file in final cleanup: ${plist}"
        continue
      fi
      
      log_info "Found remaining daemon file: $plist"
      sudo rm -f "$plist" && log_info "Removed: $plist" || log_error "Failed to remove: $plist"
    done
    
    # Report results
    if [ ${found_count} -gt 0 ]; then
      log_info "LaunchDaemon cleanup complete. Removed: ${removed_count}, Failed: $((found_count - removed_count))"
    else
      log_debug "No LaunchDaemons found to remove"
    fi
    
    # Final verification - check if any lingering daemons remain
    if launchctl list 2>/dev/null | grep -q -E "com.macjediwizard.eraseinstall|com.github.grahampugh.erase-install"; then
      log_warn "Some launch items may still be registered despite cleanup"
      # Force unload all remaining items except our active relaunch daemon
      for label in $(launchctl list 2>/dev/null | grep -E "com.macjediwizard.eraseinstall|com.github.grahampugh.erase-install" | awk '{print $3}'); do
        # Skip if this is our active relaunch daemon
        if [[ -n "$active_relaunch_daemon" && "$label" == "$active_relaunch_daemon" ]]; then
          log_info "Preserving active relaunch daemon in final verification: ${label}"
          continue
        fi
        
        log_info "Final attempt to remove daemon: $label"
        sudo launchctl remove "$label" 2>/dev/null
      done
    fi
    
    # One final check for the problematic daemons using wildcard patterns
    for problematic_pattern in "/Library/LaunchDaemons/com.github.grahampugh.erase-install.*.plist" "/Library/LaunchDaemons/com.macjediwizard.eraseinstall.*.plist"; do
      for daemon in $(ls $problematic_pattern 2>/dev/null); do
        if [ -f "$daemon" ]; then
          # Get the daemon label (filename without path or extension)
          local daemon_label=$(basename "$daemon" .plist)
          
          # Skip if this is our active relaunch daemon
          if [[ -n "$active_relaunch_daemon" && "$daemon_label" == "$active_relaunch_daemon" ]]; then
            log_info "Preserving active relaunch daemon in problematic check: ${daemon}"
            continue
          fi
          
          log_warn "Critical: Found problematic daemon after cleanup: $daemon"
          # Try to unload it
          sudo launchctl remove "$daemon_label" 2>/dev/null
          # Then remove the file
          sudo rm -f "$daemon" && log_info "Forcefully removed: $daemon" || log_error "FAILED to forcefully remove: $daemon"
        fi
      done
    done
    
    # Verify cleanup
    local verify_failed=false
    for file in "${LAUNCHDAEMON_PATH}" "${LAUNCHDAEMON_PATH}.bak" "/Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist"; do
      if [ -f "${file}" ]; then
        # Skip verification for active relaunch daemon
        local this_label=$(basename "$file" .plist)
        if [[ -n "$active_relaunch_daemon" && "$this_label" == "$active_relaunch_daemon" ]]; then
          log_info "Active relaunch daemon still present as expected: ${file}"
          continue
        fi
          
        log_error "LaunchDaemon cleanup incomplete - files still exist: ${file}"
        verify_failed=true
      fi
    done
    
    if [[ "$verify_failed" == "true" ]]; then
      return 1
    fi
    
  return 0
}

# Function to ensure cleanup after erase-install runs
post_erase_install_cleanup() {
  log_info "Performing post-installation cleanup"
  
  # Wait briefly to ensure erase-install completes its operations
  sleep 5
  
  # In test mode with OS checks skipped, be more careful with cleanup
  if [[ "${SKIP_OS_VERSION_CHECK}" == "true" ]]; then
    log_info "Test mode with OS version check skipped - performing targeted cleanup"
    
    # Only remove the known erase-install daemon without affecting scheduled daemons
    if [ -f "/Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist" ]; then
      log_warn "Found startosinstall daemon after erase-install completed"
      sudo launchctl remove "com.github.grahampugh.erase-install.startosinstall" 2>/dev/null
      sudo launchctl bootout system/com.github.grahampugh.erase-install.startosinstall 2>/dev/null
      sudo rm -f "/Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist"
      log_info "Removed startosinstall daemon"
    fi
  else
    # Standard cleanup for normal operation
    # Clean up any remaining launch items
    remove_existing_launchdaemon
    
    # Specifically check for the problematic startosinstall daemon
    if [ -f "/Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist" ]; then
      log_warn "Found startosinstall daemon after erase-install completed"
      sudo launchctl remove "com.github.grahampugh.erase-install.startosinstall" 2>/dev/null
      sudo launchctl bootout system/com.github.grahampugh.erase-install.startosinstall 2>/dev/null
      sudo rm -f "/Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist"
      log_info "Removed startosinstall daemon"
    fi
    
    # Handle any lingering watchdog daemons
    for watchdog in $(ls /Library/LaunchDaemons/com.macjediwizard.eraseinstall.schedule.watchdog.*.plist 2>/dev/null); do
      if [ -f "$watchdog" ]; then
        log_warn "Found lingering watchdog daemon: $watchdog"
        label=$(basename "$watchdog" .plist)
        sudo launchctl remove "$label" 2>/dev/null
        sudo launchctl bootout system/$label 2>/dev/null
        sudo rm -f "$watchdog"
        log_info "Removed watchdog daemon: $watchdog"
      fi
    done
  fi
  
  log_info "Post-installation cleanup completed"
}

create_scheduled_launchdaemon() {
  local hour="$1" minute="$2" day="$3" month="$4" mode="$5"
  
  # Add debug logging for input parameters
  log_debug "create_scheduled_launchdaemon called with: hour=$hour, minute=$minute, day=$day, month=$month, mode=$mode"
  
  # Detect our parent relaunch daemon, if any
  if [ -n "$PPID" ]; then
    local parent_cmd=$(ps -o command= -p "$PPID" 2>/dev/null || echo "")
    local parent_args=$(ps -o args= -p "$PPID" 2>/dev/null || echo "")
    
    if [[ "$parent_cmd" == *"com.macjediwizard.eraseinstall.relaunch."* ]]; then
      # We're running under a relaunch daemon
      if [[ "$parent_cmd" =~ com\.macjediwizard\.eraseinstall\.relaunch\.([0-9]+) ]]; then
        log_info "Running under relaunch daemon for defer sequence - preserving parent: $parent_cmd"
        PARENT_RELAUNCH_DAEMON="${BASH_REMATCH[0]}"
        PARENT_RELAUNCH_ID="${BASH_REMATCH[1]}"
        log_info "Parent relaunch daemon: $PARENT_RELAUNCH_DAEMON (ID: $PARENT_RELAUNCH_ID)"
        
        # Export variables to make them available to child processes
        export PARENT_RELAUNCH_DAEMON PARENT_RELAUNCH_ID
        # Also set a global variable to indicate we're running from a relaunch daemon
        export RUNNING_FROM_RELAUNCH_DAEMON=true
      fi
    fi
  fi
  
  # Convert all values to base-10 integers
  local hour_num=$((10#${hour}))
  local minute_num=$((10#${minute}))
  local day_num=$([ -n "$day" ] && printf '%d' "$((10#${day}))" || echo "")
  local month_num=$([ -n "$month" ] && printf '%d' "$((10#${month}))" || echo "")
  
  # Validate input parameters
  if [[ $hour_num -lt 0 || $hour_num -gt 23 || $minute_num -lt 0 || $minute_num -gt 59 ]]; then
    log_error "Invalid time parameters: hour=$hour_num, minute=$minute_num"
    return 1
  fi
  
  # Generate a unique ID for this scheduled run
  local run_id="$(date +%Y%m%d%H%M%S)"
  log_debug "Generated run_id: $run_id"
  
  # Store this run_id as the active relaunch daemon if this is a defer operation
  if [[ "$mode" == "defer" ]]; then
    # Define the relaunch daemon label using the current run_id
    local relaunch_daemon_label="com.macjediwizard.eraseinstall.relaunch.${run_id}"
    log_info "Setting active relaunch daemon: $relaunch_daemon_label"
    
    # Store in the plist for persistence
    defaults write "${PLIST}" activeRelaunchDaemon -string "${relaunch_daemon_label}"
    
    # Before creating a new relaunch daemon, check if there's an existing one
    # that's different from the one we're about to create
    local previous_relaunch=$(defaults read "${PLIST}" activeRelaunchDaemon 2>/dev/null || echo "")
    if [[ -n "$previous_relaunch" && "$previous_relaunch" != "$relaunch_daemon_label" ]]; then
      log_info "Found previous relaunch daemon: $previous_relaunch"
      log_info "New relaunch daemon will be: $relaunch_daemon_label"
      
      # We don't need to do anything here as the remove_existing_launchdaemon function
      # will preserve the current active relaunch daemon and clean up any old ones
    fi
  fi
  
  # Set the global variable for other functions to access
  CURRENT_RUN_ID="$run_id"
  
  # Debug info
  [[ "${DEBUG_MODE}" = true ]] && log_debug "Creating scheduled items for ${hour_num}:${minute_num} with test_mode=${TEST_MODE}, debug_mode=${DEBUG_MODE}"
  
  # Create a shared trigger file that will connect the UI and installation processes
  local trigger_file="/var/tmp/erase-install-trigger-${run_id}"
  
  # Get console user for UI references
  local console_user=""
  console_user=$(get_console_user)
  
  # 1. Create the LaunchAgent for UI display
  local agent_label="${LAUNCHDAEMON_LABEL}.ui.${run_id}"
  local agent_path="/Users/$console_user/Library/LaunchAgents/$agent_label.plist"
  
  # Remove existing agents first
  sudo -u "$console_user" rm -f "$agent_path"
  
  # Create directory if it doesn't exist
  sudo -u "$console_user" mkdir -p "/Users/$console_user/Library/LaunchAgents"
  
  # For test mode, add indication in the dialog title
  local display_title="$SCHEDULED_TITLE"
  [[ "$TEST_MODE" = true ]] && display_title="${SCHEDULED_TITLE_TEST_MODE}"
  
  # Create a helper script that will run dialog and then trigger the installer
  local helper_script="/Users/$console_user/Library/Application Support/erase-install-helper-${run_id}.sh"
  mkdir -p "/Users/$console_user/Library/Application Support"
  
  # Determine if abort button should be shown
  local abort_button_code=""
  local USE_ABORT_BUTTON=false
  if [[ "$mode" == "scheduled" && "${ENABLE_ABORT_BUTTON}" == "true" ]]; then
    # Check current abort count
    local abort_count=$(defaults read "${PLIST}" abortCount 2>/dev/null || echo 0)
    if [[ $abort_count -lt $MAX_ABORTS ]]; then
      # Enable abort button
      log_info "Adding abort button to dialog (abort count: ${abort_count}/${MAX_ABORTS})"
      USE_ABORT_BUTTON=true
    else
      log_info "Maximum aborts reached (${abort_count}/${MAX_ABORTS}) - not showing abort button"
    fi
  fi
  
  cat > "$helper_script" << EOF
#!/bin/bash

# Run dialog with countdown
export DISPLAY=:0
export PATH='/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'

# Log script execution
LOG_FILE="/Users/$console_user/Library/Logs/erase-install-wrapper-ui.${run_id}.log"
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Helper script starting" >> "\$LOG_FILE"

# Force GUI and dialog environment settings
defaults write org.swift.SwiftDialog FrontmostApplication -bool true

# Enhanced environment for GUI apps
defaults write com.apple.WindowServer StartupStatus No
defaults write com.apple.dock contents-immutable -bool false

# Log process details for debugging
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Running as user: \$(whoami) with EUID: \$EUID" >> "\$LOG_FILE"
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Dialog exists: \$([ -x "${DIALOG_BIN}" ] && echo 'Yes' || echo 'No')" >> "\$LOG_FILE"

# CRITICALLY IMPORTANT: Create another trigger file to signal we're about to show UI
touch "/var/tmp/erase-install-ui-starting-${run_id}"
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Created UI start signal file" >> "\$LOG_FILE"

# Create dialog output file for JSON parsing
DIALOG_OUTPUT_FILE="/tmp/dialog-output-${run_id}.json"

# Display dialog with countdown - enhanced for visibility and JSON output
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Starting dialog with elevated priority" >> "\$LOG_FILE"
"${DIALOG_BIN}" --title "${display_title}" \\
--message "${SCHEDULED_MESSAGE}" \\
--button1text "${SCHEDULED_CONTINUE_TEXT}" \\
$([[ "$USE_ABORT_BUTTON" == "true" ]] && echo "  --button2text '${ABORT_BUTTON_TEXT}' \\") \\
--icon "${DIALOG_ICON}" \\
--height ${SCHEDULED_CONTINUE_HEIGHT} \\
--width ${SCHEDULED_CONTINUE_WIDTH} \\
--moveable \\
--ontop \\
--position "${DIALOG_POSITION}" \\
--messagefont ${SCHEDULED_DIALOG_MESSAGEFONT} \\
--progress ${SCHEDULED_COUNTDOWN} \\
--progresstext "${SCHEDULED_PROGRESS_TEXT_MESSAGE}" \\
--timer ${SCHEDULED_COUNTDOWN} \\
--jsonoutput > "\$DIALOG_OUTPUT_FILE"

DIALOG_RESULT=\$?
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Dialog completed with status: \$DIALOG_RESULT" >> "\$LOG_FILE"

# ENHANCED ABORT DETECTION - Multiple detection methods
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Starting abort detection with multiple methods" >> "\$LOG_FILE"

# Method 1: Check dialog exit code first (most reliable for button detection)
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Method 1 - Dialog exit code: \$DIALOG_RESULT" >> "\$LOG_FILE"
ABORT_DETECTED=false

# SwiftDialog typically returns exit code 2 when button 2 is clicked
if [ \$DIALOG_RESULT -eq 2 ]; then
  echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Exit code 2 detected - abort button clicked" >> "\$LOG_FILE"
  ABORT_DETECTED=true
fi

# Method 2: Check JSON file if exit code didn't indicate abort
if [ "\$ABORT_DETECTED" = "false" ] && [ -f "\$DIALOG_OUTPUT_FILE" ]; then
  echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Method 2 - Checking JSON output file" >> "\$LOG_FILE"
  
  # Check if file has content
  if [ -s "\$DIALOG_OUTPUT_FILE" ]; then
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] JSON file has content, parsing..." >> "\$LOG_FILE"
    
    # Log the full JSON for debugging
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Full dialog JSON output:" >> "\$LOG_FILE"
    cat "\$DIALOG_OUTPUT_FILE" >> "\$LOG_FILE" 2>&1
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] End of JSON output" >> "\$LOG_FILE"
    
    # Try multiple JSON parsing methods
    BUTTON_CLICKED=\$(cat "\$DIALOG_OUTPUT_FILE" | grep "button" | cut -d':' -f2 | tr -d '" ,' | xargs)
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Parsed button value: '\$BUTTON_CLICKED'" >> "\$LOG_FILE"
    
    if [[ "\$BUTTON_CLICKED" == "2" ]]; then
      echo "[\$(date '+%Y-%m-%d %H:%M:%S')] JSON parsing detected abort button" >> "\$LOG_FILE"
      ABORT_DETECTED=true
    fi
  else
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] JSON file is empty - SwiftDialog may not support JSON with timer/progress" >> "\$LOG_FILE"
  fi
else
  echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Skipping JSON check - abort already detected or file missing" >> "\$LOG_FILE"
fi

# Method 3: Final fallback - check for abort signal file created by another process
if [ "\$ABORT_DETECTED" = "false" ] && [ -f "/var/tmp/erase-install-abort-${run_id}" ]; then
  echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Method 3 - Found existing abort signal file" >> "\$LOG_FILE"
  ABORT_DETECTED=true
fi

echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Final abort detection result: \$ABORT_DETECTED" >> "\$LOG_FILE"

# Process abort if detected by any method
if [ "\$ABORT_DETECTED" = "true" ]; then
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] ✅ ABORT BUTTON CLICKED - Starting abort processing" >> "\$LOG_FILE"
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Run ID: ${run_id}" >> "\$LOG_FILE"

# Create abort file for watchdog to detect with verification
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Creating abort signal file..." >> "\$LOG_FILE"
touch "/var/tmp/erase-install-abort-${run_id}"

# Verify abort file was created
if [ -f "/var/tmp/erase-install-abort-${run_id}" ]; then
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] ✅ Abort signal file created successfully" >> "\$LOG_FILE"
ls -la "/var/tmp/erase-install-abort-${run_id}" >> "\$LOG_FILE" 2>&1
else
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] ❌ ERROR: Failed to create abort signal file" >> "\$LOG_FILE"
sudo touch "/var/tmp/erase-install-abort-${run_id}" 2>&1 >> "\$LOG_FILE"
fi

# Show abort countdown dialog
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Displaying abort confirmation dialog" >> "\$LOG_FILE"
"${DIALOG_BIN}" --title "Aborting Installation" \\
--message "Emergency abort activated. Installation will be postponed for ${ABORT_DEFER_MINUTES} minutes." \\
--icon ${ABORT_ICON} \\
--button1text "OK" \\
--timer ${ABORT_COUNTDOWN} \\
--progress ${ABORT_COUNTDOWN} \\
--progresstext "Aborting in ${ABORT_COUNTDOWN} seconds..." \\
--position "${DIALOG_POSITION}" \\
--moveable \\
--ontop \\
--height ${ABORT_HEIGHT} \\
--width ${ABORT_WIDTH} 

# Signal success to the user
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Sending user notification" >> "\$LOG_FILE"
osascript -e "display notification \"Installation aborted and will be rescheduled\" with title \"macOS Upgrade\"" 2>/dev/null || true

echo "[\$(date '+%Y-%m-%d %H:%M:%S')] ✅ ABORT PROCESSING COMPLETE - Exiting helper script" >> "\$LOG_FILE"
# Exit without creating trigger file
exit 0
else
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ Dialog output file not found - cannot parse abort status" >> "\$LOG_FILE"
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Expected file: \$DIALOG_OUTPUT_FILE" >> "\$LOG_FILE"
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Dialog exit code was: \$DIALOG_RESULT" >> "\$LOG_FILE"
    # Continue with normal flow since we can't detect abort
  fi

# Wait for watchdog to be ready before creating trigger file
WATCHDOG_READY_FLAG="/var/tmp/erase-install-watchdog-ready-${run_id}"
TIMEOUT=60  # Increased timeout
COUNTER=0

# Wait for watchdog to be ready or timeout
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Waiting for watchdog to be ready..." >> "\$LOG_FILE"
while [ ! -f "\$WATCHDOG_READY_FLAG" ] && [ \$COUNTER -lt \$TIMEOUT ]; do
sleep 1
COUNTER=\$((COUNTER + 1))
# Log progress every 10 seconds
if [ \$((COUNTER % 10)) -eq 0 ]; then
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Still waiting: \$COUNTER seconds elapsed" >> "\$LOG_FILE"
fi
done

if [ -f "\$WATCHDOG_READY_FLAG" ]; then
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Watchdog is ready, creating trigger file" >> "\$LOG_FILE"
# Create trigger file to start installation
touch "$trigger_file"
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Created trigger file: $trigger_file" >> "\$LOG_FILE"
# Wait to verify trigger file was created
sleep 1
if [ -f "$trigger_file" ]; then
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Trigger file verified" >> "\$LOG_FILE"
else
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Trigger file not found after creation" >> "\$LOG_FILE"
fi
else
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] WARNING: Watchdog not ready after \$TIMEOUT seconds" >> "\$LOG_FILE"
# Create trigger file anyway as last resort
touch "$trigger_file"
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Created trigger file anyway: $trigger_file" >> "\$LOG_FILE"
# Wait to verify trigger file was created
sleep 1
if [ -f "$trigger_file" ]; then
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Trigger file verified" >> "\$LOG_FILE"
else
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Trigger file not found after creation" >> "\$LOG_FILE"
fi
fi

# Self-cleanup - unload the agent and remove it
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Cleaning up agent: $agent_label" >> "\$LOG_FILE"

# Try ALL methods to ensure agent is unloaded
launchctl unload "$agent_path" 2>/dev/null && echo "Unloaded agent via unload command" >> "\$LOG_FILE"
launchctl remove "$agent_label" 2>/dev/null && echo "Removed agent via remove command" >> "\$LOG_FILE"
launchctl bootout gui/\$(id -u)/"$agent_label" 2>/dev/null && echo "Booted out agent via bootout command" >> "\$LOG_FILE"

# Remove the agent file
rm -f "$agent_path" 2>/dev/null && echo "Removed agent file" >> "\$LOG_FILE"

# Create cleanup signal
touch "/var/tmp/erase-install-ui-completed-${run_id}"
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Created UI completion file" >> "\$LOG_FILE"

# Clean up dialog output file
rm -f "\$DIALOG_OUTPUT_FILE" 2>/dev/null

# Delete self with delay to ensure complete execution
(sleep 5 && rm -f "$0" && echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Helper script self-cleaned" >> "\$LOG_FILE") &

exit 0
EOF
  
  # Set proper ownership and permissions
  chmod +x "$helper_script"
  chown "$console_user" "$helper_script"
  
  # Create the plist content for user agent to run the helper script
  local agent_content="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
<key>Label</key>
<string>${agent_label}</string>
<key>ProgramArguments</key>
<array>
<string>/bin/bash</string>
<string>$helper_script</string>
</array>
<key>StartCalendarInterval</key>
<dict>
<key>Hour</key>
<integer>${hour_num}</integer>
<key>Minute</key>
<integer>${minute_num}</integer>
$([ -n "${day_num}" ] && printf "        <key>Day</key>\n        <integer>%d</integer>\n" "${day_num}")
$([ -n "${month_num}" ] && printf "        <key>Month</key>\n        <integer>%d</integer>\n" "${month_num}")
</dict>
<key>StandardOutPath</key>
<string>/Users/${console_user}/Library/Logs/erase-install-wrapper-ui.${run_id}.log</string>
<key>StandardErrorPath</key>
<string>/Users/${console_user}/Library/Logs/erase-install-wrapper-ui.${run_id}.log</string>
<key>RunAtLoad</key>
<false/>
<key>LaunchOnlyOnce</key>
<true/>
<key>AbandonProcessGroup</key>
<true/>
<key>ProcessType</key>
<string>Interactive</string>
<key>SessionCreate</key>
<true/>
<key>LowPriorityIO</key>
<false/>
<key>EnvironmentVariables</key>
<dict>
<key>PATH</key>
<string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
<key>LANG</key>
<string>en_US.UTF-8</string>
<key>DISPLAY</key>
<string>:0</string>
<key>DIALOG_CMD_FILE</key>
<string>/var/tmp/dialog-cmd-${run_id}</string>
</dict>
</dict>
</plist>"
  
  # 2. Create a watchdog script that will monitor for the trigger file
  local watchdog_script="/Library/Management/erase-install/erase-install-watchdog-${run_id}.sh"
  mkdir -p "/Library/Management/erase-install"
  
  # Verify WRAPPER_PATH before creating watchdog script
  if [ ! -f "${WRAPPER_PATH}" ]; then
    log_warn "WRAPPER_PATH (${WRAPPER_PATH}) does not exist. Using fallback path."
    # Try to find the script in standard locations
    if [ -f "/Library/Management/erase-install/erase-install-defer-wrapper.sh" ]; then
      WRAPPER_PATH="/Library/Management/erase-install/erase-install-defer-wrapper.sh"
    elif [ -f "/usr/local/bin/erase-install-defer-wrapper.sh" ]; then
      WRAPPER_PATH="/usr/local/bin/erase-install-defer-wrapper.sh"
    elif [ -f "/Users/Shared/erase-install-defer-wrapper.sh" ]; then
      WRAPPER_PATH="/Users/Shared/erase-install-defer-wrapper.sh"
    fi
  fi
  log_info "Using main script path: ${WRAPPER_PATH} for deferred execution"
  
  # Helper function to verify script substitutions (to be used only in debug mode)
  verify_script_substitutions() {
    local script_path="$1"
    log_info "Verifying critical parameter substitutions in watchdog script..."
    
    for param in "PREVENT_ALL_REBOOTS" "TEST_MODE" "REINSTALL"; do
      if grep -q "${param}=\"true\"" "$script_path"; then
        log_info "SCRIPT DEBUG: ✅ ${param} successfully set to 'true' in watchdog script"
      elif grep -q "${param}=\"false\"" "$script_path"; then
        log_info "SCRIPT DEBUG: ✅ ${param} successfully set to 'false' in watchdog script"
      else
        log_error "SCRIPT DEBUG: ❌ Failed to properly substitute ${param} in watchdog script"
        grep "${param}" "$script_path" | head -1 | log_debug
      fi
    done
  }
  
  # Function to validate the watchdog script for syntax errors
  validate_watchdog_script() {
    local script_path="$1"
    log_info "Validating watchdog script integrity..."
    
    local validation_output=$(bash -n "$script_path" 2>&1)
    if [ $? -ne 0 ]; then
      log_error "CRITICAL: Generated watchdog script contains syntax errors:"
      log_error "$validation_output"
      
      # Create a backup for troubleshooting
      local watchdog_backup="${script_path}.broken-$(date +%s)"
      cp "$script_path" "$watchdog_backup"
      log_error "Created backup at ${watchdog_backup} for troubleshooting"
      
      # Log script size and last few lines for debugging
      log_error "Generated script size: $(wc -l < "$script_path") lines"
      log_error "Last 10 lines of script for debugging:"
      tail -10 "$script_path" | while IFS= read -r line; do
        log_error "  $line"
      done
      
      return 1
    fi
    
    log_info "Watchdog script validation successful"
    return 0
  }
  
  # Function to load and verify LaunchDaemon
  load_and_verify_daemon() {
    local daemon_path="$1"
    local daemon_label="$2"
    local max_attempts=3
    local attempt=1
    
    log_info "Loading LaunchDaemon: $daemon_label (path: $daemon_path)"
    
    # First verify the daemon file exists
    if [ ! -f "$daemon_path" ]; then
      log_error "LaunchDaemon file does not exist: $daemon_path"
      return 1
    fi
    
    # Try to load the daemon
    while [ $attempt -le $max_attempts ]; do
      log_info "Loading attempt $attempt/$max_attempts..."
      
      # Try multiple loading methods
      sudo launchctl load "$daemon_path" 2>/dev/null || 
      sudo launchctl bootstrap system "$daemon_path" 2>/dev/null ||
      sudo launchctl kickstart system/"$daemon_label" 2>/dev/null
      
      # Verify if it was loaded successfully
      sleep 1
      if sudo launchctl list | grep -q "$daemon_label"; then
        log_info "✅ Successfully loaded and verified LaunchDaemon: $daemon_label"
        return 0
      fi
      
      log_warn "Load attempt $attempt failed, retrying..."
      sleep 2
      attempt=$((attempt+1))
    done
    
    log_error "⚠️ Failed to load LaunchDaemon after $max_attempts attempts"
    return 1
  }
  
  # IMPORTANT: Use 'EOT' instead of 'EOF' to allow variable replacement in the script template
  # Create the watchdog script with more reliable heredoc
  cat > "$watchdog_script" << 'EOT'
#!/bin/bash

# Variables will be replaced after this template is created
TRIGGER_FILE="__TRIGGER_FILE__"
MAX_WAIT=180  # Maximum wait time in seconds
SLEEP_INTERVAL=1
RUN_ID="__RUN_ID__"
CONSOLE_USER="__CONSOLE_USER__"
AGENT_LABEL="__AGENT_LABEL__"
AGENT_PATH="__AGENT_PATH__"
DAEMON_LABEL="__DAEMON_LABEL__"
DAEMON_PATH="__DAEMON_PATH__"
HELPER_SCRIPT="__HELPER_SCRIPT__"
WATCHDOG_SCRIPT="__WATCHDOG_SCRIPT__"
LOG_FILE="__LOG_FILE__"
INSTALLER_OS="__INSTALLER_OS__"
SKIP_OS_VERSION_CHECK="__SKIP_OS_VERSION_CHECK__"
WRAPPER_PATH="__WRAPPER_PATH__"
ABORT_DEFER_MINUTES=__ABORT_DEFER_MINUTES__
MAX_ABORTS=__MAX_ABORTS__
PLIST="__PLIST__"
SCRIPT_MODE="__SCRIPT_MODE__"
ABORT_FILE="__ABORT_FILE__"
PREVENT_ALL_REBOOTS="__PREVENT_ALL_REBOOTS__"

# Add all the parameters needed for erase-install
ERASE_INSTALL_PATH="__ERASE_INSTALL_PATH__"
REBOOT_DELAY="__REBOOT_DELAY__"
REINSTALL="__REINSTALL__"
NO_FS="__NO_FS__"
CHECK_POWER="__CHECK_POWER__"
POWER_WAIT_LIMIT="__POWER_WAIT_LIMIT__"
MIN_DRIVE_SPACE="__MIN_DRIVE_SPACE__"
CLEANUP_AFTER_USE="__CLEANUP_AFTER_USE__"
TEST_MODE="__TEST_MODE__"
DEBUG_MODE="__DEBUG_MODE__"

# Authentication notice variables
SHOW_AUTH_NOTICE="__SHOW_AUTH_NOTICE__"
AUTH_NOTICE_TITLE="__AUTH_NOTICE_TITLE__"
AUTH_NOTICE_TITLE_TEST_MODE="__AUTH_NOTICE_TITLE_TEST_MODE__"
AUTH_NOTICE_MESSAGE="__AUTH_NOTICE_MESSAGE__"
AUTH_NOTICE_BUTTON="__AUTH_NOTICE_BUTTON__"
AUTH_NOTICE_ICON="__AUTH_NOTICE_ICON__"
AUTH_NOTICE_HEIGHT=__AUTH_NOTICE_HEIGHT__
AUTH_NOTICE_WIDTH=__AUTH_NOTICE_WIDTH__
DIALOG_PATH="__DIALOG_PATH__"
DIALOG_POSITION="__DIALOG_POSITION__"

# Function to create trigger file mutex
init_trigger_mutex() {
# Create a flag to indicate watchdog is ready
WATCHDOG_READY_FLAG="/var/tmp/erase-install-watchdog-ready-${RUN_ID}"

# Wait a moment for proper initialization
sleep 1

# Create the ready flag
touch "${WATCHDOG_READY_FLAG}"
log_message "Watchdog initialization complete, ready for trigger file"

# Check if UI is already running
local ui_start_flag="/var/tmp/erase-install-ui-starting-${RUN_ID}"
if [ -f "$ui_start_flag" ]; then
log_message "Detected UI already started, extending wait time"
# Extend wait time if UI is already running
MAX_WAIT=300
fi

# Clean up flag on exit
trap 'rm -f "${WATCHDOG_READY_FLAG}" 2>/dev/null' EXIT
}

# Function to log with timestamp
log_message() {
# First parameter is the message
local message="$1"
# Second optional parameter is log level (INFO, WARN, ERROR)
local level="${2:-INFO}"

# Create log entry with timestamp
local log_entry="[$level] [$(date '+%Y-%m-%d %H:%M:%S')] $message"

# Ensure log file directory exists
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

# Write to log file with error handling
echo "$log_entry" >> "$LOG_FILE" 2>/dev/null || true

# Also log to system.log for easier debugging with error handling
if [ -n "$message" ]; then
logger -t "erase-install-watchdog-${RUN_ID}" "$message" 2>/dev/null || true
else
logger -t "erase-install-watchdog-${RUN_ID}" "empty-message" 2>/dev/null || true
fi

# If this is an ERROR level message, also send to stderr
if [ "$level" = "ERROR" ]; then
echo "$log_entry" >&2
fi
}

# Helper functions for different log levels
log_info() {
log_message "$1" "INFO"
}

log_warn() {
log_message "$1" "WARN"
}

log_error() {
log_message "$1" "ERROR"
}

log_debug() {
if [ "$DEBUG_MODE" = "true" ]; then
log_message "$1" "DEBUG"
fi
}

# Initialize watchdog as early as possible
init_trigger_mutex

log_message "Starting watchdog with DAEMON_LABEL=${DAEMON_LABEL}"
log_message "Script mode: ${SCRIPT_MODE}"
log_message "Run ID: ${RUN_ID}"
log_message "Trigger file will be: ${TRIGGER_FILE}"

# Function to check if OS is already at or above the target version
check_os_already_updated() {
# Get current OS version
local current_os=$(sw_vers -productVersion)
log_message "Current OS version: $current_os"

# Get the target OS version from the plist
local target_os=$(defaults read "${PLIST}" targetOSVersion 2>/dev/null)
if [[ -z "$target_os" ]]; then
# If we don't have it stored, use INSTALLER_OS
target_os="${INSTALLER_OS}"
log_message "No stored target version found. Using INSTALLER_OS: $target_os"
else
log_message "Using stored target OS version: $target_os"
fi

# Extract major versions
local current_major=$(echo "$current_os" | cut -d. -f1)
local target_major=$(echo "$target_os" | cut -d. -f1)

# Compare major versions
if [[ $current_major -gt $target_major ]]; then
log_message "Current OS major version ($current_major) is greater than target major version ($target_major)"
return 0  # No update needed
elif [[ $current_major -lt $target_major ]]; then
log_message "Current OS major version ($current_major) is less than target major version ($target_major)"
return 1  # Update needed
else
# Major versions are equal, compare minor versions
log_message "Major versions are equal. Checking minor versions..."

# Split versions by dots for comparison
IFS='.' read -ra CURRENT_VER <<< "$current_os"
IFS='.' read -ra TARGET_VER <<< "$target_os"

# Compare each component
for ((i=1; i<${#CURRENT_VER[@]} && i<${#TARGET_VER[@]}; i++)); do
if [[ ${CURRENT_VER[i]} -gt ${TARGET_VER[i]} ]]; then
log_message "Current version component ${CURRENT_VER[i]} is greater than target ${TARGET_VER[i]} at position $i"
return 0  # No update needed
elif [[ ${CURRENT_VER[i]} -lt ${TARGET_VER[i]} ]]; then
log_message "Current version component ${CURRENT_VER[i]} is less than target ${TARGET_VER[i]} at position $i"
return 1  # Update needed
fi
done

# If we get here, all compared components are equal
# If target has more components, check if they're significant
if [[ ${#TARGET_VER[@]} -gt ${#CURRENT_VER[@]} ]]; then
for ((i=${#CURRENT_VER[@]}; i<${#TARGET_VER[@]}; i++)); do
if [[ ${TARGET_VER[i]} -gt 0 ]]; then
  log_message "Target version has additional significant component ${TARGET_VER[i]}"
  return 1  # Update needed
fi
done
fi

# If we get here, versions are compatible
log_message "Current version $current_os is compatible with target version $target_os"
return 0  # No update needed
fi
}

# Function to check if OS was upgraded during deferral
check_if_os_upgraded_during_deferral() {
log_message "Checking if OS was upgraded during deferral period..."

# Get current OS version
local current_os=$(sw_vers -productVersion)
log_message "Current OS version: $current_os"

# Get initial OS version when deferral started
local initial_os=$(defaults read "${PLIST}" initialOSVersion 2>/dev/null || echo "")
if [[ -z "$initial_os" ]]; then
log_message "No initial OS version recorded. Using current OS version."
initial_os="$current_os"
fi
log_message "Initial OS version (when deferred): $initial_os"

# Get target OS version from plist
local target_os=$(defaults read "${PLIST}" targetOSVersion 2>/dev/null || echo "")
if [[ -z "$target_os" ]]; then
log_message "No target OS version recorded. Using INSTALLER_OS value."
target_os="${INSTALLER_OS}"
fi
log_message "Target OS version: $target_os"

# Extract version components
local current_major=$(echo "$current_os" | cut -d. -f1)
local initial_major=$(echo "$initial_os" | cut -d. -f1)
local target_major=$(echo "$target_os" | cut -d. -f1)

# First, check if OS is already fully up-to-date compared to target
log_message "Performing exact version comparison..."

# Split versions into components for detailed comparison
IFS='.' read -ra CURRENT_VER <<< "$current_os"
IFS='.' read -ra TARGET_VER <<< "$target_os"

# Flag to track if we need to update
local needs_update=false

# Check if major versions differ
if [[ ${CURRENT_VER[0]} -lt ${TARGET_VER[0]} ]]; then
log_message "Current major version (${CURRENT_VER[0]}) is less than target (${TARGET_VER[0]})"
needs_update=true
elif [[ ${CURRENT_VER[0]} -eq ${TARGET_VER[0]} ]]; then
# Major versions match, check minor/patch versions
log_message "Major versions match, checking minor versions..."

# Compare each component after the major version
for ((i=1; i<${#CURRENT_VER[@]} && i<${#TARGET_VER[@]}; i++)); do
if [[ ${CURRENT_VER[i]} -lt ${TARGET_VER[i]} ]]; then
log_message "Current version component ${CURRENT_VER[i]} is less than target ${TARGET_VER[i]} at position $i"
needs_update=true
break
elif [[ ${CURRENT_VER[i]} -gt ${TARGET_VER[i]} ]]; then
log_message "Current version component ${CURRENT_VER[i]} is greater than target ${TARGET_VER[i]} at position $i"
break
fi
# If equal, continue to next component
done

# If target has more components than current, check if they're significant
if [[ "$needs_update" == "false" && ${#TARGET_VER[@]} -gt ${#CURRENT_VER[@]} ]]; then
for ((i=${#CURRENT_VER[@]}; i<${#TARGET_VER[@]}; i++)); do
if [[ ${TARGET_VER[i]} -gt 0 ]]; then
  log_message "Target version has additional significant component ${TARGET_VER[i]}"
  needs_update=true
  break
fi
done
fi
fi

# If OS is already at or above target version, no update needed
if [[ "$needs_update" == "false" ]]; then
log_message "Current OS version ($current_os) is already at or above target version ($target_os)"
return 0  # No update needed
fi

# At this point, we know the current version isn't fully up-to-date
log_message "Current OS version ($current_os) is not fully up-to-date compared to target ($target_os)"

# Now check if a major upgrade occurred during deferral
if [[ "$current_major" -gt "$initial_major" ]]; then
log_message "Major OS upgrade detected during deferral (from $initial_os to $current_os)"

# Policy decision: Proceed with update even after major upgrade to ensure full update
log_message "Although user performed major upgrade, current version isn't at latest minor version"
log_message "Proceeding with update to ensure system is fully up-to-date"
return 1  # Proceed with update
else
# No major upgrade detected, update is needed
log_message "No major OS upgrade detected. Update is needed."
return 1  # Update needed
fi
}

# Function to safely clean up all components
# Function to safely clean up all components
cleanup_watchdog() {
  # Create a unique identifier for this cleanup run
  local cleanup_id="${RUN_ID}-$(date +%s)"
  local cleanup_mutex="/var/tmp/erase-install-cleanup-${cleanup_id}.lock"
  local cleanup_log="/var/log/erase-install-cleanup-${cleanup_id}.log"

  log_message "Starting coordinated cleanup with ID: ${cleanup_id}"
  log_message "Cleanup log will be at: ${cleanup_log}"

  # Check for explicit preservation flag first (most reliable method)
  local preserve_abort=false
  local preserve_flag="/var/tmp/erase-install-preserve-abort-${RUN_ID}"
  
  if [ -f "$preserve_flag" ]; then
    log_message "Found abort preservation flag - will preserve abort daemon during cleanup"
    preserve_abort=true
  fi

  # Check if an abort daemon exists for this run ID as backup method
  local abort_daemon_path="/Library/LaunchDaemons/com.macjediwizard.eraseinstall.abort.${RUN_ID}.plist"
  
  if [ -f "$abort_daemon_path" ]; then
    log_message "Abort daemon detected for run ID ${RUN_ID} - will preserve during cleanup"
    preserve_abort=true

    # Verify the daemon is loaded
    if sudo launchctl list 2>/dev/null | grep -q "com.macjediwizard.eraseinstall.abort.${RUN_ID}"; then
      log_message "✓ Abort daemon is active in launchctl"
    else
      log_message "! Abort daemon exists but is not loaded - attempting to load it"
      sudo launchctl load "$abort_daemon_path" 2>>"${cleanup_log}" || 
      sudo launchctl bootstrap system "$abort_daemon_path" 2>>"${cleanup_log}" || 
      sudo launchctl kickstart -k system/com.macjediwizard.eraseinstall.abort.${RUN_ID} 2>>"${cleanup_log}" || true
    fi
  fi

  # Check environment variable (tertiary method)
  if [[ "${ERASE_INSTALL_ABORT_DAEMON:-}" == "true" ]]; then
    log_message "ERASE_INSTALL_ABORT_DAEMON environment variable is set - will preserve abort daemons"
    preserve_abort=true
  fi

  # Export the preservation flag so background processes know about it
  if [ "$preserve_abort" = "true" ]; then
    export PRESERVE_ABORT_DAEMON="true"
    export ABORT_DAEMON_PATH="$abort_daemon_path"
    log_message "✓ Exported abort daemon preservation settings to environment"
  fi

# Create mutex directory to prevent multiple simultaneous cleanups
if ! mkdir "${cleanup_mutex}" 2>/dev/null; then
log_message "WARNING: Another cleanup process appears to be running (${cleanup_mutex} exists)"
log_message "Will proceed anyway with caution"
fi

# Perform initial cleanup in the current process
log_message "CLEANUP PHASE 1: Removing key components" | tee -a "${cleanup_log}"

# Get the UID of the console user - with error handling
local console_uid=""
if [ -n "$CONSOLE_USER" ]; then
console_uid=$(id -u "$CONSOLE_USER" 2>/dev/null) || true
if [ -z "$console_uid" ]; then
log_message "WARNING: Could not get UID for $CONSOLE_USER, using fallback detection" | tee -a "${cleanup_log}"
console_uid=$(who | grep console | awk '{print $1}' | xargs id -u 2>/dev/null) || true
fi
log_message "Console user UID: $console_uid (for $CONSOLE_USER)" | tee -a "${cleanup_log}"
else
log_message "WARNING: No console user specified, cleanup may be incomplete" | tee -a "${cleanup_log}"
fi

# CRITICAL: Stop any running erase-install processes first
if pgrep -f "erase-install.sh" >/dev/null; then
log_message "Stopping running erase-install processes" | tee -a "${cleanup_log}"
pkill -TERM -f "erase-install.sh" 2>/dev/null || true
sleep 1
# Force kill if still running
# SECURITY FIX (Issue #29): Use safe process termination
kill_process_safely "erase-install.sh" 5 || true
fi

# Unload LaunchAgent if it exists and we have a console user
if [ -n "$AGENT_PATH" ] && [ -f "$AGENT_PATH" ] && [ -n "$console_uid" ]; then
log_message "Unloading UI LaunchAgent: $AGENT_LABEL" | tee -a "${cleanup_log}"
# Try multiple methods with proper error handling
launchctl asuser "$console_uid" sudo -u "$CONSOLE_USER" launchctl remove "$AGENT_LABEL" 2>>"${cleanup_log}" || true
launchctl asuser "$console_uid" sudo -u "$CONSOLE_USER" launchctl unload "$AGENT_PATH" 2>>"${cleanup_log}" || true
launchctl asuser "$console_uid" launchctl bootout gui/$console_uid/"$AGENT_LABEL" 2>>"${cleanup_log}" || true

# Remove the agent file with proper error handling
log_message "Removing LaunchAgent file: $AGENT_PATH" | tee -a "${cleanup_log}"
rm -f "$AGENT_PATH" 2>>"${cleanup_log}" || true
if [ -f "$AGENT_PATH" ]; then
log_message "WARNING: Failed to remove $AGENT_PATH, will retry with elevated privileges" | tee -a "${cleanup_log}"
sudo rm -f "$AGENT_PATH" 2>>"${cleanup_log}" || true
fi
else
log_message "LaunchAgent path not found or not specified, skipping" | tee -a "${cleanup_log}"
fi

# Remove helper script if it exists
if [ -n "$HELPER_SCRIPT" ] && [ -f "$HELPER_SCRIPT" ]; then
log_message "Removing helper script: $HELPER_SCRIPT" | tee -a "${cleanup_log}"
rm -f "$HELPER_SCRIPT" 2>>"${cleanup_log}" || true
fi

# CLEANUP PHASE 2: Handle startosinstall daemon
log_message "CLEANUP PHASE 2: Checking for startosinstall daemon" | tee -a "${cleanup_log}"

# Handle startosinstall daemon (MOST CRITICAL PART)
local startosinstall_plist="/Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist"
if [ -f "$startosinstall_plist" ]; then
log_message "CRITICAL: Found startosinstall daemon - removing immediately" | tee -a "${cleanup_log}"
# Try multiple methods with proper error handling
launchctl remove "com.github.grahampugh.erase-install.startosinstall" 2>>"${cleanup_log}" || true
launchctl bootout system/"com.github.grahampugh.erase-install.startosinstall" 2>>"${cleanup_log}" || true
launchctl unload "$startosinstall_plist" 2>>"${cleanup_log}" || true

# Remove the file with proper error handling
rm -f "$startosinstall_plist" 2>>"${cleanup_log}" || true
if [ -f "$startosinstall_plist" ]; then
log_message "WARNING: Failed to remove $startosinstall_plist, trying with elevated privileges" | tee -a "${cleanup_log}"
sudo rm -f "$startosinstall_plist" 2>>"${cleanup_log}" || true
fi

# Verify if it's still present after all attempts
if [ -f "$startosinstall_plist" ]; then
log_message "ERROR: Failed to remove startosinstall plist after multiple attempts" | tee -a "${cleanup_log}"
else
log_message "Successfully removed startosinstall plist" | tee -a "${cleanup_log}"
fi
else
log_message "No startosinstall daemon found - good" | tee -a "${cleanup_log}"
fi

# CLEANUP PHASE 3: Remove our own daemon if specified
if [ -n "$DAEMON_LABEL" ] && [ -n "$DAEMON_PATH" ]; then
log_message "CLEANUP PHASE 3: Unloading our LaunchDaemon: $DAEMON_LABEL" | tee -a "${cleanup_log}"
launchctl remove "$DAEMON_LABEL" 2>>"${cleanup_log}" || true
launchctl bootout system/"$DAEMON_LABEL" 2>>"${cleanup_log}" || true
launchctl unload "$DAEMON_PATH" 2>>"${cleanup_log}" || true

# Remove daemon file
if [ -f "$DAEMON_PATH" ]; then
log_message "Removing daemon file: $DAEMON_PATH" | tee -a "${cleanup_log}"
rm -f "$DAEMON_PATH" 2>>"${cleanup_log}" || true
if [ -f "$DAEMON_PATH" ]; then
log_message "WARNING: Failed to remove $DAEMON_PATH, trying with elevated privileges" | tee -a "${cleanup_log}"
sudo rm -f "$DAEMON_PATH" 2>>"${cleanup_log}" || true
fi
fi
else
log_message "No daemon label/path specified, skipping daemon unload" | tee -a "${cleanup_log}"
fi

# CLEANUP PHASE 4: Background process for additional cleanup
log_message "CLEANUP PHASE 4: Starting background cleanup process" | tee -a "${cleanup_log}"

(
  # Set up error handling for the background process
  set -e
  
  # Add a delay to ensure other processes have completed
  sleep 3
  
  echo "$(date '+%Y-%m-%d %H:%M:%S') Background cleanup process started" >> "${cleanup_log}"
  
  # Capture the values we need before starting subshell
  local preserve_abort="$preserve_abort"
  local abort_daemon_path="$abort_daemon_path"
  
  # Import environment variables if available
  if [[ "${PRESERVE_ABORT_DAEMON:-}" == "true" ]]; then
    preserve_abort=true
    echo "$(date '+%Y-%m-%d %H:%M:%S') Using environment-provided abort daemon preservation settings" >> "${cleanup_log}"
  fi
  
  # Double-check for preservation flag (in case environment wasn't inherited)
  if [ -f "/var/tmp/erase-install-preserve-abort-${RUN_ID}" ]; then
    preserve_abort=true
    echo "$(date '+%Y-%m-%d %H:%M:%S') Found preservation flag file - will preserve abort daemon" >> "${cleanup_log}"
  fi
  
  # Capture the values we need before starting subshell
  preserve_abort="$preserve_abort"
  abort_daemon_path="$abort_daemon_path"
  watchdog_script="$WATCHDOG_SCRIPT"
  
  # Remove any temporary files
  echo "$(date '+%Y-%m-%d %H:%M:%S') Removing temporary files" >> "${cleanup_log}"
  rm -f /var/tmp/dialog.* 2>/dev/null || true
  rm -f /var/tmp/erase-install-ui-* 2>/dev/null || true
  rm -f /var/tmp/erase-install-watchdog-* 2>/dev/null || true
  
  # FINAL SWEEP: Check for any remaining erase-install related daemons
  echo "$(date '+%Y-%m-%d %H:%M:%S') Final sweep for any remaining daemons" >> "${cleanup_log}"
  for daemon_path in /Library/LaunchDaemons/com.macjediwizard.eraseinstall.*.plist /Library/LaunchDaemons/com.github.grahampugh.erase-install.*.plist; do
    # Check if glob expanded properly (to avoid processing literal glob pattern)
    if [ -e "$daemon_path" ]; then
      # Skip abort daemon if we need to preserve it
      if [ "$preserve_abort" = "true" ] && [[ "$daemon_path" == *".abort."* ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') Preserving abort daemon: $daemon_path" >> "${cleanup_log}"
        continue
      fi
      
      echo "$(date '+%Y-%m-%d %H:%M:%S') Found lingering daemon: $daemon_path" >> "${cleanup_log}"
      daemon_label=$(basename "$daemon_path" .plist)
      sudo launchctl remove "$daemon_label" 2>/dev/null || true
      sudo rm -f "$daemon_path" 2>/dev/null || true
    fi
  done
  
  # Clean up any watchdog scripts in the Management directory
  for script in /Library/Management/erase-install/erase-install-watchdog-*.sh; do
    if [ -e "$script" ] && [ "$script" != "$watchdog_script" ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') Removing lingering watchdog script: $script" >> "${cleanup_log}"
      rm -f "$script" 2>/dev/null || true
    fi
  done
  
  # Remove self (watchdog script) at the very end, but only if not running from abort daemon
  if [ -n "$watchdog_script" ] && [ -f "$watchdog_script" ] && [ "$preserve_abort" != "true" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') Cleaning up watchdog script: $watchdog_script" >> "${cleanup_log}"
    mv "$watchdog_script" "${watchdog_script}.removed" 2>/dev/null
    rm -f "${watchdog_script}.removed" 2>/dev/null || true
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') Preserving watchdog script for abort daemon" >> "${cleanup_log}"
  fi
  
  # Remove mutex to signal completion
  rm -rf "${cleanup_mutex}" 2>/dev/null || true
  
  echo "$(date '+%Y-%m-%d %H:%M:%S') Background cleanup process completed successfully" >> "${cleanup_log}"
) &

# Make sure not to wait for the background process
disown $! 2>/dev/null || true

log_message "Cleanup process initiated successfully, background process will continue"

# Leave mutex in place for the background process to remove
return 0
}

# Function to create the abort daemon
create_abort_daemon() {
  # Create a LaunchDaemon for the aborted installation
  local abort_daemon_label="com.macjediwizard.eraseinstall.abort.${RUN_ID}"
  local abort_daemon_path="/Library/LaunchDaemons/${abort_daemon_label}.plist"
  
  log_message "Creating abort LaunchDaemon to run at $defer_hour:$defer_min"
  
  # Create an explicit preservation flag FIRST - very important for reliable recovery
  touch "/var/tmp/erase-install-preserve-abort-${RUN_ID}" 2>/dev/null
  log_message "Created abort preservation flag at: /var/tmp/erase-install-preserve-abort-${RUN_ID}"
  
  # Write to a temporary location first that we know we have permissions for
  local tmp_daemon_path="/tmp/abort_daemon_${RUN_ID}.plist"
  
  # Create LaunchDaemon plist with updated RunAtLoad set to true for reliability
  cat > "$tmp_daemon_path" << ABORTDAEMON
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${abort_daemon_label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${WRAPPER_PATH}</string>
        <string>--no-reboot</string>
        <string>--from-abort-daemon</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>${defer_hour}</integer>
        <key>Minute</key>
        <integer>${defer_min}</integer>
$([ -n "${defer_day}" ] && [ "${defer_day}" -gt 0 ] && printf "        <key>Day</key>\n        <integer>%d</integer>\n" "${defer_day}")
$([ -n "${defer_month}" ] && [ "${defer_month}" -gt 0 ] && printf "        <key>Month</key>\n        <integer>%d</integer>\n" "${defer_month}")
    </dict>
    <key>RunAtLoad</key>
    <false/>
    <key>LaunchOnlyOnce</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/erase-install-wrapper-abort-reschedule.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/erase-install-wrapper-abort-reschedule.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>ERASE_INSTALL_ABORT_DAEMON</key>
        <string>true</string>
    </dict>
</dict>
</plist>
ABORTDAEMON
  
  # Validate the temp daemon plist  
  if ! plutil -lint "$tmp_daemon_path" > /dev/null 2>&1; then
    log_message "ERROR: Created abort LaunchDaemon failed validation check"
    plutil -lint "$tmp_daemon_path" | log_message
    rm -f "$tmp_daemon_path"
    return 1
  fi
  
  # Copy the file to the final location with proper permissions
  # SECURITY FIX (Issue #26): Use secure atomic installation
  if ! install_daemon_secure "$tmp_daemon_path" "$abort_daemon_path"; then
    log_error "Failed to install abort daemon securely"
    rm -f "$tmp_daemon_path"
    return 1
  fi
  rm -f "$tmp_daemon_path"
  
  # Clean up temp file
  rm -f "$tmp_daemon_path"
  
  # Verify the daemon file exists
  if [ ! -f "$abort_daemon_path" ]; then
    log_message "ERROR: Failed to create abort daemon at: $abort_daemon_path"
    return 1
  fi
  
  log_message "Successfully created abort LaunchDaemon at: $abort_daemon_path"
  return 0
}

save_active_abort_daemon() {
  local daemon_label="$1"
  
  # First, verify the daemon exists
  if [ ! -f "/Library/LaunchDaemons/${daemon_label}.plist" ]; then
    log_warn "Cannot save non-existent abort daemon: ${daemon_label}"
    return 1
  fi
  
  # Save the active abort daemon in the plist
  log_info "Saving active abort daemon: $daemon_label"
  defaults write "${PLIST}" activeAbortDaemon -string "${daemon_label}"
  
  # Save the current run ID separately to help with tracking
  local run_id="${daemon_label##*.}"
  if [ -n "$run_id" ]; then
    log_info "Saving abort run ID: $run_id"
    defaults write "${PLIST}" abortRunID -string "$run_id"
  fi
  
  return 0
}

# Add these after the cleanup_watchdog function
verify_abort_schedule() {
  local abort_daemon_label="$1"
  local abort_daemon_path="/Library/LaunchDaemons/${abort_daemon_label}.plist"
  local success=true
  
  log_message "Performing comprehensive verification of abort schedule daemon"
  
  # 1. Check if daemon file exists
  if [ ! -f "$abort_daemon_path" ]; then
    log_message "❌ Abort daemon file does not exist: $abort_daemon_path"
    success=false
  else
    log_message "✅ Abort daemon file exists"
    
    # 2. Verify file permissions - use octal mode for comparison
    local file_perms=$(sudo stat -f '%OLp' "$abort_daemon_path" 2>/dev/null | grep -o '[0-7]\{3\}$')
    if [ "$file_perms" != "644" ]; then
      log_message "❌ Abort daemon has incorrect permissions: $file_perms (should be 644)"
      sudo chmod 644 "$abort_daemon_path" 2>/dev/null
      log_message "Attempted to fix permissions"
    else
      log_message "✅ Abort daemon has correct permissions"
    fi
    
    # 3. Verify file ownership
    local file_owner=$(sudo stat -f '%Su:%Sg' "$abort_daemon_path" 2>/dev/null)
    if [ "$file_owner" != "root:wheel" ]; then
      log_message "❌ Abort daemon has incorrect ownership: $file_owner (should be root:wheel)"
      sudo chown root:wheel "$abort_daemon_path" 2>/dev/null
      log_message "Attempted to fix ownership"
    else
      log_message "✅ Abort daemon has correct ownership"
    fi
    
    # 4. Check plist validity
    if ! plutil -lint "$abort_daemon_path" > /dev/null 2>&1; then
      log_message "❌ Abort daemon plist is invalid"
      success=false
    else
      log_message "✅ Abort daemon plist is valid"
    fi
  fi
  
  # 5. Check if daemon is loaded in launchctl
  if launchctl list | grep -q "$abort_daemon_label"; then
    log_message "✅ Abort daemon is loaded in launchctl"
  else
    log_message "❌ Abort daemon is not loaded in launchctl"
    success=false
  fi
  
  # 6. Check if abort environment variable is set
  if [[ "$(launchctl print system/"$abort_daemon_label" 2>/dev/null | grep ERASE_INSTALL_ABORT_DAEMON)" == *"true"* ]]; then
    log_message "✅ Abort daemon has correct environment variable set"
  else
    log_message "⚠️ Could not verify abort environment variable (expected in newer macOS only)"
  fi
  
  # Return overall result
  if [ "$success" = true ]; then
    log_message "✅ Abort schedule verification passed all checks"
    return 0
  else
    log_message "❌ Abort schedule verification failed one or more checks"
    return 1
  fi
}

# Enhanced function to load abort daemon with improved validation and testing
load_abort_daemon() {
  local daemon_path="$1"
  local daemon_label="$2"
  local max_attempts=5
  local attempt=1
  
  log_message "Attempting to load abort daemon: $daemon_label"
  
  # Verify the daemon file exists
  if [ ! -f "$daemon_path" ]; then
    log_message "ERROR: Abort daemon file not found: $daemon_path"
    return 1
  fi
  
  # Verify plist has RunAtLoad set to true for reliability
  if ! sudo plutil -extract RunAtLoad xml1 -o - "$daemon_path" 2>/dev/null | grep -q "<true/>"; then
    log_message "WARNING: RunAtLoad not set to true in plist, fixing..."
    # Create a temporary file with corrected setting
    local tmp_path="/tmp/fixed_${daemon_label}.plist"
    sudo cp "$daemon_path" "$tmp_path"
    sudo plutil -replace RunAtLoad -bool true "$tmp_path"
    if sudo plutil -lint "$tmp_path" >/dev/null 2>&1; then
      # SECURITY FIX (Issue #26): Use secure atomic installation
      if ! install_daemon_secure "$tmp_path" "$daemon_path"; then
        log_error "Failed to install daemon securely"
        rm -f "$tmp_path"
        return 1
      fi
      rm -f "$tmp_path"
      log_message "Fixed RunAtLoad setting in daemon plist"
    fi
    rm -f "$tmp_path" 2>/dev/null
  else
    log_message "✅ RunAtLoad properly set to true in daemon plist"
  fi
  
  # Try to load the daemon with multiple attempts
  while [ $attempt -le $max_attempts ]; do
    log_message "Loading attempt $attempt/$max_attempts..."
    
    # Method 1: Standard load with sudo using force flag (-w)
    if sudo launchctl load -w "$daemon_path" 2>/dev/null; then
      sleep 1
      if sudo launchctl list | grep -q "$daemon_label"; then
        log_message "✅ Successfully loaded abort daemon with sudo launchctl load"
        
        # Create a backup copy of the daemon for additional reliability
        sudo cp "$daemon_path" "${daemon_path}.bak" 2>/dev/null
        log_message "Created backup copy of abort daemon"
        
        # Verify permissions one more time after successful load
        sudo chmod 644 "$daemon_path" 2>/dev/null
        sudo chown root:wheel "$daemon_path" 2>/dev/null
        
        # Validate daemon in launchctl database for extra reliability
        local validation_output
        validation_output=$(sudo launchctl print system/"$daemon_label" 2>&1)
        if [[ "$validation_output" == *"state = running"* ]]; then
          log_message "✅ Daemon validated and appears to be in running state"
        elif [[ "$validation_output" == *"path ="* ]]; then
          log_message "✅ Daemon validated in launchctl database"
        else
          log_message "⚠️ Daemon loaded but validation shows unusual state"
          log_message "Attempting kickstart to ensure proper initialization..."
          sudo launchctl kickstart -k system/"$daemon_label" 2>/dev/null
        fi
        
        # Create debugging info for future troubleshooting if needed
        cat > "/var/tmp/abort-daemon-debug-${RUN_ID}.log" << EOF
Daemon loaded successfully at: $(date +'%Y-%m-%d %H:%M:%S')
Path: $daemon_path
Label: $daemon_label
Permissions: $(ls -la "$daemon_path" 2>/dev/null)
Load method: sudo launchctl load -w
LaunchCtl status: 
$(sudo launchctl list | grep "$daemon_label" 2>/dev/null)
EOF
        
        return 0
      fi
    fi
    
    # Method 2: Bootstrap method with sudo
    log_message "Trying bootstrap method..."
    if sudo launchctl bootstrap system "$daemon_path" 2>/dev/null; then
      sleep 1
      if sudo launchctl list | grep -q "$daemon_label"; then
        log_message "✅ Successfully loaded abort daemon with bootstrap method"
        
        # Verify daemon is properly loaded and enabled
        sudo launchctl enable system/"$daemon_label" 2>/dev/null
        
        # Create debugging info for future troubleshooting if needed
        cat > "/var/tmp/abort-daemon-debug-${RUN_ID}.log" << EOF
Daemon loaded successfully at: $(date +'%Y-%m-%d %H:%M:%S')
Path: $daemon_path
Label: $daemon_label
Permissions: $(ls -la "$daemon_path" 2>/dev/null)
Load method: sudo launchctl bootstrap
LaunchCtl status: 
$(sudo launchctl list | grep "$daemon_label" 2>/dev/null)
EOF
        
        return 0
      fi
    fi
    
    # Method 3: Load and enable with multiple steps
    log_message "Trying multi-step load and enable method..."
    sudo launchctl load -w "$daemon_path" 2>/dev/null
    sudo launchctl enable system/"$daemon_label" 2>/dev/null
    sudo launchctl kickstart -k system/"$daemon_label" 2>/dev/null
    
    sleep 2
    if sudo launchctl list | grep -q "$daemon_label"; then
      log_message "✅ Successfully loaded abort daemon with multi-step method"
      
      # Create debugging info for future troubleshooting if needed
      cat > "/var/tmp/abort-daemon-debug-${RUN_ID}.log" << EOF
Daemon loaded successfully at: $(date +'%Y-%m-%d %H:%M:%S')
Path: $daemon_path
Label: $daemon_label
Permissions: $(ls -la "$daemon_path" 2>/dev/null)
Load method: multi-step (load, enable, kickstart)
LaunchCtl status: 
$(sudo launchctl list | grep "$daemon_label" 2>/dev/null)
EOF
      
      return 0
    fi
    
    # Check for potential permission/ownership issues
    if [ $attempt -eq 1 ]; then
      log_message "First attempt failed, checking permissions and ownership..."
      sudo chmod 644 "$daemon_path" 2>/dev/null
      sudo chown root:wheel "$daemon_path" 2>/dev/null
    fi
    
    # Short pause before next attempt
    log_message "Load attempt $attempt failed, retrying after pause..."
    sleep 3
    attempt=$((attempt+1))
  done
  
  # Last resort: If we still can't load it, try direct submission and enable logging
  log_message "⚠️ All standard methods failed. Attempting direct submission as last resort..."
  
  # Create very detailed log for troubleshooting
  log_message "Creating detailed diagnostics log for troubleshooting"
  cat > "/var/tmp/abort-daemon-debug-failures-${RUN_ID}.log" << EOF
ABORT DAEMON LOADING FAILURE DIAGNOSTICS
=======================================
Date/Time: $(date +'%Y-%m-%d %H:%M:%S')
Daemon Path: $daemon_path
Daemon Label: $daemon_label
Daemon exists: $([ -f "$daemon_path" ] && echo "YES" || echo "NO")

File Details:
$(ls -la "$daemon_path" 2>&1)

File Contents:
$(cat "$daemon_path" 2>&1)

Plist Validation:
$(plutil -lint "$daemon_path" 2>&1)

LaunchCtl List Output:
$(sudo launchctl list 2>&1 | grep -A 2 -B 2 "$daemon_label" 2>&1 || echo "Not found in launchctl list")

Loaded Daemons in /Library/LaunchDaemons:
$(ls -la /Library/LaunchDaemons/com.macjediwizard.eraseinstall.* 2>&1)

System Info:
macOS Version: $(sw_vers -productVersion)
Architecture: $(uname -m)
EOF
  
  # Try direct submit method as absolute last resort
  sudo launchctl submit -l "$daemon_label" -p "$WRAPPER_PATH" \
    -o "/var/log/erase-install-wrapper-abort-reschedule.log" \
    -e "/var/log/erase-install-wrapper-abort-reschedule.log" -- --from-abort-daemon --no-reboot
  
  sleep 2
  if sudo launchctl list | grep -q "$daemon_label"; then
    log_message "✅ Successfully loaded abort daemon with submission method"
    return 0
  fi
  
  # Create a more easily discoverable flag file
  log_message "⚠️ Failed to load abort daemon after exhausting all methods"
  log_message "Creating abort recovery flag for next script execution"
  
  # Save all critical info needed for recovery
  cat > "/var/tmp/erase-install-abort-recovery-${RUN_ID}.txt" << EOF
ABORT_TIME=$(date +'%Y-%m-%d %H:%M:%S')
DAEMON_LABEL=$daemon_label
DAEMON_PATH=$daemon_path
WRAPPER_PATH=$WRAPPER_PATH
RUN_ID=$RUN_ID
DEFER_HOUR=$defer_hour
DEFER_MIN=$defer_min
DEFER_DAY=$defer_day
DEFER_MONTH=$defer_month
EOF
  
  # Set permissions to ensure it's readable by everyone
  chmod 644 "/var/tmp/erase-install-abort-recovery-${RUN_ID}.txt" 2>/dev/null
  
  # Create explicit preservation flag regardless of load success
  touch "/var/tmp/erase-install-preserve-abort-${RUN_ID}" 2>/dev/null
  
  return 1
}

# Special handling for defer mode
if [ "$SCRIPT_MODE" = "defer" ]; then
log_info "Operating in defer mode - preparing to relaunch main script"
log_debug "WRAPPER_PATH: ${WRAPPER_PATH}"
log_debug "CONSOLE_USER: ${CONSOLE_USER}"
log_debug "EUID: $EUID"
log_debug "Current directory: $(pwd)"

# Verify the main script exists
if [ ! -f "${WRAPPER_PATH}" ]; then
log_error "Main script not found at ${WRAPPER_PATH}!"
# Try to locate it
potential_paths=(
"/Library/Management/erase-install/erase-install-defer-wrapper.sh"
"/usr/local/bin/erase-install-defer-wrapper.sh"
"/Users/Shared/erase-install-defer-wrapper.sh"
)
for path in "${potential_paths[@]}"; do
if [ -f "$path" ]; then
log_info "Found main script at $path"
WRAPPER_PATH="$path"
break
fi
done
else
log_info "Verified main script exists at ${WRAPPER_PATH}"
fi

sleep 3  # Brief pause

# Create a temporary LaunchDaemon to run the main script
RELAUNCH_DAEMON_LABEL="com.macjediwizard.eraseinstall.relaunch.${RUN_ID}"
RELAUNCH_DAEMON_PATH="/Library/LaunchDaemons/${RELAUNCH_DAEMON_LABEL}.plist"

# Update the activeRelaunchDaemon in the plist
defaults write "${PLIST}" activeRelaunchDaemon -string "${RELAUNCH_DAEMON_LABEL}"
log_info "Updated active relaunch daemon to: ${RELAUNCH_DAEMON_LABEL}"

log_info "Creating temporary LaunchDaemon to relaunch main script"

# Create the plist content
cat > "$RELAUNCH_DAEMON_PATH" << LAUNCHDAEMONEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>Label</key>
<string>${RELAUNCH_DAEMON_LABEL}</string>
<key>ProgramArguments</key>
<array>
<string>${WRAPPER_PATH}</string>
<string>--from-abort-daemon</string>
</array>
<key>RunAtLoad</key>
<true/>
<key>LaunchOnlyOnce</key>
<true/>
<key>StandardOutPath</key>
<string>/var/log/erase-install-wrapper-relaunch.log</string>
<key>StandardErrorPath</key>
<string>/var/log/erase-install-wrapper-relaunch.log</string>
<key>UserName</key>
<string>root</string>
<key>GroupName</key>
<string>wheel</string>
<key>EnvironmentVariables</key>
<dict>
<key>PATH</key>
<string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
<key>ERASE_INSTALL_ABORT_DAEMON</key>
<string>true</string>
</dict>
</dict>
</plist>
LAUNCHDAEMONEOF

# Set proper permissions
chmod 644 "$RELAUNCH_DAEMON_PATH"
chown root:wheel "$RELAUNCH_DAEMON_PATH"

# Load the LaunchDaemon
log_info "Loading relaunch LaunchDaemon"
launchctl load "$RELAUNCH_DAEMON_PATH"

# Wait for it to start
log_info "Waiting 5 seconds for main script to start"
sleep 5

# Check if main script is running
if pgrep -f "${WRAPPER_PATH}" >/dev/null; then
log_info "Main script is running after LaunchDaemon load"
else
log_warn "Main script may not have started properly, trying direct execution"

# Fallback: Try direct execution if LaunchDaemon didn't work
if [ $EUID -eq 0 ]; then
log_info "Executing main script directly as root"
"${WRAPPER_PATH}" > /var/log/erase-install-wrapper-relaunch-${RUN_ID}.log 2>&1 &
else
log_info "Executing main script directly as user"
sudo -u "$CONSOLE_USER" "${WRAPPER_PATH}" > /var/tmp/erase-install-wrapper-relaunch.log 2>&1 &
fi
fi

# Clean up and exit
log_info "Cleaning up after launching main script"
cleanup_watchdog
exit 0
elif [ "$SCRIPT_MODE" = "scheduled" ]; then
log_info "Operating in scheduled mode - waiting for trigger file"
# Continue with normal watchdog functionality for scheduled installations
fi

# Wait for trigger file or timeout
log_info "Waiting for trigger file: $TRIGGER_FILE (will wait up to $MAX_WAIT seconds)"

# Add more debugging info about the watchdog state
if [ "$SCRIPT_MODE" = "scheduled" ]; then
log_info "Running in SCHEDULED mode - will wait for user to confirm via dialog"
log_debug "Helper script path: $HELPER_SCRIPT"
if [ -f "$HELPER_SCRIPT" ]; then
log_debug "Helper script exists: Yes"
ls -la "$HELPER_SCRIPT" | log_debug
else
log_debug "Helper script exists: No"
fi

# Check for UI startup signal
UI_START_FLAG="/var/tmp/erase-install-ui-starting-${RUN_ID}"
if [ -f "$UI_START_FLAG" ]; then
log_info "Detected UI startup signal, UI helper is running"
else
log_warn "No UI startup signal detected, UI helper may not be running yet"
fi
fi

COUNTER=0
while [ ! -f "$TRIGGER_FILE" ] && [ $COUNTER -lt $MAX_WAIT ]; do
# Check for abort file on each iteration
if [ -f "$ABORT_FILE" ]; then
log_info "Abort file detected during wait loop - breaking out to process abort"
break
fi

# Periodically check and report status
if [ $((COUNTER % 30)) -eq 0 ] && [ $COUNTER -gt 0 ]; then
log_info "Still waiting for trigger file... ($COUNTER seconds elapsed)"

# Check for any trigger files in the directory
if [ "$DEBUG_MODE" = "true" ]; then
log_debug "Looking for any trigger files in /var/tmp"
ls -la /var/tmp/erase-install-* 2>/dev/null | log_debug
fi

# Check if UI has completed or is running
UI_COMPLETE_FLAG="/var/tmp/erase-install-ui-completed-${RUN_ID}"
if [ -f "$UI_COMPLETE_FLAG" ] && [ ! -f "$TRIGGER_FILE" ]; then
log_warn "UI completed but no trigger file was created - attempting to create one"
touch "$TRIGGER_FILE"
break
fi
fi
sleep $SLEEP_INTERVAL
COUNTER=$((COUNTER + SLEEP_INTERVAL))
done

# Enhanced abort file detection
if [ -f "$ABORT_FILE" ]; then
  log_message "🚨 ABORT DETECTED: Processing emergency abort request"
  log_message "Abort file: $ABORT_FILE"
  log_message "Run ID: $RUN_ID"
  
  # Remove abort file immediately
  rm -f "$ABORT_FILE"
  log_message "Removed abort signal file"
  
  # Check for test execution flag
  if [ -f "/var/tmp/erase-install-immediate-test-${RUN_ID}" ]; then
    log_message "Test mode detected - exiting"
    rm -f "/var/tmp/erase-install-immediate-test-${RUN_ID}"
    touch "/var/tmp/erase-install-abort-test-success-${RUN_ID}"
    exit 0
  fi
  
  # CHECK: Don't process abort if installation already completed successfully
  if [ -f "/var/tmp/erase-install-success-${RUN_ID}" ]; then
    log_message "Installation completed successfully - ignoring stale abort signal"
    rm -f "$ABORT_FILE" 2>/dev/null
    exit 0
  fi
  
  # Increment abort count with verification
  log_message "📊 INCREMENTING ABORT COUNT"
  abort_count=$(defaults read "$PLIST" abortCount 2>/dev/null || echo 0)
  log_message "Current abort count: $abort_count"
  abort_count=$((abort_count + 1))
  defaults write "$PLIST" abortCount -int "$abort_count"
  
  # Verify increment
  verify_count=$(defaults read "$PLIST" abortCount 2>/dev/null || echo "ERROR")
  log_message "New abort count: $verify_count/$MAX_ABORTS"
  
  # Calculate defer time
  log_message "⏰ CALCULATING RESCHEDULE TIME"
  current_hour=$(date +%H)
  current_min=$(date +%M)
  current_hour=$((10#$current_hour))
  current_min=$((10#$current_min))
  log_message "Current time: $current_hour:$current_min"
  
  # Add defer minutes
  current_min=$((current_min + ABORT_DEFER_MINUTES))
  
  # Handle minute rollover
  while [ $current_min -ge 60 ]; do
    current_min=$((current_min - 60))
    current_hour=$((current_hour + 1))
  done
  
  # Handle hour rollover
if [ $current_hour -ge 24 ]; then
  current_hour=$((current_hour - 24))
  defer_day=$(date -v+1d +%d)
  defer_month=$(date -v+1d +%m)
else
  defer_day=$(date +%d)
  defer_month=$(date +%m)
fi

# CRITICAL FIX: Ensure defer_day is never 0
defer_day=$((10#${defer_day}))  # Convert to base-10 integer
defer_month=$((10#${defer_month}))  # Convert to base-10 integer

# Validate day is in valid range
if [[ $defer_day -lt 1 || $defer_day -gt 31 ]]; then
  log_message "ERROR: Invalid defer_day calculated: $defer_day - using today's date"
  defer_day=$(date +%d)
  defer_day=$((10#${defer_day}))
fi

# Validate month is in valid range  
if [[ $defer_month -lt 1 || $defer_month -gt 12 ]]; then
  log_message "ERROR: Invalid defer_month calculated: $defer_month - using current month"
  defer_month=$(date +%m)
  defer_month=$((10#${defer_month}))
fi

log_message "✅ VALIDATED: defer_day=$defer_day, defer_month=$defer_month"
  
  # Format with leading zeros
  defer_hour=$(printf "%02d" $((10#$current_hour)))
  defer_min=$(printf "%02d" $current_min)
  
  log_message "🎯 SCHEDULING FOR: $defer_hour:$defer_min"
  
  # Create abort daemon
  log_message "🛠️ CREATING ABORT DAEMON"
  if create_abort_daemon; then
    abort_daemon_label="com.macjediwizard.eraseinstall.abort.${RUN_ID}"
    abort_daemon_path="/Library/LaunchDaemons/${abort_daemon_label}.plist"
    
    log_message "Loading abort daemon: $abort_daemon_label"
    
    # Load daemon with verification
    if sudo launchctl load "$abort_daemon_path" 2>/dev/null; then
      log_message "✅ Standard load succeeded"
    else
      log_message "⚠️ Standard load failed, trying alternatives"
      sudo launchctl bootstrap system "$abort_daemon_path" 2>/dev/null || 
      sudo launchctl kickstart system/"$abort_daemon_label" 2>/dev/null
    fi
    
    # Verify daemon is loaded
    sleep 2
    if launchctl list | grep -q "$abort_daemon_label"; then
      log_message "✅ SUCCESS: Abort daemon loaded for $defer_hour:$defer_min"

      # Save this as the active abort daemon in the plist
      log_message "Saving active abort daemon to plist: $abort_daemon_label"
      
      # Try multiple methods to save the abort daemon info
      if defaults write "$PLIST" activeAbortDaemon -string "$abort_daemon_label" 2>/dev/null; then
        log_message "Successfully wrote to plist with defaults"
      elif sudo defaults write "$PLIST" activeAbortDaemon -string "$abort_daemon_label" 2>/dev/null; then
        log_message "Successfully wrote to plist with sudo defaults"
      else
        log_message "Failed to write to plist, using fallback file method"
        # Fallback: create a simple text file that's easier to write
        echo "$abort_daemon_label" > "/var/tmp/active-abort-daemon-${RUN_ID}.txt" 2>/dev/null
        chmod 644 "/var/tmp/active-abort-daemon-${RUN_ID}.txt" 2>/dev/null
      fi
      
      # Also save the run ID for easier tracking
      defaults write "$PLIST" abortRunID -string "$RUN_ID" 2>/dev/null || 
      sudo defaults write "$PLIST" abortRunID -string "$RUN_ID" 2>/dev/null ||
      echo "$RUN_ID" > "/var/tmp/active-abort-runid-${RUN_ID}.txt" 2>/dev/null
      
      # Also save the run ID for easier tracking
      defaults write "$PLIST" abortRunID -string "$RUN_ID" 2>/dev/null || {
        log_message "Failed to save abort run ID to plist"  
      }
      
      # Verify the save worked
      saved_daemon=$(defaults read "$PLIST" activeAbortDaemon 2>/dev/null || echo "")
      if [[ "$saved_daemon" == "$abort_daemon_label" ]]; then
        log_message "✅ Successfully saved active abort daemon: $saved_daemon"
      else
        log_message "❌ Failed to verify saved abort daemon (expected: $abort_daemon_label, got: $saved_daemon)"
      fi
      
      osascript -e "display notification \"Installation rescheduled for $defer_hour:$defer_min\" with title \"macOS Upgrade Aborted\"" 2>/dev/null || true
    else
      log_message "❌ CRITICAL: Abort daemon not found in launchctl"
      launchctl list | grep "eraseinstall" | head -5 | log_message
    fi
    
  else
    log_message "❌ CRITICAL: create_abort_daemon function failed"
  fi
  
  log_message "🏁 ABORT PROCESSING COMPLETE"
  cleanup_watchdog
  exit 0
fi

# Verify if the trigger file was created
if [ -f "$TRIGGER_FILE" ]; then
log_info "✅ Trigger file found at: $TRIGGER_FILE"
# Get file info for debugging
ls -la "$TRIGGER_FILE" >> "$LOG_FILE" 2>&1
else
log_warn "❌ Trigger file not found after waiting $COUNTER seconds"
# Check the directory
log_info "Looking for any files in trigger directory..."
ls -la "$(dirname "$TRIGGER_FILE")" | grep "erase-install" >> "$LOG_FILE" 2>&1
fi

# If trigger file exists, first check OS version, then run erase-install if needed
if [ -f "$TRIGGER_FILE" ]; then
# Remove trigger file
rm -f "$TRIGGER_FILE"
log_message "Trigger file found, checking OS version before starting installation"

# Check if OS was upgraded during deferral
if [[ "$SKIP_OS_VERSION_CHECK" == "true" ]]; then
log_message "===== DEFERRAL OS CHECK TEST MODE ====="
log_message "Test modes active: TEST_MODE=${TEST_MODE}, SKIP_OS_VERSION_CHECK=${SKIP_OS_VERSION_CHECK}"

# Get current OS version
local current_os=$(sw_vers -productVersion)
log_message "Current OS version: $current_os"

# Get initial and target OS versions
local initial_os=$(defaults read "${PLIST}" initialOSVersion 2>/dev/null || echo "$current_os")
local target_os=$(defaults read "${PLIST}" targetOSVersion 2>/dev/null || echo "${INSTALLER_OS}")
log_message "Initial OS version (when deferred): $initial_os"
log_message "Target OS version: $target_os"

# Run the deferral check
log_message "----- DEFERRAL VERSION CHECK TEST -----"
if check_if_os_upgraded_during_deferral; then
log_message "TEST RESULT: OS has been upgraded during deferral period or is already at target."
log_message "In normal mode, a scheduled installation would exit here."
log_message "Since SKIP_OS_VERSION_CHECK=${SKIP_OS_VERSION_CHECK}, installation will continue anyway."
else
log_message "TEST RESULT: OS has NOT been upgraded during deferral and needs update."
fi

log_message "===== DEFERRAL OS CHECK TEST COMPLETE ====="
# Continue regardless of check result in test mode
elif check_if_os_upgraded_during_deferral; then
log_message "OS already updated to meet target version. No need to install. Exiting."
# Display a notification to the user
osascript -e 'display notification "Your macOS is already up to date. No installation required." with title "macOS Upgrade"'
# Clean up and exit
cleanup_watchdog
exit 0
fi

# OS needs update, proceed with installation
log_message "OS needs to be updated. Preparing erase-install command..."

# Show pre-authentication notice BEFORE starting erase-install
if [[ "${SHOW_AUTH_NOTICE}" == "true" ]]; then
log_message "Displaying pre-authentication notice"

# Check if dialog exists
if [ ! -x "${DIALOG_PATH}" ]; then
log_warn "Dialog not found at ${DIALOG_PATH}, checking alternative locations"
for dialog_alt in "/usr/local/bin/dialog" "/Library/Management/erase-install/Dialog.app/Contents/MacOS/Dialog"; do
if [ -x "$dialog_alt" ]; then
  log_info "Found dialog at $dialog_alt"
  DIALOG_PATH="$dialog_alt"
  break
fi
done
fi

# For test mode, use a modified title
display_title="${AUTH_NOTICE_TITLE}"
[[ "$TEST_MODE" = true ]] && display_title="${AUTH_NOTICE_TITLE_TEST_MODE}"

# Display the dialog
log_info "Executing dialog command for authentication notice"
"${DIALOG_PATH}" --title "${display_title}" \
--message "${AUTH_NOTICE_MESSAGE}" \
--button1text "${AUTH_NOTICE_BUTTON}" \
--icon "${AUTH_NOTICE_ICON}" \
--height ${AUTH_NOTICE_HEIGHT} \
--width ${AUTH_NOTICE_WIDTH} \
--moveable \
--position "${DIALOG_POSITION}"

dialog_result=$?
log_info "Authentication notice dialog returned status $dialog_result"

# Small pause to let user prepare
sleep 0.5
log_message "Pre-authentication notice completed, proceeding with installation"
fi

# Build command arguments properly using array (SECURITY FIX: prevents command injection)
declare -a cmd_args=("$ERASE_INSTALL_PATH")

# Add reinstall parameter
if [[ "$REINSTALL" == "true" ]]; then
log_message "Mode: Reinstall (not erase-install)"
cmd_args+=(--reinstall)
fi

# Add reboot delay if specified
if [ "$REBOOT_DELAY" -gt 0 ]; then
log_message "Using reboot delay: $REBOOT_DELAY seconds"
cmd_args+=(--rebootdelay "$REBOOT_DELAY")
fi

# Add no filesystem option if enabled
if [ "$NO_FS" = true ]; then
log_message "File system check disabled (--no-fs)"
cmd_args+=(--no-fs)
fi

# Add power check and wait limit if enabled
if [ "$CHECK_POWER" = true ]; then
log_message "Power check enabled: erase-install will verify power connection"
cmd_args+=(--check-power)

if [ "$POWER_WAIT_LIMIT" -gt 0 ]; then
log_message "Power wait limit set to $POWER_WAIT_LIMIT seconds"
cmd_args+=(--power-wait-limit "$POWER_WAIT_LIMIT")
else
log_message "Using default power wait limit (60 seconds)"
fi
else
log_message "Power check disabled: installation will proceed regardless of power status"
fi

# Add minimum drive space
log_message "Minimum drive space: $MIN_DRIVE_SPACE GB"
cmd_args+=(--min-drive-space "$MIN_DRIVE_SPACE")

# Add cleanup option if enabled
if [ "$CLEANUP_AFTER_USE" = true ]; then
log_message "Cleanup after use enabled"
cmd_args+=(--cleanup-after-use)
fi

# Add test mode if enabled
if [[ $TEST_MODE == true ]]; then
log_message "Test mode enabled"
cmd_args+=(--test-run)
fi

# Add verbose logging if debug mode enabled
if [ "$DEBUG_MODE" = true ]; then
log_message "Verbose logging enabled for erase-install"
cmd_args+=(--verbose)
fi

# Specify target OS version to use cached installer or download specific version
if [ -n "$INSTALLER_OS" ]; then
log_message "Specifying target OS version: $INSTALLER_OS (will use cached installer if available)"
cmd_args+=(--os "$INSTALLER_OS")
fi

# Add no-reboot override if enabled (highest safety priority)
# This should be last to override any other reboot settings
if [ "$PREVENT_ALL_REBOOTS" = "true" ]; then
log_message "SAFETY FEATURE: --no-reboot flag added to prevent any reboots"
cmd_args+=(--no-reboot)
elif [ "$TEST_MODE" = "true" ]; then
# Double safety check - always add no-reboot in test mode regardless of PREVENT_ALL_REBOOTS
log_message "SAFETY FEATURE: Adding --no-reboot flag because test mode is enabled"
cmd_args+=(--no-reboot)
fi

# Safety check to verify test mode flag is correctly passed
has_test_run=false
has_no_reboot=false
for arg in "${cmd_args[@]}"; do
    [[ "$arg" == "--test-run" ]] && has_test_run=true
    [[ "$arg" == "--no-reboot" ]] && has_no_reboot=true
done

if [ "$TEST_MODE" = "true" ] && [ "$has_test_run" = false ]; then
log_message "CRITICAL SAFETY CHECK FAILED: Test mode enabled but --test-run missing from command"
log_message "Command args: ${cmd_args[*]}"
log_message "Aborting installation to prevent unintended reboot"
exit 1
fi

# Execute the command with proper error handling
log_message "Command about to execute: ${cmd_args[*]}"
log_message "PREVENT_ALL_REBOOTS value: $PREVENT_ALL_REBOOTS"
log_message "TEST_MODE value: $TEST_MODE"

# Critical safety check - absolutely prevent reboots in test mode
if [ "$TEST_MODE" = "true" ] && [ "$has_no_reboot" = false ]; then
log_message "CRITICAL SAFETY FAILURE: Test mode enabled but --no-reboot missing from command"
log_message "Adding --no-reboot as emergency safety measure"
cmd_args+=(--no-reboot)
fi

# Final verification - log full command
log_message "FINAL COMMAND TO EXECUTE: ${cmd_args[*]}"

# Add PATH to ensure binary can be found
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# Execute the command using array expansion (SECURITY: prevents command injection)
"${cmd_args[@]}"

# Save exit code with enhanced error handling
RESULT=$?
log_message "erase-install completed with exit code: $RESULT"

# Reset counters if installation was successful
if [ $RESULT -eq 0 ]; then
  log_message "Installation completed successfully. Resetting deferral and abort counts."
  defaults write "${PLIST}" deferCount -int 0
  defaults write "${PLIST}" abortCount -int 0
  defaults write "${PLIST}" firstPromptDate -string "$(date -u +%s)"
  log_message "All counters reset successfully"
fi

# Enhanced error logging for power-related issues
if [ $RESULT -ne 0 ] && [ "$CHECK_POWER" = true ]; then
log_message "NOTE: Power checking was enabled with wait limit of $POWER_WAIT_LIMIT seconds"
log_message "If installation failed due to power issues, consider increasing the POWER_WAIT_LIMIT value"
fi

# Clean up
cleanup_watchdog

exit $RESULT
else
# If timeout occurred, log an error
log_message "Timeout waiting for trigger file"

# Clean up
cleanup_watchdog

exit 1
fi
EOT
  
  # Now perform variable replacements in a more reliable way
  # Use a different delimiter for messages that might contain special characters
  log_info "Performing variable substitutions in watchdog script..."
  
  # First, handle basic substitutions
  sed -i '' "s|__TRIGGER_FILE__|${trigger_file}|g" "$watchdog_script"
  sed -i '' "s|__RUN_ID__|${run_id}|g" "$watchdog_script"
  sed -i '' "s|__CONSOLE_USER__|${console_user}|g" "$watchdog_script"
  sed -i '' "s|__AGENT_LABEL__|${agent_label}|g" "$watchdog_script"
  sed -i '' "s|__AGENT_PATH__|${agent_path}|g" "$watchdog_script"
  sed -i '' "s|__DAEMON_LABEL__|${daemon_label}|g" "$watchdog_script"
  sed -i '' "s|__DAEMON_PATH__|${daemon_path}|g" "$watchdog_script"
  sed -i '' "s|__HELPER_SCRIPT__|${helper_script}|g" "$watchdog_script"
  sed -i '' "s|__WATCHDOG_SCRIPT__|${watchdog_script}|g" "$watchdog_script"
  sed -i '' "s|__LOG_FILE__|/var/log/erase-install-wrapper.watchdog.${run_id}.log|g" "$watchdog_script"
  sed -i '' "s|__INSTALLER_OS__|${INSTALLER_OS}|g" "$watchdog_script"
  sed -i '' "s|__SKIP_OS_VERSION_CHECK__|${SKIP_OS_VERSION_CHECK}|g" "$watchdog_script"
  sed -i '' "s|__WRAPPER_PATH__|${WRAPPER_PATH}|g" "$watchdog_script"
  sed -i '' "s|__ABORT_DEFER_MINUTES__|${ABORT_DEFER_MINUTES}|g" "$watchdog_script"
  sed -i '' "s|__MAX_ABORTS__|${MAX_ABORTS}|g" "$watchdog_script"
  sed -i '' "s|__PLIST__|${PLIST}|g" "$watchdog_script"
  sed -i '' "s|__SCRIPT_MODE__|${mode}|g" "$watchdog_script"
  sed -i '' "s|__ABORT_FILE__|/var/tmp/erase-install-abort-${run_id}|g" "$watchdog_script"
  
  # Set boolean variables correctly to avoid string comparison issues
  if [[ "${PREVENT_ALL_REBOOTS}" == "true" ]]; then
    sed -i '' "s|__PREVENT_ALL_REBOOTS__|true|g" "$watchdog_script"
  else
    sed -i '' "s|__PREVENT_ALL_REBOOTS__|false|g" "$watchdog_script"
  fi
  
  # erase-install parameters
  sed -i '' "s|__ERASE_INSTALL_PATH__|${SCRIPT_PATH}|g" "$watchdog_script"
  sed -i '' "s|__REBOOT_DELAY__|${REBOOT_DELAY}|g" "$watchdog_script"
  
  # Boolean parameters need special handling
  if [[ "${REINSTALL}" == "true" ]]; then
    sed -i '' "s|__REINSTALL__|true|g" "$watchdog_script"
  else
    sed -i '' "s|__REINSTALL__|false|g" "$watchdog_script"
  fi
  
  if [[ "${NO_FS}" == "true" ]]; then
    sed -i '' "s|__NO_FS__|true|g" "$watchdog_script"
  else
    sed -i '' "s|__NO_FS__|false|g" "$watchdog_script"
  fi
  
  if [[ "${CHECK_POWER}" == "true" ]]; then
    sed -i '' "s|__CHECK_POWER__|true|g" "$watchdog_script"
  else
    sed -i '' "s|__CHECK_POWER__|false|g" "$watchdog_script"
  fi
  
  if [[ "${CLEANUP_AFTER_USE}" == "true" ]]; then
    sed -i '' "s|__CLEANUP_AFTER_USE__|true|g" "$watchdog_script"
  else
    sed -i '' "s|__CLEANUP_AFTER_USE__|false|g" "$watchdog_script"
  fi
  
  if [[ "${TEST_MODE}" == "true" ]]; then
    sed -i '' "s|__TEST_MODE__|true|g" "$watchdog_script"
  else
    sed -i '' "s|__TEST_MODE__|false|g" "$watchdog_script"
  fi
  
  if [[ "${DEBUG_MODE}" == "true" ]]; then
    sed -i '' "s|__DEBUG_MODE__|true|g" "$watchdog_script"
  else
    sed -i '' "s|__DEBUG_MODE__|false|g" "$watchdog_script"
  fi
  
  sed -i '' "s|__POWER_WAIT_LIMIT__|${POWER_WAIT_LIMIT}|g" "$watchdog_script"
  sed -i '' "s|__MIN_DRIVE_SPACE__|${MIN_DRIVE_SPACE}|g" "$watchdog_script"
  
  # Auth notice parameters - using different delimiter for message to avoid escaping issues
  if [[ "${SHOW_AUTH_NOTICE}" == "true" ]]; then
    sed -i '' "s|__SHOW_AUTH_NOTICE__|true|g" "$watchdog_script"
  else
    sed -i '' "s|__SHOW_AUTH_NOTICE__|false|g" "$watchdog_script"
  fi
  
  # SECURITY FIX (Issue #22): Escape ALL sed substitutions to prevent command injection
  # Use escape_sed() for all user-controlled values that could contain special characters
  local escaped_auth_title=$(escape_sed "$AUTH_NOTICE_TITLE")
  local escaped_auth_title_test=$(escape_sed "$AUTH_NOTICE_TITLE_TEST_MODE")
  local escaped_auth_message=$(escape_sed "$AUTH_NOTICE_MESSAGE")
  local escaped_auth_button=$(escape_sed "$AUTH_NOTICE_BUTTON")
  local escaped_auth_icon=$(escape_sed "$AUTH_NOTICE_ICON")
  local escaped_dialog_bin=$(escape_sed "$DIALOG_BIN")
  local escaped_dialog_position=$(escape_sed "$DIALOG_POSITION")

  sed -i '' "s@__AUTH_NOTICE_TITLE__@${escaped_auth_title}@g" "$watchdog_script"
  sed -i '' "s@__AUTH_NOTICE_TITLE_TEST_MODE__@${escaped_auth_title_test}@g" "$watchdog_script"
  sed -i '' "s@__AUTH_NOTICE_MESSAGE__@${escaped_auth_message}@g" "$watchdog_script"
  sed -i '' "s@__AUTH_NOTICE_BUTTON__@${escaped_auth_button}@g" "$watchdog_script"
  sed -i '' "s@__AUTH_NOTICE_ICON__@${escaped_auth_icon}@g" "$watchdog_script"
  sed -i '' "s|__AUTH_NOTICE_HEIGHT__|${AUTH_NOTICE_HEIGHT}|g" "$watchdog_script"
  sed -i '' "s|__AUTH_NOTICE_WIDTH__|${AUTH_NOTICE_WIDTH}|g" "$watchdog_script"
  sed -i '' "s@__DIALOG_PATH__@${escaped_dialog_bin}@g" "$watchdog_script"
  sed -i '' "s@__DIALOG_POSITION__@${escaped_dialog_position}@g" "$watchdog_script"
  
  # Verify script substitutions in debug mode
  if [[ "${DEBUG_MODE}" == "true" ]]; then
    verify_script_substitutions "$watchdog_script"
  fi
  
  # Validate the watchdog script for syntax errors
  if ! validate_watchdog_script "$watchdog_script"; then
    log_error "Failed to create a valid watchdog script. Aborting schedule creation."
    return 1
  fi
  
  # Set proper permissions
  chmod +x "$watchdog_script"
  
  # 3. Create the LaunchDaemon for the watchdog
  daemon_label="${LAUNCHDAEMON_LABEL}.watchdog.${run_id}"
  daemon_path="/Library/LaunchDaemons/$daemon_label.plist"
  log_debug "daemon_label value is: ${daemon_label}"
  log_debug "daemon_path value is: ${daemon_path}"
  
  log_info "Creating LaunchDaemon watchdog at $(printf '%02d:%02d' "${hour_num}" "${minute_num}")${day:+ on day $day_num}${month:+ month $month_num}"
  
  # Create plist content for watchdog daemon (runs at the same time as the UI)
  local daemon_content="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
<key>Label</key>
<string>${daemon_label}</string>
<key>ProgramArguments</key>
<array>
<string>/bin/bash</string>
<string>${watchdog_script}</string>
</array>
<key>StartCalendarInterval</key>
<dict>
<key>Hour</key>
<integer>${hour_num}</integer>
<key>Minute</key>
<integer>${minute_num}</integer>
$([ -n "${day_num}" ] && printf "        <key>Day</key>\n        <integer>%d</integer>\n" "${day_num}")
$([ -n "${month_num}" ] && printf "        <key>Month</key>\n        <integer>%d</integer>\n" "${month_num}")
</dict>
<key>StandardOutPath</key>
<string>/var/log/erase-install-wrapper.log</string>
<key>StandardErrorPath</key>
<string>/var/log/erase-install-wrapper.log</string>
<key>RunAtLoad</key>      
<false/>
<key>LaunchOnlyOnce</key>
<true/>
<key>AbandonProcessGroup</key>
<true/>
<key>UserName</key>
<string>root</string>
<key>GroupName</key>
<string>wheel</string>
</dict>
</plist>"
  
  # Determine whether to show UI based on mode
  local show_ui=false
  if [ "$mode" != "defer" ]; then
    show_ui=true
  fi
  
  # Only create and load UI agent if not in defer mode
  if [ "$show_ui" = true ]; then
    log_info "Creating LaunchAgent for UI display at $(printf '%02d:%02d' "${hour_num}" "${minute_num}")${day:+ on day $day_num}${month:+ month $month_num}"
    # Create the agent plist
    printf "%s" "${agent_content}" | sudo -u "$console_user" tee "$agent_path" > /dev/null
    if [ $? -ne 0 ]; then
      log_error "Failed to create LaunchAgent file at $agent_path"
      return 1
    fi
    
    sudo -u "$console_user" chmod 644 "$agent_path"
    
    # Load the agent with improved error handling
    log_info "Loading LaunchAgent for UI..."
    if ! launchctl asuser "$(id -u "$console_user")" sudo -u "$console_user" launchctl bootstrap gui/"$(id -u "$console_user")" "$agent_path" 2>/dev/null; then
      log_warn "Failed to load agent with bootstrap method, trying legacy load method..."
      if ! launchctl asuser "$(id -u "$console_user")" sudo -u "$console_user" launchctl load "$agent_path"; then
        log_error "Failed to load LaunchAgent. The schedule may not work properly."
      else
        log_info "Successfully loaded LaunchAgent with legacy method"
      fi
    else
      log_info "Successfully loaded LaunchAgent"
    fi
  else
    log_info "Defer mode - skipping UI agent creation"
  fi
  
  # Write the daemon plist
  printf "%s" "${daemon_content}" | sudo tee "$daemon_path" > /dev/null
  if [ $? -ne 0 ]; then
    log_error "Failed to create LaunchDaemon file at $daemon_path"
    return 1
  fi
  
  # Log the full daemon path for debugging
  log_info "LaunchDaemon created at: $daemon_path"
  
  # Verify the daemon file exists
  if [ ! -f "$daemon_path" ]; then
    log_error "LaunchDaemon file does not exist after creation: $daemon_path"
    # Check permissions and try again with sudo
    log_info "Checking permissions and retrying..."
    ls -la "$(dirname "$daemon_path")" | head -5 | log_debug
    sudo printf "%s" "${daemon_content}" | sudo tee "$daemon_path" > /dev/null
    
    # Check again
    if [ ! -f "$daemon_path" ]; then
      log_error "LaunchDaemon file still does not exist after sudo attempt: $daemon_path"
      return 1
    else
      log_info "Successfully created LaunchDaemon file with sudo"
    fi
  fi
  
  # Ensure proper permissions
  # Note: Permissions already set atomically during file write or via install_daemon_secure()
  
  # Load and verify the daemon using our helper function
  if ! load_and_verify_daemon "$daemon_path" "$daemon_label"; then
    log_warn "Failed to load daemon properly, schedule may not work as expected"
  fi
  
  # Add debug info if debug mode enabled
  if [[ "${DEBUG_MODE}" = true ]]; then
    log_debug "Scheduled components:"
    log_debug "UI Agent: $agent_path"
    log_debug "Watchdog Daemon: $daemon_path"
    log_debug "Helper Script: $helper_script"
    log_debug "Watchdog Script: $watchdog_script"
    log_debug "Trigger File: $trigger_file"
  fi
  
  log_info "Successfully created and loaded launch items for schedule: $(printf '%02d:%02d' "${hour_num}" "${minute_num}")${day:+ on day $day_num}${month:+ month $month_num}"
  
  # Set the global variable for verification function to use
  log_debug "Exporting run_id: ${run_id}"
  
  # Log script mode for debugging
  if [[ "$mode" == "defer" ]]; then
    log_info "Created silent defer-type schedule - main script will be relaunched automatically"
  elif [[ "$mode" == "scheduled" ]]; then
    log_info "Created normal scheduled installation with UI"
  else
    log_info "Created schedule with mode: $mode"
  fi
  
  CURRENT_RUN_ID="${run_id}"
  
  return 0
}

# Function to perform emergency cleanup of all known daemons
emergency_daemon_cleanup() {
  local preserve_parent_daemon="${1:-false}"
  log_info "Performing emergency cleanup of all LaunchDaemons"
  
  # Get parent process info for preservation if needed
  local parent_daemon_label=""
  if [[ "$preserve_parent_daemon" == "true" ]] && [ -n "$PPID" ]; then
    local parent_cmd=""
    parent_cmd=$(ps -o command= -p "$PPID" 2>/dev/null || echo "")
    if [[ "$parent_cmd" == *"com.macjediwizard.eraseinstall.abort"* ]]; then
      # Extract the daemon label from the parent command
      parent_daemon_label=$(echo "$parent_cmd" | grep -o "com.macjediwizard.eraseinstall.abort[^ ]*" | head -1)
      if [ -n "$parent_daemon_label" ]; then
        log_info "Will preserve parent abort daemon: $parent_daemon_label"
      fi
    fi
  fi
  
  # First try normal removal with parent daemon preservation if needed
  if [[ -n "$parent_daemon_label" ]]; then
    log_info "Calling remove_existing_launchdaemon with --preserve-parent=$parent_daemon_label"
    remove_existing_launchdaemon "--preserve-parent=$parent_daemon_label"
  else
    # Normal removal without preservation
    remove_existing_launchdaemon
  fi
  
  # CRITICAL: Direct aggressive removal of the problematic startosinstall daemon
  if ls /Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist &>/dev/null; then
    log_info "Emergency cleanup: forcibly removing startosinstall daemon"
    
    # Kill any related process
    # SECURITY FIX (Issue #29): Use safe process termination
    log_info "Attempting to terminate startosinstall processes..."
    kill_process_safely "startosinstall" 10  # 10 second timeout for system process
    
    # Forcibly unload and remove
    launchctl remove "com.github.grahampugh.erase-install.startosinstall" 2>/dev/null
    launchctl bootout system/com.github.grahampugh.erase-install.startosinstall 2>/dev/null
    
    # Forcibly delete the file
    rm -f /Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist
    
    # Verify removal
    if [ -f "/Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist" ]; then
      log_error "Failed to remove startosinstall plist - trying alternative method"
      sudo rm -f /Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist
    fi
    
    # Check launchctl list for the daemon
    if launchctl list | grep -q "com.github.grahampugh.erase-install.startosinstall"; then
      log_warn "Daemon still present in launchctl list after removal attempts"
      # Try more aggressive methods here if needed
    fi
  fi
  
  # Direct approach for all other daemons
  for daemon_path in "/Library/LaunchDaemons/com.github.grahampugh.erase-install.*.plist" \
    "/Library/LaunchDaemons/com.macjediwizard.eraseinstall.*.plist"; do
      # Use ls to expand the wildcard
      for file in $(ls $daemon_path 2>/dev/null); do
        if [ -f "$file" ]; then
          log_info "Emergency cleanup: removing $file"
          # Get the label from the filename
          local label=$(basename "$file" .plist)
          # Try to unload it
          launchctl remove "$label" 2>/dev/null
          launchctl bootout system/"$label" 2>/dev/null
          # Force remove
          rm -f "$file"
        fi
      done
    done
  
  # Also check for user LaunchAgents
  for user in $(ls /Users); do
    for file in $(ls /Users/$user/Library/LaunchAgents/com.macjediwizard.eraseinstall.*.plist 2>/dev/null); do
      if [ -f "$file" ]; then
        log_info "Emergency cleanup: removing user agent $file"
        local user_id=$(id -u "$user" 2>/dev/null)
        local label=$(basename "$file" .plist)
        launchctl asuser "$user_id" launchctl remove "$label" 2>/dev/null
        rm -f "$file"
      fi
    done
  done
  
  # Add a final direct cleanup of both problem daemons
  log_info "Performing final direct cleanup"
  rm -f /Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist
  rm -f /Library/LaunchDaemons/com.macjediwizard.eraseinstall.schedule.watchdog.*.plist
  
  log_info "Emergency cleanup completed"
}

# Function to perform very thorough verification and cleanup of all system daemons
verify_complete_system_cleanup() {
  log_info "Verifying Complete System Cleanup"
  log_info "Running comprehensive system daemon verification"
  
  # Check if we have a current run ID from this session
  if [ -n "$CURRENT_RUN_ID" ]; then
    log_info "Current scheduled task ID: $CURRENT_RUN_ID - preserving these daemons"
    
    # CRITICAL: If we have a current ID, skip ALL cleanup to avoid race conditions
    log_info "Active scheduled task detected - skipping daemon cleanup entirely"
    return 0
  fi
  
  # Check for active abort daemons we need to preserve
  local active_abort_daemons=""
  active_abort_daemons=$(launchctl list | grep "com.macjediwizard.eraseinstall.abort" | awk '{print $3}')
  
  if [ -n "$active_abort_daemons" ]; then
    log_info "Found active abort daemons that need to be preserved: $active_abort_daemons"
  fi
  
  # Handle com.github.grahampugh.erase-install.startosinstall.plist (always remove this)
  if [ -f "/Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist" ]; then
    log_info "Found startosinstall daemon - removing"
    rm -f "/Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist"
  fi
  
  # Only continue if we have no current run ID
  log_info "No active scheduled task - checking for any lingering daemons"
  
  # For the LaunchDaemons
  for daemon in /Library/LaunchDaemons/com.macjediwizard.eraseinstall.*.plist; do
    # Skip if glob doesn't match any files
    [ ! -f "$daemon" ] && continue
    
    # Get the daemon label (filename without path or extension)
    local daemon_label=$(basename "$daemon" .plist)
    
    # Skip abort daemons that are active
    if [[ "$daemon_label" == *".abort."* ]] && echo "$active_abort_daemons" | grep -q "$daemon_label"; then
      log_info "Preserving active abort daemon: $daemon"
      continue
    fi
    
    # If it's not an abort daemon or not an active one, remove it
    log_info "Found lingering daemon: $daemon - removing"
    rm -f "$daemon"
  done
  
  # Check for user agents
  for user in $(ls /Users); do
    # Skip special directories and files
    if [ "$user" = ".localized" ] || [ "$user" = "Shared" ] || [ ! -d "/Users/$user/Library/LaunchAgents" ]; then
      continue
    fi
    
    for agent in /Users/$user/Library/LaunchAgents/com.macjediwizard.eraseinstall.*.plist; do
      # Skip if glob doesn't match any files
      [ ! -f "$agent" ] && continue
      
      log_info "Found lingering agent: $agent - removing"
      rm -f "$agent"
    done
  done
  
  log_info "Comprehensive verification cleanup complete"
}

# Function to identify and terminate lingering watchdog processes
kill_lingering_watchdogs() {
  log_info "Checking for lingering watchdog processes..."
  
  # Find all watchdog processes
  local watchdog_pids=$(ps -ef | grep -E '/bin/bash.*/Library/Management/erase-install/erase-install-watchdog-.*.sh' | grep -v grep | awk '{print $2}')
  
  if [ -n "$watchdog_pids" ]; then
    log_info "Found lingering watchdog processes: $watchdog_pids"
    
    # Kill each process
    for pid in $watchdog_pids; do
      log_info "Terminating watchdog process: $pid"
      kill -15 $pid 2>/dev/null
      sleep 0.2
    done
    
    # Wait a moment and check if they're gone
    sleep 1
    
    # Find any remaining processes and force kill
    watchdog_pids=$(ps -ef | grep -E '/bin/bash.*/Library/Management/erase-install/erase-install-watchdog-.*.sh' | grep -v grep | awk '{print $2}')
    if [ -n "$watchdog_pids" ]; then
      log_info "Some watchdog processes remain after SIGTERM. Force killing: $watchdog_pids"
      for pid in $watchdog_pids; do
        kill -9 $pid 2>/dev/null
      done
    fi
  else
    log_debug "No lingering watchdog processes found."
  fi
  
  # Remove any leftover watchdog scripts
  if [ -n "$(ls /Library/Management/erase-install/erase-install-watchdog-*.sh 2>/dev/null)" ]; then
    log_info "Removing orphaned watchdog scripts..."
    rm -f /Library/Management/erase-install/erase-install-watchdog-*.sh 2>/dev/null
  fi
}

########################################################################################################################################################################
#
# ---------------- Run Erase-Install Installer ----------------
#
########################################################################################################################################################################
run_erase_install() {
  log_info "Starting user detection for run_erase_install"

  # Get current console user for UI display - enhanced for robustness
  local console_user=""
  console_user=$(get_console_user)
  log_info "Detected console user: '$console_user'"
  local console_uid
  console_uid=$(id -u "$console_user")
  log_info "User UID: $console_uid"
  
  # Remove any existing LaunchDaemons before starting
  remove_existing_launchdaemon
  
  # Kill any existing erase-install processes
  log_info "Checking for existing erase-install processes..."
  
  # Get our script's process group
  local our_pgid=$(ps -o pgid= -p $$)
  
  # Find processes more precisely, excluding our own process group
  local pids
  pids=$(ps -e -o pid=,pgid=,command= | \
    awk -v pgid="$our_pgid" '
      $0 ~ /[e]rase-install.sh|[e]rase-install-defer-wrapper.sh/ && 
      $2 != pgid { 
        print $1 
      }
    ')
  
  if [ -n "${pids}" ]; then
    log_info "Found existing erase-install processes. Cleaning up..."
    echo "${pids}" | while read -r pid; do
      if sudo kill -15 "${pid}" 2>/dev/null; then
        log_info "Terminated process ${pid}"
      fi
    done
    
    sleep 1
    
    # Verify no processes remain
    pids=$(ps -e -o pid=,pgid=,command= | \
      awk -v pgid="$our_pgid" '
        $0 ~ /[e]rase-install.sh|[e]rase-install-defer-wrapper.sh/ && 
        $2 != pgid { 
          print $1 
        }
      ')
    
    if [ -n "${pids}" ]; then
      echo "${pids}" | while read -r pid; do
        sudo kill -9 "${pid}" 2>/dev/null && \
        log_info "Force terminated process ${pid}" || \
        log_error "Failed to terminate process ${pid}"
      done
    fi
  fi
  
  # Check if OS is already updated before running installation - add this check
  log_info "Checking if OS is already at or above target version..."
  if [[ "${SKIP_OS_VERSION_CHECK}" == "true" ]]; then
    log_info "SKIP_OS_VERSION_CHECK is enabled - testing but continuing regardless of OS version"
    test_os_version_check  # Use the initial version check
  elif check_os_already_updated; then
    log_info "OS already updated to target version. No need to install. Exiting."
    return 0
  fi
  
  # Show authentication notice before starting erase-install
  show_auth_notice
  
  local auth_notice_result=$?
  
  # DEBUG: Add these lines
  log_info "Pre-auth notice completed with return code: $auth_notice_result"
  log_info "About to start erase-install execution"
  log_info "Current working directory: $(pwd)"
  log_info "Script still running, proceeding to erase-install..."
  
  # Run the installation with proper user context for UI
  log_info "Starting erase-install..."
    
  # Special logging for test mode with power checking
  if [[ "$TEST_MODE" == "true" && "$CHECK_POWER" == "true" ]]; then
    log_info "TEST MODE: Power checking is enabled with wait limit of $POWER_WAIT_LIMIT seconds"
    log_info "TEST MODE: Note that even in test mode, erase-install will still check for power"
    log_info "TEST MODE: If this is not desired for testing, set CHECK_POWER=false in the configuration"
    
    # Enhanced visibility in test logs
    if [[ "$POWER_WAIT_LIMIT" -gt 60 ]]; then
      log_info "TEST MODE: Current power wait limit ($POWER_WAIT_LIMIT seconds) exceeds 1 minute"
      log_info "TEST MODE: For faster test cycling, consider temporarily reducing POWER_WAIT_LIMIT in test environments"
    fi
  fi
    
  # Build command with proper options
  local cmd_args=()
  cmd_args+=("${SCRIPT_PATH}")

  # CRITICAL: Specify target OS version to use cached installer or download specific version
  if [[ -n "$INSTALLER_OS" ]]; then
    cmd_args+=("--os" "$INSTALLER_OS")
    log_info "Specifying target OS version: $INSTALLER_OS (will use cached installer if available)"
  fi

  # Add options based on configuration variables with improved logging
  if [[ "$REBOOT_DELAY" -gt 0 ]]; then
    cmd_args+=("--rebootdelay" "$REBOOT_DELAY")
    log_debug "Using reboot delay: $REBOOT_DELAY seconds"
  fi
  
  if [[ "$REINSTALL" == "true" ]]; then
    cmd_args+=("--reinstall")
    log_debug "Mode: Reinstall (not erase-install)"
  fi
  
  if [[ "$NO_FS" == "true" ]]; then
    cmd_args+=("--no-fs")
    log_debug "File system check disabled (--no-fs)"
  fi
  
  if [[ "$CHECK_POWER" == "true" ]]; then
    cmd_args+=("--check-power")
    log_debug "Power check enabled: erase-install will verify power connection"
    
    if [[ "$POWER_WAIT_LIMIT" -gt 0 ]]; then
      cmd_args+=("--power-wait-limit" "$POWER_WAIT_LIMIT")
      log_debug "Power wait limit set to $POWER_WAIT_LIMIT seconds"
    else
      log_debug "Using default power wait limit (60 seconds)"
    fi
  else
    log_debug "Power check disabled: installation will proceed regardless of power status"
  fi
  
  cmd_args+=("--min-drive-space" "$MIN_DRIVE_SPACE")
  log_debug "Minimum drive space: $MIN_DRIVE_SPACE GB"
  
  if [[ "$CLEANUP_AFTER_USE" == "true" ]]; then
    cmd_args+=("--cleanup-after-use")
    log_debug "Cleanup after use enabled"
  fi
  
  if [[ "$TEST_MODE" == "true" ]]; then
    cmd_args+=("--test-run")
    log_debug "Test mode enabled"
  fi
  
  if [[ "$DEBUG_MODE" == "true" ]]; then
    cmd_args+=("--verbose")
    log_debug "Verbose logging enabled for erase-install"
  fi
  
  # Execute with proper error handling
  if ! sudo "${cmd_args[@]}"; then
    local exit_code=$?
    log_error "erase-install command failed with exit code: $exit_code"
    
    # Enhanced error logging for potential power-related issues
    if [[ "$CHECK_POWER" == "true" ]]; then
      log_error "Note: Power checking was enabled with wait limit of $POWER_WAIT_LIMIT seconds"
      log_error "If installation failed due to power issues, consider:"
      log_error "1. Increasing POWER_WAIT_LIMIT (currently $POWER_WAIT_LIMIT seconds)"
      log_error "2. Ensuring the device has reliable power connection before starting"
      log_error "3. Check erase-install log for power-related messages"
    fi
    
    # Add cleanup even on failure
    post_erase_install_cleanup
    return 1
  fi
  
  # Add cleanup after successful run
  post_erase_install_cleanup
  
  # Clean up after test run
  if [[ "$TEST_MODE" = true ]]; then
    log_info "Test run completed successfully"
    remove_existing_launchdaemon
  fi
  
  # IMPORTANT: Only reset deferrals after successful installation
  log_info "Installation completed successfully. Resetting deferral and abort counts."
  reset_all_counters
  
  return 0
}

show_preinstall() {
  local show_countdown="${1:-true}"
  local countdown=${PREINSTALL_COUNTDOWN:-60}
  
  # For test mode, add indication in the dialog title
  local display_title="$PREINSTALL_TITLE"
  [[ "$TEST_MODE" = true ]] && display_title="${PREINSTALL_TITLE_TEST_MODE}"
  
  # Remove any existing LaunchDaemons before starting
  remove_existing_launchdaemon
  
  log_info "Starting pre-installation sequence with countdown: $show_countdown"
  
  # Check OS version before countdown
  if [[ "${SKIP_OS_VERSION_CHECK}" == "true" ]]; then
    log_info "SKIP_OS_VERSION_CHECK is enabled - testing but continuing regardless of OS version"
    test_os_version_check
  elif check_os_already_updated; then
    log_info "OS already updated to target version. No need to install. Exiting."
    return 0
  fi
  
  # Skip countdown if show_countdown is false
  if [[ "$show_countdown" == "false" ]]; then
    log_info "Skipping pre-install countdown, proceeding directly to installation..."
    run_erase_install
    return
  fi
  
  # Check if abort button should be shown (only for scheduled installations, not immediate)
  local abort_button_args=""
  if [[ "${ENABLE_ABORT_BUTTON}" == "true" && "$show_countdown" == "true" ]]; then
    # Check current abort count
    local abort_count=$(defaults read "${PLIST}" abortCount 2>/dev/null || echo 0)
    if [[ $abort_count -lt $MAX_ABORTS ]]; then
      abort_button_args="--button2text \"${ABORT_BUTTON_TEXT}\""
      log_info "Adding abort button to pre-installation dialog (abort count: ${abort_count}/${MAX_ABORTS})"
    else
      log_info "Maximum aborts reached (${abort_count}/${MAX_ABORTS}) - not showing abort button"
    fi
  fi
  
  # Create a temporary file to track countdown progress
  local tmp_progress
  tmp_progress=$(mktemp)
  echo "$countdown" > "$tmp_progress"
  
  # Launch dialog with countdown and progress bar
  "$DIALOG_BIN" --title "$display_title" \
  --message "$PREINSTALL_MESSAGE" \
  --button1text "$PREINSTALL_CONTINUE_TEXT" \
  $abort_button_args \
  --height ${PREINSTALL_HEIGHT} \
  --width ${PREINSTALL_WIDTH} \
  --messagefont ${PREINSTALL_DIALOG_MESSAGEFONT} \
  --moveable \
  --icon "$DIALOG_ICON" \
  --ontop \
  --progress "$countdown" \
  --progresstext "Starting in $countdown seconds..." \
  --position "$DIALOG_POSITION" \
  --jsonoutput > /tmp/dialog_output.json &
  
  local dialog_pid=$!
  local dialog_status=$?
  local countdown_remaining=$countdown
  local dialog_closed=false
  
  # Check if dialog started properly
  if [ $dialog_status -ne 0 ] || [ -z "$dialog_pid" ]; then
    log_error "Failed to start countdown dialog. Proceeding directly to installation."
    rm -f "$tmp_progress"
    local install_result=0
    run_erase_install
    install_result=$?
    return $install_result
  fi
  
  # Update countdown progress
  while [[ $countdown_remaining -gt 0 ]]; do
    # Check if the dialog is still running
    if ! kill -0 $dialog_pid 2>/dev/null; then
      dialog_closed=true
      log_info "Pre-install dialog closed by user, continuing immediately"
      break
    fi
    
    # Decrement countdown
    ((countdown_remaining--))
    echo "$countdown_remaining" > "$tmp_progress"
    
    # Update dialog progress
    "$DIALOG_BIN" --progresstext "Starting in $countdown_remaining seconds..." --progress "$countdown_remaining"
    
    # Wait 1 second
    sleep 1
  done
  
  # Kill dialog if still running
  if ! $dialog_closed && kill -0 $dialog_pid 2>/dev/null; then
    kill $dialog_pid 2>/dev/null
  fi
  
  # Cleanup temp file
  rm -f "$tmp_progress"
  
  # Process dialog output if available
  if [ -f /tmp/dialog_output.json ]; then
    local btn=$(cat /tmp/dialog_output.json | grep "button" | cut -d':' -f2 | tr -d '" ,')
    log_info "Pre-install dialog returned: [$btn] (or timed out)"
    
    # Handle abort button click (button 2)
    if [[ "$btn" == "2" ]]; then
      log_info "Abort button clicked in pre-installation dialog"
      
      # Increment abort count
      local abort_count=$(defaults read "$PLIST" abortCount 2>/dev/null || echo 0)
      abort_count=$((abort_count + 1))
      defaults write "$PLIST" abortCount -int "$abort_count"
      log_info "Abort count incremented to $abort_count/$MAX_ABORTS"
      
      # Create abort file for watchdog to detect
      if [[ -n "$CURRENT_RUN_ID" ]]; then
        touch "/var/tmp/erase-install-abort-${CURRENT_RUN_ID}"
        log_info "Created abort signal file at: /var/tmp/erase-install-abort-${CURRENT_RUN_ID}"
      else
        log_warn "No current run ID available - abort may not work correctly"
      fi
      
      # Show abort countdown dialog
      "${DIALOG_BIN}" --title "Aborting Installation" \
      --message "Emergency abort activated. Installation will be postponed for ${ABORT_DEFER_MINUTES} minutes." \
      --icon "${ABORT_ICON}" \
      --button1text "OK" \
      --timer "${ABORT_COUNTDOWN}" \
      --progress "${ABORT_COUNTDOWN}" \
      --progresstext "Aborting in ${ABORT_COUNTDOWN} seconds..." \
      --position "${DIALOG_POSITION}" \
      --moveable \
      --ontop \
      --height "${ABORT_HEIGHT}" \
      --width "${ABORT_WIDTH}"
      
      # Signal success to the user
      osascript -e "display notification \"Installation aborted and will be rescheduled\" with title \"macOS Upgrade\"" 2>/dev/null || true
      
      # Clean up
      rm -f /tmp/dialog_output.json
      rm -f "$tmp_progress"
      
      # Exit without installing
      return 1
    fi
    
    rm -f /tmp/dialog_output.json
  else
    log_info "Pre-install dialog completed countdown, continuing automatically"
  fi
  
  # Run the installation
  log_info "Starting installation after countdown"
  local install_result=0
  run_erase_install
  install_result=$?
  
  # Final cleanup
  remove_existing_launchdaemon
  log_info "Installation sequence completed with status: $install_result"
  
  return $install_result
  
}

# -------------- Prompt Handling --------------
set_options() {
  log_info "Setting dialog options based on deferral state..."
  
  local defer_text
  if [[ "$TEST_MODE" == "true" ]]; then
    defer_text="Defer 5 Minutes   (TEST MODE)"
    DIALOG_DEFER_TEXT_TEST_MODE="$defer_text"
  else
    defer_text="${DIALOG_DEFER_TEXT}"
  fi
  
  # Use the new state variables
  if [[ "${FORCE_INSTALL}" = true ]]; then
    OPTIONS="${DIALOG_INSTALL_NOW_TEXT},${DIALOG_SCHEDULE_TODAY_TEXT}"
    log_info "FORCE_INSTALL=true - Removing defer option from dialog"
    
    # Log why it was exceeded for debugging
    if (( CURRENT_DEFER_COUNT >= MAX_DEFERS )); then
      log_info "Defer option removed because max deferrals (${CURRENT_DEFER_COUNT}/${MAX_DEFERS}) have been used"
    else
      local elapsed_hours=$((CURRENT_ELAPSED / 3600))
      log_info "Defer option removed because time limit exceeded: ${elapsed_hours} hours elapsed"
    fi
  else
    OPTIONS="${DIALOG_INSTALL_NOW_TEXT},${DIALOG_SCHEDULE_TODAY_TEXT},${defer_text}"
    log_info "FORCE_INSTALL=false - Including defer option: '${defer_text}' (${CURRENT_DEFER_COUNT}/${MAX_DEFERS} deferrals used)"
  fi
  
  # Verify option string was created correctly
  if [[ -z "$OPTIONS" ]]; then
    log_error "Failed to create options string - using fallback"
    OPTIONS="${DIALOG_INSTALL_NOW_TEXT},${DIALOG_SCHEDULE_TODAY_TEXT}"
  else
    log_debug "Set options string to: $OPTIONS"
  fi
}

generate_time_options() {
  # Start with a clean slate
  local time_options=""
  local error_state=false
  
  # Get current hour and minute with error checking
  local current_hour=$(date +%H 2>/dev/null)
  local current_minute=$(date +%M 2>/dev/null)
  
  if [[ -z "$current_hour" || -z "$current_minute" ]]; then
    log_error "Failed to get current time"
    echo "08:00,09:00,10:00,11:00"  # Provide safe defaults
    return 1
  fi
  
  # Convert to base-10 integers to handle leading zeros properly
  local current_hour_num
  local current_minute_num
  
  # Safe conversion with error handling
  if ! current_hour_num=$((10#$current_hour)) 2>/dev/null; then
    log_error "Failed to convert hour to number: $current_hour"
    current_hour_num=8  # Safe default
    error_state=true
  fi
  
  if ! current_minute_num=$((10#$current_minute)) 2>/dev/null; then
    log_error "Failed to convert minute to number: $current_minute"
    current_minute_num=0  # Safe default
    error_state=true
  fi
  
  # Add today's remaining hours in 15-minute increments
  # Calculate which 15-minute blocks remain in the current hour
  if [ $current_minute_num -lt 15 ]; then
    time_options="${current_hour}:15,${current_hour}:30,${current_hour}:45"
  elif [ $current_minute_num -lt 30 ]; then
    time_options="${current_hour}:30,${current_hour}:45"
  elif [ $current_minute_num -lt 45 ]; then
    time_options="${current_hour}:45"
  fi
  
  # Add remaining full hours today - ensure we stop at 23
  local next_hour=$((current_hour_num + 1))
  if [ $next_hour -le 23 ]; then
    for h in $(seq $next_hour 23); do
      local fmt_hour
      # Safely format the hour with error handling
      if ! fmt_hour=$(printf "%02d" $h 2>/dev/null); then
        log_error "Failed to format hour: $h"
        fmt_hour="$h"  # Use unformatted as fallback
        error_state=true
      fi
      time_options="${time_options:+$time_options,}${fmt_hour}:00,${fmt_hour}:15,${fmt_hour}:30,${fmt_hour}:45"
    done
  fi
  
  # Add tomorrow early morning (8, 9, 10) if we have few options left today
  if [ $next_hour -gt 20 ]; then
    time_options="${time_options:+$time_options,}Tomorrow 08:00,Tomorrow 08:30,Tomorrow 09:00,Tomorrow 09:30"
  fi
  
  # Ensure we have at least some options
  if [ -z "$time_options" ]; then
    log_warn "No viable time options generated, using fallback values"
    time_options="Tomorrow 08:00,Tomorrow 08:30,Tomorrow 09:00,Tomorrow 09:30"
  fi
  
  # Log warning if errors occurred
  if $error_state; then
    log_warn "Some errors occurred during time option generation, results may be incomplete"
  fi
  
  printf "%s" "$time_options"
}

validate_time() {
  local input="$1"
  
  # Check for empty or null input
  if [[ -z "$input" ]]; then
    log_warn "Empty time input provided"
    return 1
  fi
  
  local hour="" minute="" day="" month=""
  local when=""
  
  if [[ "$input" == "Tomorrow "* ]]; then
    local t; t=$(echo "$input" | awk '{print $2}')
    hour=$(echo "$t" | cut -d: -f1)
    minute=$(echo "$t" | cut -d: -f2)
    
    # Check if hour and minute were properly extracted
    if [[ -z "$hour" || -z "$minute" ]]; then
      log_warn "Invalid time format for tomorrow: $input (failed to extract hour/minute)"
      return 1
    fi
    
    # Convert hour to base 10 to handle leading zeros
    hour=$((10#${hour}))
    minute=$((10#${minute}))
    
    # Validate hour range
    if [[ $hour -lt 0 || $hour -gt 23 || $minute -lt 0 || $minute -gt 59 ]]; then
      log_warn "Invalid time format for tomorrow: $input (hour must be 0-23, minute 0-59)"
      return 1
    fi
    
    when="tomorrow"
    day=$(date -v+1d +%d)
    month=$(date -v+1d +%m)
  else
    hour=$(echo "$input" | cut -d: -f1)
    minute=$(echo "$input" | cut -d: -f2)
    
    # Check if hour and minute were properly extracted
    if [[ -z "$hour" || -z "$minute" ]]; then
      log_warn "Invalid time format: $input (failed to extract hour/minute)"
      return 1
    fi
    
    # Convert hour and minute to base 10 to handle leading zeros
    hour=$((10#${hour}))
    minute=$((10#${minute}))
    
    # Validate hour range
    if [[ $hour -lt 0 || $hour -gt 23 || $minute -lt 0 || $minute -gt 59 ]]; then
      log_warn "Invalid time format: $input (hour must be 0-23, minute 0-59)"
      return 1
    fi
    
    when="today"
  fi
  
  # Ensure we have all required values before returning
  if [[ -z "$when" || -z "$hour" || -z "$minute" ]]; then
    log_warn "Failed to extract valid time components from: $input"
    return 1
  fi
  
  if [[ "$when" == "tomorrow" ]]; then
    printf "%s %02d %02d %s %s" "$when" "$hour" "$minute" "$day" "$month"
  else
    printf "%s %02d %02d" "$when" "$hour" "$minute"
  fi
}

show_prompt() {
  log_info "Displaying SwiftDialog dropdown prompt."

  # Get console user for proper UI handling
  local console_user=""
  console_user=$(get_console_user)
  local console_uid
  console_uid=$(id -u "$console_user" 2>/dev/null || echo "0")
  
  # Set UI environment for the console user
  export DISPLAY=:0
  if [ -n "$console_uid" ] && [ "$console_uid" != "0" ]; then
    launchctl asuser "$console_uid" sudo -u "$console_user" defaults write org.swift.SwiftDialog FrontmostApplication -bool true
  fi
  
  # For test mode, add indication in the dialog title
  local display_title="$DIALOG_TITLE"
  [[ "$TEST_MODE" = true ]] && display_title="${DIALOG_TITLE_TEST_MODE}"

  # Apply branding to dialog parameters
  local branded_title branded_message branded_icon
  local branding_result
  branding_result=$(apply_branding "$display_title" "$DIALOG_MESSAGE" "$DIALOG_ICON")
  branded_title=$(echo "$branding_result" | sed -n '1p')
  branded_message=$(echo "$branding_result" | sed -n '2p')
  branded_icon=$(echo "$branding_result" | sed -n '3p')

  local raw; raw=$("${DIALOG_BIN}" --title "${branded_title}" --message "${branded_message}" --button1text "${DIALOG_CONFIRM_TEXT}" --height ${DIALOG_HEIGHT} --width ${DIALOG_WIDTH} --moveable --icon "${branded_icon}" --ontop --timeout 0 --showicon true --position "${DIALOG_POSITION}" --messagefont ${DIALOG_MESSAGEFONT} --selecttitle "Select an action:" --select --selectvalues "${OPTIONS}" --selectdefault "${DIALOG_INSTALL_NOW_TEXT}" --jsonoutput 2>&1 | tee -a "${WRAPPER_LOG}")
  local code=$?
  log_debug "SwiftDialog exit code: ${code}"
  log_debug "SwiftDialog raw output: ${raw}"
  
  [[ $code -ne 0 || -z "$raw" ]] && { log_warn "No valid JSON from SwiftDialog; aborting."; return 1; }
  
  local selection; selection=$(parse_dialog_output "$raw" "SelectedOption")
  [[ -z "$selection" || "$selection" == "null" ]] && { log_warn "No selection made; aborting."; return 1; }
  
  log_info "User selected: ${selection}"
  
  case "$selection" in
    "${DIALOG_INSTALL_NOW_TEXT}")
      
      # Preserve abort daemon if we're running from one
      if [[ "$RUNNING_FROM_ABORT_DAEMON" == "true" ]]; then
        log_info "Running from abort daemon - performing selective cleanup"
        remove_existing_launchdaemon --preserve-abort-daemon
      else
        remove_existing_launchdaemon
      fi
      
      # Check if OS is already at the target version
      log_info "Checking if OS is already up-to-date before proceeding with immediate installation..."
      if [[ "${SKIP_OS_VERSION_CHECK}" == "true" ]]; then
        log_info "SKIP_OS_VERSION_CHECK is enabled - testing but continuing regardless of OS version"
        test_os_version_check
      elif check_os_already_updated; then
        log_info "System is already running the target OS version. No update needed."
        
        # Show a notification to the user
        if [ -n "$console_user" ] && [ "$console_user" != "root" ] && [ -n "$console_uid" ]; then
          launchctl asuser "$console_uid" sudo -u "$console_user" osascript -e 'display notification "Your macOS is already up to date. No update required." with title "macOS Upgrade"'
        fi
        
        log_info "Exiting without installation as OS is already up-to-date."
        return 0
      fi
      
      # Skip countdown for immediate installations - go directly to installation
      log_info "Install Now selected - proceeding directly to installation"
      local install_result=0
      run_erase_install
      install_result=$?
      return $install_result
    ;;
    
    "${DIALOG_SCHEDULE_TODAY_TEXT}")
      local sched subcode time_data hour minute day month
      local time_options; time_options=$(generate_time_options)
      # For test mode, add indication in the dialog title
      local display_title="$SCHEDULED_TITLE"
      [[ "$TEST_MODE" = true ]] && display_title="${SCHEDULED_TITLE_TEST_MODE}"

      # Apply branding to schedule dialog
      local sched_branding
      sched_branding=$(apply_branding "$display_title" "Select installation time:" "$DIALOG_ICON")
      local sched_title=$(echo "$sched_branding" | sed -n '1p')
      local sched_message=$(echo "$sched_branding" | sed -n '2p')
      local sched_icon=$(echo "$sched_branding" | sed -n '3p')

      local sub; sub=$("${DIALOG_BIN}" --title "${sched_title}" --message "${sched_message}" --button1text "${DIALOG_CONFIRM_TEXT}" --height ${SCHEDULED_HEIGHT} --width ${SCHEDULED_WIDTH} --moveable --icon "${sched_icon}" --ontop --timeout 0 --showicon true --position "${DIALOG_POSITION}" --messagefont "${SCHEDULED_DIALOG_MESSAGEFONT}" --selecttitle "Choose time:" --select --selectvalues "${time_options}" --selectdefault "$(echo "$time_options" | cut -d',' -f1)" --jsonoutput 2>&1 | tee -a "${WRAPPER_LOG}")
      subcode=$?
      log_debug "Schedule dialog exit code: ${subcode}"
      log_debug "Schedule raw output: ${sub}"
      [[ $subcode -ne 0 || -z "$sub" ]] && { log_warn "No time selected; aborting."; return 1; }
      sched=$(parse_dialog_output "$sub" "SelectedOption")
      [[ -z "$sched" || "$sched" == "null" ]] && { log_warn "No time selected; aborting."; return 1; }
      log_info "Selected time: ${sched}"
      
      time_data=$(validate_time "$sched")
      if [[ $? -ne 0 || -z "$time_data" ]]; then
        log_warn "Invalid time selection: $sched"

        # Apply branding to error dialog
        local error_branding
        error_branding=$(apply_branding "$ERROR_DIALOG_TITLE" "$ERROR_DIALOG_MESSAGE" "$ERROR_DIALOG_ICON")
        local error_title=$(echo "$error_branding" | sed -n '1p')
        local error_message=$(echo "$error_branding" | sed -n '2p')
        local error_icon=$(echo "$error_branding" | sed -n '3p')

        # Show error dialog
        "${DIALOG_BIN}" --title "${error_title}" --message "${error_message}" --icon "${error_icon}" --button1text "${ERROR_CONTINUE_TEXT}" --height ${ERROR_DIALOG_HEIGHT} --width ${ERROR_DIALOG_WIDTH} --position "${DIALOG_POSITION}"
        
        # Return to main prompt instead of exiting
        show_prompt
        return $?
      fi
      
      # Parse time data
      read -r when hour minute day month <<< "$time_data"
      
      # Convert to proper numeric values for display
      local hour_num=$((10#${hour}))
      local minute_num=$((10#${minute}))
      
      # Check if OS is already at the target version
      log_info "Checking if OS is already up-to-date before scheduling installation..."
      if [[ "${SKIP_OS_VERSION_CHECK}" == "true" ]]; then
        log_info "SKIP_OS_VERSION_CHECK is enabled - testing but continuing regardless of OS version"
        test_os_version_check
      elif check_os_already_updated; then
        log_info "System is already running the target OS version. No update needed."
        
        # Show a notification to the user
        if [ -n "$console_user" ] && [ "$console_user" != "root" ] && [ -n "$console_uid" ]; then
          launchctl asuser "$console_uid" sudo -u "$console_user" osascript -e 'display notification "Your macOS is already up to date. No scheduled installation required." with title "macOS Upgrade"'
        fi
        
        log_info "Exiting without scheduling installation as OS is already up-to-date."
        return 0
      fi
      
      # **CRITICAL FIX: Enhanced daemon creation for abort context**
      log_info "Creating scheduled installation daemon (abort context: ${RUNNING_FROM_ABORT_DAEMON:-false})"
      
      # Enhanced handling for abort context
      if [[ "${RUNNING_FROM_ABORT_DAEMON}" == "true" ]]; then
        log_info "🔄 ABORT CONTEXT: Creating scheduled daemon with preserved cleanup"
        # Get our current abort daemon ID from environment or parent process
        local current_abort_daemon_id=""
        
        # Try multiple methods to get the abort daemon ID
        if [ -n "$PPID" ]; then
          local parent_cmd=$(ps -o command= -p "$PPID" 2>/dev/null || echo "")
          current_abort_daemon_id=$(echo "$parent_cmd" | grep -o '[0-9]\{14\}' || echo "")
        fi
        
        # Fallback: check for any active abort daemon in plist
        if [[ -z "$current_abort_daemon_id" ]]; then
          current_abort_daemon_id=$(defaults read "${PLIST}" abortRunID 2>/dev/null || echo "")
        fi
        
        # Fallback: get from script name/path
        if [[ -z "$current_abort_daemon_id" ]]; then
          current_abort_daemon_id=$(echo "$0" | grep -o '[0-9]\{14\}' || echo "")
        fi
        
        if [[ -n "$current_abort_daemon_id" ]]; then
          log_info "✅ Preserving current abort daemon ID: $current_abort_daemon_id"
          # DON'T remove existing daemons when running from abort context
          log_info "Skipping daemon cleanup to preserve abort daemon"
        else
          log_warn "⚠️ Could not identify current abort daemon ID - proceeding with normal cleanup"
          remove_existing_launchdaemon
        fi
      else
        log_info "📋 NORMAL CONTEXT: Standard daemon creation"
        remove_existing_launchdaemon
      fi
      
      # Store current OS version for comparison when daemon runs
      local current_os=$(sw_vers -productVersion)
      defaults write "${PLIST}" initialOSVersion -string "${current_os}"
      
      # Use erase-install to determine available version
      local available_version
      available_version=$(get_available_macos_version)
      defaults write "${PLIST}" targetOSVersion -string "${available_version}"
      log_info "Stored initial OS: $current_os and target OS: $available_version for scheduled installation"
      
      if [[ "$when" == "tomorrow" ]]; then
        log_info "Scheduling for tomorrow at $(printf '%02d:%02d' $((hour_num)) $((minute_num)))"
        if ! create_scheduled_launchdaemon "$hour" "$minute" "$day" "$month" "scheduled"; then
          log_error "Failed to create scheduled LaunchDaemon for tomorrow"
          return 1
        fi
      else
        log_info "Scheduling for today at $(printf '%02d:%02d' $((hour_num)) $((minute_num)))"
        if ! create_scheduled_launchdaemon "${hour}" "${minute}" "" "" "scheduled"; then
          log_error "Failed to create scheduled LaunchDaemon"
          return 1
        fi
      fi
      
      # **NEW: Verify daemon creation succeeded**
      sleep 2  # Give daemon time to be created and loaded
      local expected_time=$(printf '%02d%02d' $((hour_num)) $((minute_num)))
      log_info "Verifying scheduled daemon creation for time: $expected_time"
      
      # Check for daemon file existence
      if ls /Library/LaunchDaemons/com.macjediwizard.eraseinstall.schedule.watchdog.*${expected_time}*.plist 2>/dev/null; then
        log_info "✅ Successfully verified scheduled daemon creation"
      else
        # Fallback verification - check for any recent daemon
        local recent_daemon=$(ls -t /Library/LaunchDaemons/com.macjediwizard.eraseinstall.schedule.watchdog.*.plist 2>/dev/null | head -1)
        if [[ -n "$recent_daemon" ]]; then
          log_info "✅ Found recent scheduled daemon: $(basename "$recent_daemon")"
        else
          log_error "❌ Scheduled daemon creation verification failed"
          log_error "No daemon found for time: $expected_time"
          return 1
        fi
      fi
    ;;
    
    # Handle both normal and test mode defer options
    "${DIALOG_DEFER_TEXT}" | "${DIALOG_DEFER_TEXT_TEST_MODE}")
      if [[ "${FORCE_INSTALL}" = true ]]; then
        log_warn "Maximum deferrals (${MAX_DEFERS}) reached or time limit exceeded (used: ${CURRENT_DEFER_COUNT}/${MAX_DEFERS})."
        log_info "Force install triggered - deferrals will be reset only after installation completes."
        
        # Check if OS is already at the target version
        log_info "Checking if OS is already up-to-date before forced installation after max deferrals..."
        if [[ "${SKIP_OS_VERSION_CHECK}" == "true" ]]; then
          log_info "SKIP_OS_VERSION_CHECK is enabled - testing but continuing regardless of OS version"
          test_os_version_check
        elif check_os_already_updated; then
          log_info "System is already running the target OS version. No update needed."
          
          # Show a notification to the user
          if [ -n "$console_user" ] && [ "$console_user" != "root" ] && [ -n "$console_uid" ]; then
            launchctl asuser "$console_uid" sudo -u "$console_user" osascript -e 'display notification "Your macOS is already up to date. No update required." with title "macOS Upgrade"'
          fi
          
          log_info "Exiting without installation as OS is already up-to-date."
          return 0
        fi
        
        # Show countdown for installations after deferral expiry
        show_preinstall "true"
      else
        # Use the state management function instead of direct plist manipulation
        if ! increment_defer_count; then
          log_error "Failed to increment defer count"
          return 1
        fi
        
        # Don't call get_installation_state here - it overwrites our just-incremented count
        # The increment_defer_count function already calls it internally
        log_info "Defer count incremented to: $CURRENT_DEFER_COUNT"
        
        # Use the updated state variable
        local newCount=$CURRENT_DEFER_COUNT
        
        if [[ "$TEST_MODE" == "true" ]]; then
          log_info "TEST MODE: Deferred for 5 minutes (${newCount}/${MAX_DEFERS})"
        else
          log_info "Deferred for 24 hours (${newCount}/${MAX_DEFERS})"
        fi
        
        # Store current OS version and target OS version
        local current_os=$(sw_vers -productVersion)
        defaults write "${PLIST}" initialOSVersion -string "${current_os}"
        
        # Use erase-install to determine available version
        local available_version
        available_version=$(get_available_macos_version)
        defaults write "${PLIST}" targetOSVersion -string "${available_version}"
        log_info "Stored initial OS: $current_os and target OS: $available_version for deferral comparison"
        
        # Get tomorrow's time
        if [[ "$TEST_MODE" == "true" ]]; then
          # Test mode: Schedule for 5 minutes from now for testing
          log_info "TEST MODE: Using 5-minute deferral instead of 24 hours"
          
          # Get current time
          local current_hour=$(date +%H)
          local current_min=$(date +%M)
          
          # Convert to base-10 integers (handling leading zeros)
          current_hour=$((10#$current_hour))
          current_min=$((10#$current_min))
          
          # Add 5 minutes
          current_min=$((current_min + 5))
          
          # Handle minute rollover
          if [[ $current_min -ge 60 ]]; then
            current_min=$((current_min - 60))
            current_hour=$((current_hour + 1))
          fi
          
          # Handle hour rollover
          if [[ $current_hour -ge 24 ]]; then
            current_hour=$((current_hour - 24))
            # We need tomorrow's date if hours rolled over
            defer_day=$(date -v+1d +%d)
            defer_month=$(date -v+1d +%m)
          else
            # Use today's date
            defer_day=$(date +%d)
            defer_month=$(date +%m)
          fi
          
          # Format back to strings with leading zeros
          defer_hour=$(printf "%02d" $current_hour)
          defer_min=$(printf "%02d" $current_min)
          
          log_info "TEST MODE: Scheduling for today/tomorrow at $defer_hour:$defer_min"
        else
          # Production mode: Use regular 24-hour deferral
          log_info "Regular 24-hour deferral mode"
          
          # Get current date/time components
          local current_hour=$(date +%H)
          local current_min=$(date +%M)
          local current_day=$(date +%d)
          local current_month=$(date +%m)
          
          # Convert to base-10 integers (handling leading zeros)
          current_hour=$((10#$current_hour))
          current_min=$((10#$current_min))
          current_day=$((10#$current_day))
          current_month=$((10#$current_month))
          
          # Same time tomorrow
          local defer_day=$((current_day + 1))
          local defer_month=$current_month
          
          # Handle month rollover - check max days in current month
          local days_in_month=31
          if [[ $current_month -eq 4 || $current_month -eq 6 || $current_month -eq 9 || $current_month -eq 11 ]]; then
            days_in_month=30
          elif [[ $current_month -eq 2 ]]; then
            # February: check for leap year (simplified)
            local year=$(date +%Y)
            if (( year % 400 == 0 || (year % 4 == 0 && year % 100 != 0) )); then
              days_in_month=29
            else
              days_in_month=28
            fi
          fi
          
          # Adjust for month rollover
          if [[ $defer_day -gt $days_in_month ]]; then
            defer_day=1
            defer_month=$((current_month + 1))
            # Handle year rollover
            if [[ $defer_month -gt 12 ]]; then
              defer_month=1
            fi
          fi
          
          # Format back to strings with leading zeros
          defer_hour=$(printf "%02d" $current_hour)
          defer_min=$(printf "%02d" $current_min)
          defer_day=$(printf "%02d" $defer_day)
          defer_month=$(printf "%02d" $defer_month)
        fi
        
        # Important: Clean up all daemons EXCEPT the one stored in the plist
        log_info "Removing existing LaunchDaemons while preserving active relaunch daemon"
        remove_existing_launchdaemon
        
        # Add improved debugging for scheduling information
        log_debug "Scheduling info: hour=${defer_hour}, min=${defer_min}, day=${defer_day}, month=${defer_month}, mode=defer"
        
        # Create LaunchDaemon with original time values (preserving leading zeros)
        local created_launchdaemon=false
        if create_scheduled_launchdaemon "${defer_hour}" "${defer_min}" "${defer_day}" "${defer_month}" "defer"; then
          created_launchdaemon=true
          
          # Verify the scheduled LaunchDaemon was actually created
          if [[ -n "$CURRENT_RUN_ID" ]]; then
            local expected_daemon_path="/Library/LaunchDaemons/${LAUNCHDAEMON_LABEL}.watchdog.${CURRENT_RUN_ID}.plist"
            if [[ -f "$expected_daemon_path" ]]; then
              log_info "Successfully verified scheduled LaunchDaemon exists at: $expected_daemon_path"
              
              # Extra validation - check the contents of the daemon
              local daemon_hour=$(defaults read "$expected_daemon_path" StartCalendarInterval | grep -A1 Hour | grep integer | awk '{print $1}' | tr -d '<integer>')
              local daemon_minute=$(defaults read "$expected_daemon_path" StartCalendarInterval | grep -A1 Minute | grep integer | awk '{print $1}' | tr -d '<integer>')
              
              if [[ -n "$daemon_hour" && -n "$daemon_minute" ]]; then
                log_info "Verified LaunchDaemon time settings: ${daemon_hour}:${daemon_minute}"
              else
                log_warn "Could not verify time settings in LaunchDaemon"
              fi
              
              # Check if daemon is loaded in launchctl
              local daemon_label="${LAUNCHDAEMON_LABEL}.watchdog.${CURRENT_RUN_ID}"
              if launchctl list | grep -q "$daemon_label"; then
                log_info "Verified LaunchDaemon is loaded in launchctl: $daemon_label"
              else
                log_warn "LaunchDaemon file exists but may not be loaded: $daemon_label"
                log_info "Attempting to load LaunchDaemon again..."
                launchctl load "$expected_daemon_path" 2>/dev/null || true
                
                # Second verification
                if launchctl list | grep -q "$daemon_label"; then
                  log_info "Successfully loaded LaunchDaemon on second attempt: $daemon_label"
                else
                  log_warn "Failed to load LaunchDaemon after second attempt"
                  # Try one more time with sudo
                  log_info "Attempting to load with sudo..."
                  sudo launchctl load "$expected_daemon_path" 2>/dev/null || true
                fi
              fi
            else
              log_warn "LaunchDaemon file not found at expected path: $expected_daemon_path"
              created_launchdaemon=false
            fi
          else
            log_warn "No CURRENT_RUN_ID available, cannot verify LaunchDaemon path"
          fi
          
          # Only continue if we created and verified the LaunchDaemon
          if [[ "$created_launchdaemon" == "true" ]]; then
            # Base-10 conversion only for display
            local display_hour=$((10#${defer_hour}))
            local display_min=$((10#${defer_min}))
            local display_day=$((10#${defer_day}))
            local display_month=$((10#${defer_month}))
            
            if [[ "$TEST_MODE" == "true" ]]; then
              log_info "TEST MODE: Scheduled re-prompt for $defer_hour:$defer_min (in approximately 5 minutes)"
              log_info "Deferral count is now ${newCount} of ${MAX_DEFERS}"
              
              # Show a notification to the user if possible
              if [ -n "$console_user" ] && [ "$console_user" != "root" ] && [ -n "$console_uid" ]; then
                launchctl asuser "$console_uid" sudo -u "$console_user" osascript -e "display notification \"Test mode: Deferral ${newCount}/${MAX_DEFERS} scheduled for 5 minutes from now.\" with title \"macOS Upgrade Deferred\""
              fi
            else
              local formatted_date=$(date -j -f "%Y-%m-%d %H:%M:%S" "$(date +%Y)-${display_month}-${display_day} ${display_hour}:${display_min}:00" "+%a, %b %d at %I:%M %p" 2>/dev/null)
              log_info "Scheduled re-prompt for ${formatted_date} (deferral ${newCount}/${MAX_DEFERS})"
              
              # Show a notification to the user if possible
              if [ -n "$console_user" ] && [ "$console_user" != "root" ] && [ -n "$console_uid" ]; then
                launchctl asuser "$console_uid" sudo -u "$console_user" osascript -e "display notification \"macOS upgrade deferred until ${formatted_date} (deferral ${newCount}/${MAX_DEFERS})\" with title \"macOS Upgrade Deferred\""
              fi
            fi
          else
            log_error "LaunchDaemon creation appeared to succeed but verification failed"
            
            # Try direct retry with more permissions
            log_info "Attempting direct retry of LaunchDaemon creation..."
            # Force cleanup first
            remove_existing_launchdaemon
            
            # Try again with sudo if needed
            if create_scheduled_launchdaemon "${defer_hour}" "${defer_min}" "${defer_day}" "${defer_month}" "defer"; then
              log_info "Second attempt to create LaunchDaemon succeeded"
            else
              log_error "Second attempt to create LaunchDaemon also failed"
              return 1
            fi
          fi
        else
          log_error "Failed to schedule re-prompt"
          
          # Check permission issues on critical directories
          log_info "Checking for permission issues in critical directories..."
          ls -la /Library/LaunchDaemons/ | head -5 | log_debug
          
          # Try to diagnose common issues
          log_info "Checking for common issues that might prevent daemon creation..."
          
          # Check disk space
          local disk_space=$(df -h / | awk 'NR==2 {print $4}')
          log_info "Available disk space: $disk_space"
          
          # Check if we're in a restricted environment
          if [[ "$(csrutil status)" == *"enabled"* ]]; then
            log_info "System Integrity Protection is enabled"
          fi
          
          return 1
        fi
      fi
    ;;
    *)
      log_warn "Unexpected selection: $selection"
      return 1
    ;;
  esac
  
  return 0
}

# ----------------Installer Functions----------------

# Check for test mode argument
if [[ "$1" == "--test-os-check" ]]; then
  # Enable the OS version check test mode
  SKIP_OS_VERSION_CHECK=true
  shift  # Remove this argument and continue processing others
fi

# Check for test power wait option
if [[ "$1" == "--test-power-wait" ]]; then
  # Initialize logging first
  init_logging
  log_info "Starting power wait limit test mode"
  log_system_info
  
  # Verify power wait limit configuration
  log_info "===== POWER WAIT LIMIT TEST MODE ====="
  log_info "Current Power Check setting: CHECK_POWER=${CHECK_POWER}"
  log_info "Current Power Wait Limit: POWER_WAIT_LIMIT=${POWER_WAIT_LIMIT} seconds"
  
  # Add a power status check to the test mode
  log_info "Checking current system power status..."
  if system_profiler SPPowerDataType &>/dev/null; then
    power_info=$(system_profiler SPPowerDataType 2>/dev/null)
    
    if echo "$power_info" | grep -q "AC Power: Yes"; then
      log_info "POWER TEST: System is currently connected to AC power"
      log_info "POWER TEST: erase-install would proceed immediately with installation"
    else
      log_info "POWER TEST: System is currently running on battery power"
      log_info "POWER TEST: erase-install would wait up to $POWER_WAIT_LIMIT seconds for power connection"
      
      # Get battery percentage if available
      battery_percent=$(echo "$power_info" | grep "State of Charge" | awk '{print $5}' | tr -d '%')
      if [[ -n "$battery_percent" ]]; then
        log_info "POWER TEST: Current battery charge level: ${battery_percent}%"
      fi
    fi
    
    # Log all power information for debugging purposes
    log_info "POWER TEST: Full power information (for reference):"
    echo "$power_info" | grep -E 'Power Source|AC Power|State of Charge|Time|Cycle Count' | while IFS= read -r line; do
      log_info "    $line"
    done
  else
    log_info "POWER TEST: No battery detected. Device is likely a desktop on AC power."
    log_info "POWER TEST: erase-install would proceed immediately with installation"
  fi
  
  # Show how this would be passed to erase-install
  log_info "These settings would result in the following parameters to erase-install:"
  if [[ "$CHECK_POWER" == "true" ]]; then
    log_info "  --check-power --power-wait-limit ${POWER_WAIT_LIMIT}"
    log_info "Graham's erase-install script will wait up to ${POWER_WAIT_LIMIT} seconds for power connection"
  else
    log_info "  [no power check parameters]"
    log_info "Graham's erase-install script will NOT check for power connection"
  fi
  
  log_info "===== POWER WAIT LIMIT TEST COMPLETE ====="
  exit 0
fi

# First, check for cleanup command option
if [[ "$1" == "--cleanup" ]]; then
  # Initialize logging first
  init_logging
  log_info "Running emergency cleanup of all watchdog processes and locks"
  
  # Kill all watchdog processes
  log_info "Finding and terminating all watchdog processes..."
  for pid in $(ps -ef | grep -E '/bin/bash.*/Library/Management/erase-install/erase-install-watchdog-.*.sh' | grep -v grep | awk '{print $2}'); do
    log_info "Killing watchdog process: $pid"
    kill -9 $pid 2>/dev/null
    sleep 0.1
  done
  
  # Remove all lock files
  log_info "Removing lock files..."
  rm -f /tmp/erase-install-wrapper-main.lock 2>/dev/null
  rm -f /var/run/erase-install-wrapper.lock 2>/dev/null
  
  # Clean up any potentially open file descriptors
  for fd in {200..210}; do
    eval "exec $fd>&-" 2>/dev/null
  done
  
  # Remove all watchdog scripts
  log_info "Removing watchdog scripts..."
  rm -f /Library/Management/erase-install/erase-install-watchdog-*.sh 2>/dev/null
  
  # Clean up any remaining LaunchDaemons
  log_info "Cleaning up LaunchDaemons..."
  emergency_daemon_cleanup
  
  log_info "Emergency cleanup completed"
  exit 0
fi

if [[ "$1" == "--scheduled" ]]; then
  # Initialize logging first
  init_logging
  log_info "Starting scheduled installation process (PID: $$)"
  
  # Check if OS is already updated before running installation
  log_info "Checking if OS is already at or above target version..."
  if [[ "${SKIP_OS_VERSION_CHECK}" == "true" ]]; then
    log_info "SKIP_OS_VERSION_CHECK is enabled - testing but continuing regardless of OS version"
    test_deferral_os_check
  elif check_if_os_upgraded_during_deferral; then
    log_info "OS already updated to target version or newer. No need to install. Exiting."
    cleanup_and_exit
    exit 0
  fi
  
  # Define cleanup function
  cleanup_and_exit() {
    local exit_code=$?
    log_info "Cleaning up scheduled installation process"
    
    # Kill any lingering watchdog processes
    kill_lingering_watchdogs
    
    # Try to remove LaunchDaemon multiple times if needed
    local retries=3
    while [ $retries -gt 0 ]; do
      if remove_existing_launchdaemon; then
        break
      fi
      retries=$((retries - 1))
      [ $retries -gt 0 ] && sleep 1
    done
    
    log_info "Scheduled installation process completed (exit code: $exit_code)"
    exit $exit_code
  }
  
  if [[ "$1" == "--clean-locks" ]]; then
    init_logging
    log_info "Manual lock cleanup requested"
    
    # Clean up lock files
    for lock_file in "/tmp/erase-install-wrapper-main.lock" "/var/run/erase-install-wrapper.lock"; do
      if [ -f "$lock_file" ]; then
        log_info "Removing lock file: $lock_file"
        rm -f "$lock_file"
      else
        log_info "No lock file found at: $lock_file"
      fi
    done
    
    log_info "Lock cleanup completed"
    exit 0
  fi
  
  # Set up trap immediately
  trap 'cleanup_and_exit' EXIT TERM INT
  
  # Set up locking
  if [[ $EUID -eq 0 ]]; then
    # Running as root
    LOCK_DIR="/var/run"
  else
    # Running as regular user
    LOCK_DIR="/tmp"
  fi
  LOCK_FILE="${LOCK_DIR}/erase-install-wrapper.lock"
  
  # Kill any lingering watchdog processes first
  kill_lingering_watchdogs
  
  # Try to acquire lock with a 60-second timeout
  if ! acquire_lock "$LOCK_FILE" 30 false; then
    log_warn "Unable to acquire lock normally. Checking for stale locks..."
    
    if ! acquire_lock "$LOCK_FILE" 5 true; then
      log_error "Still unable to acquire lock. Another instance may be running. Exiting."
      exit 1
    else
      log_warn "Lock acquired after force-break."
    fi
  fi
  
  # Set up trap to release lock on exit
  trap 'release_lock; cleanup_and_exit' EXIT TERM INT  
  
  # Ensure cleanup on exit - trap is already set up above
  
  log_system_info
  
  # Verify dependencies before proceeding
  if ! dependency_check; then
    log_error "Failed dependency check"
    exit 1
  fi
  
  # Remove any existing LaunchDaemons
  remove_existing_launchdaemon
  
  # Initialize the environment for the scheduled run
  init_plist
  
  log_info "Starting user detection for scheduled run"

  # Get current console user info for UI display - enhanced for robustness
  local console_user=""
  console_user=$(get_console_user)
  log_info "Detected console user: '$console_user'"
  local console_uid
  console_uid=$(id -u "$console_user")
  log_info "User UID: $console_uid"
  
  # Set environment variables for UI
  export DISPLAY=:0
  
  # Run dialog as user with proper environment - enhanced for visibility
  log_info "Displaying scheduled installation dialog for user: $console_user"
  log_info "About to display dialogs for user: '$console_user' with UID: $console_uid"
  
  # First, try a simple notification to alert the user
  log_debug "Attempting AppleScript notification"
  launchctl asuser "$console_uid" sudo -u "$console_user" osascript -e "
    tell application \"System Events\"
      activate
      display dialog \"${SCHEDULED_TITLE}\" buttons {\"OK\"} default button \"OK\" with title \"$PREINSTALL_TITLE\" with icon note giving up after 5
    end tell
  " 2>&1 | log_debug "AppleScript result: $(cat -)" || log_debug "AppleScript notification failed"
  
  # SECURITY FIX (Issue #23): Create temporary script for dialog display using secure temp dir
  log_debug "Creating temporary script for dialog display"
  TMP_DIR=$(create_secure_temp_dir "scheduled-dialog") || {
    log_error "Failed to create secure temp directory for dialog script"
    return 1
  }
  TMP_DIALOG_SCRIPT="$TMP_DIR/dialog_display.sh"
  
  # Create the script with all variables expanded now
  cat > "$TMP_DIALOG_SCRIPT" << EOF
#!/bin/bash
export DISPLAY=:0
export PATH='/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'

# Force activation of UI layer first
/usr/bin/osascript -e 'tell application "Finder" to activate' &
/usr/bin/osascript -e 'tell application "System Events" to activate' &
sleep 1

# Store dialog path and confirm it exists
DIALOG_PATH="${DIALOG_BIN}"
if [ ! -x "\${DIALOG_PATH}" ]; then
  echo "Error: SwiftDialog not found at \${DIALOG_PATH}" >&2
  exit 1
fi

echo "Running SwiftDialog from: \${DIALOG_PATH}"
echo "With parameters:"
echo "  Title: ${PREINSTALL_TITLE}"
echo "  Message: ${PREINSTALL_MESSAGE}"

# Run dialog with proper focus
"\${DIALOG_PATH}" --title "${PREINSTALL_TITLE}" \\
  --message "${PREINSTALL_MESSAGE}" \\
  --button1text "${PREINSTALL_CONTINUE_TEXT}" \\
  --icon "${DIALOG_ICON}" \\
  --height ${PREINSTALL_HEIGHT} \\
  --width ${PREINSTALL_WIDTH} \\
  --messagefont ${PREINSTALL_DIALOG_MESSAGEFONT} \\
  --moveable \\
  --ontop \\
  --forefront \\
  --position "${DIALOG_POSITION}" \\
  --progress ${PREINSTALL_COUNTDOWN} \\
  --progresstext "${PREINSTALL_PROGRESS_TEXT_MESSAGE}" \\
  --timer ${PREINSTALL_COUNTDOWN} 
EOF
  
  # Make script executable and set proper ownership
  chmod +x "$TMP_DIALOG_SCRIPT"
  chown "$console_user" "$TMP_DIALOG_SCRIPT"
  
  # Run as the console user with proper environment 
  log_info "Launching dialog script as $console_user"
  launchctl asuser "$console_uid" sudo -u "$console_user" "$TMP_DIALOG_SCRIPT" > /tmp/dialog_output.log 2>&1
  
  # Log the results
  log_debug "Dialog exit status: $?"
  [ -f /tmp/dialog_output.log ] && log_debug "Dialog output: $(cat /tmp/dialog_output.log)"
  
  # Clean up
  rm -rf "$TMP_DIR"
  rm -f /tmp/dialog_output.log
  
  sleep 2  # Brief pause to ensure dialog is displayed
  
  # Run the actual installation
  log_info "Starting installation process"
  
  # Check if OS is already updated before running installation
  log_info "Checking if OS is already at or above target version..."
  if [[ "${SKIP_OS_VERSION_CHECK}" == "true" ]]; then
    log_info "SKIP_OS_VERSION_CHECK is enabled - testing but continuing regardless of OS version"
    test_deferral_os_check
  elif check_if_os_upgraded_during_deferral; then
    log_info "OS already updated to target version or newer. No need to install. Exiting."
    cleanup_and_exit
    exit 0
  fi
  
  # OS needs update, proceed with installation
  log_info "OS needs to be updated. Starting installation process"
  
  # When running from LaunchDaemon (as root), we can run erase-install directly
  if [[ $EUID -eq 0 ]]; then
    log_info "Running erase-install as root"
    
    # Build command properly
    local cmd_args=()
    cmd_args+=("${SCRIPT_PATH}")
    
    # Add options based on configuration
    cmd_args+=("--reinstall")
    
    if [[ "$REBOOT_DELAY" -gt 0 ]]; then
      cmd_args+=("--rebootdelay" "$REBOOT_DELAY")
    fi
    
    if [[ "$NO_FS" == "true" ]]; then
      cmd_args+=("--no-fs")
    fi
    
    if [[ "$CHECK_POWER" == "true" ]]; then
      cmd_args+=("--check-power")
      
      if [[ "$POWER_WAIT_LIMIT" -gt 0 ]]; then
        cmd_args+=("--power-wait-limit" "$POWER_WAIT_LIMIT")
      fi
    fi
    
    cmd_args+=("--min-drive-space" "$MIN_DRIVE_SPACE")
    
    if [[ "$CLEANUP_AFTER_USE" == "true" ]]; then
      cmd_args+=("--cleanup-after-use")
    fi
    
    if [[ "$TEST_MODE" == "true" ]]; then
      cmd_args+=("--test-run")
    fi
    
    if [[ "$PREVENT_ALL_REBOOTS" == "true" ]]; then
      cmd_args+=("--no-reboot")
    fi
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
      cmd_args+=("--verbose")
    fi
    
    # Log the command
    log_info "Executing erase-install with arguments: ${cmd_args[*]}"
    
    # Execute the command
    "${cmd_args[@]}"
  else
    # When running as user, we need to use the normal run_erase_install function
    log_info "Running erase-install via run_erase_install function"
    run_erase_install
  fi
  
  # Explicitly call cleanup to ensure proper exit
  cleanup_and_exit
fi

########################################################################################################################################################################
#
#--------------------- MAIN -------------------------------
#
########################################################################################################################################################################

# Enhanced function to detect if the script is being run by an abort daemon
is_running_from_abort_daemon() {
  # Check our early detection flag first (most reliable)
  if [[ "$RUNNING_FROM_ABORT_DAEMON" == "true" ]]; then
    return 0
  fi
  
  # Check environment variable (set by LaunchDaemon)
  if [[ "${ERASE_INSTALL_ABORT_DAEMON:-}" == "true" ]]; then
    log_debug "Detected abort daemon via environment variable"
    export RUNNING_FROM_ABORT_DAEMON=true
    return 0
  fi
  
  # Check command line arguments
  for arg in "$@"; do
    if [[ "$arg" == "--from-abort-daemon" ]]; then
      log_debug "Detected abort daemon via command line argument"
      export RUNNING_FROM_ABORT_DAEMON=true
      return 0
    fi
  done
  
  # Check parent process command line
  if [ -n "$PPID" ]; then
    local parent_cmd=$(ps -o command= -p "$PPID" 2>/dev/null || echo "")
    if [[ "$parent_cmd" == *"com.macjediwizard.eraseinstall.abort"* ]]; then
      log_debug "Detected abort daemon via parent process: $parent_cmd"
      export RUNNING_FROM_ABORT_DAEMON=true
      return 0
    fi
  fi
  
  # Fallback: check for abort daemon text files if plist failed
  local current_run_id=$(date +%Y%m%d%H%M%S)
  # Try to find any recent abort daemon files
  for abort_file in /var/tmp/active-abort-daemon-*.txt; do
    if [ -f "$abort_file" ]; then
      local saved_daemon=$(cat "$abort_file" 2>/dev/null)
      if [[ -n "$saved_daemon" ]]; then
        log_debug "Found abort daemon via fallback file: $saved_daemon"
        export RUNNING_FROM_ABORT_DAEMON=true
        return 0
      fi
    fi
  done
  
  # Check if any abort daemon is currently loaded that might be our parent
  local active_abort_daemons=$(launchctl list | grep "com.macjediwizard.eraseinstall.abort" | awk '{print $3}')
  if [ -n "$active_abort_daemons" ]; then
    log_debug "Found active abort daemons in launchctl, assuming we're from one"
    export RUNNING_FROM_ABORT_DAEMON=true
    return 0
  fi
  
  return 1
}
        
is_running_from_relaunch_daemon() {
  # Check environment variable first
  if [[ "${RUNNING_FROM_RELAUNCH_DAEMON:-}" == "true" ]]; then
    log_debug "Detected running from relaunch daemon via environment variable"
    return 0  # True - environment indicates we're from relaunch daemon
  fi
  
  # Check command line arguments for relaunch flag
  for arg in "$@"; do
    if [[ "$arg" == "--from-relaunch-daemon" ]]; then
      log_debug "Detected running from relaunch daemon via command line argument"
      return 0  # True - explicit command line flag
    fi
  done
  
  # Check if parent process has "relaunch" in its command line
  local parent_cmd=""
  if [ -n "$PPID" ]; then
    parent_cmd=$(ps -o command= -p "$PPID" 2>/dev/null || echo "")
    if [[ "$parent_cmd" == *"com.macjediwizard.eraseinstall.relaunch"* ]]; then
      log_debug "Detected running from relaunch daemon via parent process: $parent_cmd"
      export RUNNING_FROM_RELAUNCH_DAEMON=true
      return 0  # True - running from relaunch daemon
    fi
  fi
  
  # Not running from relaunch daemon
  return 1
}

# ========================================
# Command-line Argument Processing (v2.0)
# ========================================

# Parse command-line arguments before initialization
CUSTOM_CONFIG_PATH=""
SHOW_CONFIG_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --config=*)
      CUSTOM_CONFIG_PATH="${arg#*=}"
      ;;
    --show-config)
      SHOW_CONFIG_ONLY=true
      ;;
    --test-os-check)
      SKIP_OS_VERSION_CHECK=true
      ;;
    --version)
      echo "erase-install-defer-wrapper v${SCRIPT_VERSION}"
      echo "JSON Configuration Management for macOS Upgrade Automation"
      echo ""
      echo "GitHub: https://github.com/MacJediWizard/Jamf-Silent-macOS-Upgrade-Scheduler"
      echo "Made with ❤️ by MacJediWizard Consulting, Inc."
      exit 0
      ;;
    --help|-h)
      echo "erase-install-defer-wrapper v${SCRIPT_VERSION}"
      echo "JSON Configuration Management for macOS Upgrade Automation"
      echo ""
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --show-config              Display current configuration and exit"
      echo "  --config=/path/to/file     Use custom JSON configuration file"
      echo "  --test-os-check            Skip OS version check (for testing)"
      echo "  --version                  Display version information and exit"
      echo "  --help, -h                 Display this help message and exit"
      echo ""
      echo "Configuration Priority (Highest to Lowest):"
      echo "  1. Custom JSON (--config parameter)"
      echo "  2. Managed JSON (/Library/Managed Preferences/...)"
      echo "  3. Local JSON (/Library/Preferences/...)"
      echo "  4. Script Defaults"
      echo ""
      echo "Examples:"
      echo "  $0 --show-config"
      echo "  $0 --config=/tmp/test-config.json"
      echo "  $0 --config=/tmp/qa.json --test-os-check"
      echo ""
      echo "Documentation: https://github.com/MacJediWizard/Jamf-Silent-macOS-Upgrade-Scheduler"
      exit 0
      ;;
  esac
done

# Main script execution for non-scheduled mode
init_logging

# Load JSON configuration (v2.0) - overrides User Configuration Section if JSON exists
load_json_config

log_info "Starting erase-install wrapper script v${SCRIPT_VERSION}"
log_info "Configuration source: $([ -f "/Library/Managed Preferences/com.macjediwizard.eraseinstall.config.json" ] && echo "Managed JSON (Jamf)" || [ -f "/Library/Preferences/com.macjediwizard.eraseinstall.config.json" ] && echo "Local JSON" || echo "Script Defaults")"

# Handle --show-config command
if [[ "$SHOW_CONFIG_ONLY" == "true" ]]; then
  echo ""
  echo "=== Current Configuration ==="
  echo "Configuration Source: $([ -f "/Library/Managed Preferences/com.macjediwizard.eraseinstall.config.json" ] && echo "Managed JSON (Jamf)" || [ -f "/Library/Preferences/com.macjediwizard.eraseinstall.config.json" ] && echo "Local JSON" || echo "Script Defaults")"
  echo ""
  echo "Core Settings:"
  echo "  SCRIPT_VERSION: ${SCRIPT_VERSION}"
  echo "  INSTALLER_OS: ${INSTALLER_OS}"
  echo "  MAX_DEFERS: ${MAX_DEFERS}"
  echo "  MAX_ABORTS: ${MAX_ABORTS}"
  echo "  FORCE_TIMEOUT_SECONDS: ${FORCE_TIMEOUT_SECONDS}"
  echo ""
  echo "Feature Toggles:"
  echo "  TEST_MODE: ${TEST_MODE}"
  echo "  PREVENT_ALL_REBOOTS: ${PREVENT_ALL_REBOOTS}"
  echo "  SKIP_OS_VERSION_CHECK: ${SKIP_OS_VERSION_CHECK}"
  echo "  AUTO_INSTALL_DEPENDENCIES: ${AUTO_INSTALL_DEPENDENCIES}"
  echo "  DEBUG_MODE: ${DEBUG_MODE}"
  echo ""
  echo "File Paths:"
  echo "  SCRIPT_PATH: ${SCRIPT_PATH}"
  echo "  DIALOG_BIN: ${DIALOG_BIN}"
  echo "  PLIST: ${PLIST}"
  echo ""
  echo "Dialog Settings:"
  echo "  DIALOG_TITLE: ${DIALOG_TITLE}"
  echo "  DIALOG_POSITION: ${DIALOG_POSITION}"
  echo "  DIALOG_ICON: ${DIALOG_ICON}"
  echo ""
  echo "erase-install Options:"
  echo "  REINSTALL: ${REINSTALL}"
  echo "  CHECK_POWER: ${CHECK_POWER}"
  echo "  POWER_WAIT_LIMIT: ${POWER_WAIT_LIMIT}"
  echo "  MIN_DRIVE_SPACE: ${MIN_DRIVE_SPACE}"
  echo ""
  exit 0
fi

log_system_info

# Detect if running from abort daemon
RUNNING_FROM_ABORT_DAEMON=false
if is_running_from_abort_daemon "$@"; then
  RUNNING_FROM_ABORT_DAEMON=true
  log_info "DETECTED: Script is running from an abort daemon - will preserve abort daemon during cleanup"
else
  log_info "Script is running in normal mode - not from abort daemon"
fi

# Add emergency cleanup (with abort daemon awareness)
if [[ "$RUNNING_FROM_ABORT_DAEMON" == "true" ]]; then
  log_info "ABORT MODE: Performing selective emergency cleanup (preserving parent abort daemon)"
  # Only clean up non-abort daemons when running from abort daemon
  # Future enhancement: Add selective cleanup that preserves the parent abort daemon
else
  log_info "Performing normal emergency cleanup of all LaunchDaemons"
  emergency_daemon_cleanup
fi

# Kill any lingering watchdog processes
kill_lingering_watchdogs

# Set up locking for main script execution
LOCK_FILE="/tmp/erase-install-wrapper-main.lock"

# First try to acquire lock normally
if ! acquire_lock "$LOCK_FILE" 15 false; then
  log_warn "Unable to acquire lock normally. Attempting one more time with force-break..."
  
  # Try again with force-break
  if ! acquire_lock "$LOCK_FILE" 5 true; then
    log_error "Still unable to acquire lock after force-break attempt. Exiting."
    exit 1
  else
    log_warn "Lock acquired after force-break."
  fi
fi

# Set up trap to release lock on exit
trap 'release_lock' EXIT TERM INT

# Check for dependencies
if ! dependency_check; then
  log_error "Required dependencies are missing. Exiting."
  exit 1
fi

# Initialize plist for deferral tracking
init_plist

# Initialize installation state variables early
log_info "Initializing installation state variables..."
get_installation_state

# Verify critical variables are set
if [[ -z "$CURRENT_DEFER_COUNT" ]]; then
  log_error "Failed to initialize CURRENT_DEFER_COUNT - setting to 0"
  export CURRENT_DEFER_COUNT=0
fi

if [[ -z "$FORCE_INSTALL" ]]; then
  log_error "Failed to initialize FORCE_INSTALL - setting to false"
  export FORCE_INSTALL=false
fi

if [[ -z "$CAN_DEFER" ]]; then
  log_error "Failed to initialize CAN_DEFER - setting to true"
  export CAN_DEFER=true
fi

log_debug "State variables initialized: DEFER_COUNT=$CURRENT_DEFER_COUNT, FORCE_INSTALL=$FORCE_INSTALL, CAN_DEFER=$CAN_DEFER"

# Check if system is already running the target OS version
log_info "Performing early OS version check..."
if [[ "${SKIP_OS_VERSION_CHECK}" == "true" ]]; then
  log_info "SKIP_OS_VERSION_CHECK is enabled - running test mode but continuing regardless of OS version"
  test_os_version_check
  # Always continue when in test mode
elif check_os_already_updated; then
  log_info "System is already running the target OS version. No update needed."
  
  # Show a notification to the user
  console_user=""
  console_user=$(get_console_user)
  
  if [ -n "$console_user" ] && [ "$console_user" != "root" ]; then
    console_uid=""
    console_uid=$(id -u "$console_user" 2>/dev/null || echo "")
    if [ -n "$console_uid" ]; then
      launchctl asuser "$console_uid" sudo -u "$console_user" osascript -e 'display notification "Your macOS is already up to date. No update required." with title "macOS Upgrade"'
    fi
  fi
  
  # Clean up any resources
  remove_existing_launchdaemon
  
  log_info "Exiting script as no update is needed."
  exit 0
fi

# Get current deferral state
get_installation_state

# Set options based on deferral state
set_options

# Show prompt and handle user selection
if ! show_prompt; then
  log_error "User prompt failed or was dismissed. Exiting."
  exit 1
fi

# Call this function at the very end of your main script
log_info "Verifying Complete System Cleanup"
verify_complete_system_cleanup

log_info "Script completed successfully"
exit 0