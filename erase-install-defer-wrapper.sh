#!/bin/bash

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
SCRIPT_VERSION="1.6.1"              # Current version of this script
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
TEST_MODE=true                      # Set to false for production (when true, deferrals are shortened to 5 minutes)
PREVENT_ALL_REBOOTS=true            # SAFETY FEATURE: Set to true to prevent any reboots during testing
SKIP_OS_VERSION_CHECK=true         # Set to true to skip OS version checking for testing purposes
AUTO_INSTALL_DEPENDENCIES=true      # Automatically install erase-install and SwiftDialog if missing
DEBUG_MODE=true                     # Enable detailed logging
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
AUTH_NOTICE_TIMEOUT=120                    # Timeout in seconds (0 = no timeout)
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
  
  # Set appropriate permissions
  if [[ -f "${WRAPPER_LOG}" ]]; then
    chmod 644 "${WRAPPER_LOG}" 2>/dev/null
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
  
  # Get console user for proper UI handling
  local console_user=""
  console_user=$(stat -f%Su /dev/console 2>/dev/null || echo "")
  [ -z "$console_user" ] && console_user=$(who | grep "console" | awk '{print $1}' | head -n1)
  [ -z "$console_user" ] && console_user=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && !/loginwindow/ { print $3 }')
  local console_uid
  console_uid=$(id -u "$console_user" 2>/dev/null || echo "0")
  
  # Set UI environment for the console user
  export DISPLAY=:0
  if [ -n "$console_uid" ] && [ "$console_uid" != "0" ]; then
    launchctl asuser "$console_uid" sudo -u "$console_user" defaults write org.swift.SwiftDialog FrontmostApplication -bool true
  fi
  
  # For test mode, use a modified title
  local display_title="$AUTH_NOTICE_TITLE"
  [[ "$TEST_MODE" = true ]] && display_title="${AUTH_NOTICE_TITLE_TEST_MODE}"
  
  # Prepare timeout parameters
  local timeout_args=""
  if [[ $AUTH_NOTICE_TIMEOUT -gt 0 ]]; then
    timeout_args="--timer $AUTH_NOTICE_TIMEOUT"
  fi
  
  # Display the dialog
  "$DIALOG_BIN" --title "$display_title" \
  --message "$AUTH_NOTICE_MESSAGE" \
  --button1text "$AUTH_NOTICE_BUTTON" \
  --icon "$AUTH_NOTICE_ICON" \
  --height $AUTH_NOTICE_HEIGHT \
  --width $AUTH_NOTICE_WIDTH \
  --moveable \
  --position "$DIALOG_POSITION" \
  $timeout_args
  
  local result=$?
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
  
  # Create a temporary directory
  local tmp; tmp=$(mktemp -d)
  if [[ ! -d "${tmp}" ]]; then
    log_error "Failed to create temporary directory for download."
    return 1
  fi
  
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
        local file_size=$(stat -f%z "${pkg_path}" 2>/dev/null || echo "0")
        log_info "Downloaded file size: ${file_size} bytes"
        
        if [[ ${file_size} -gt 1000000 ]]; then
          log_info "Package download successful and verified."
          download_success=true
        else
          log_warn "Downloaded file is too small (${file_size} bytes) - likely not a valid package."
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
        log_info "Downloaded file size: ${file_size} bytes"
        
        if [[ ${file_size} -gt 1000000 ]]; then
          log_info "Package download successful and verified from: ${url}"
          download_success=true
          break
        else
          log_warn "Downloaded file from ${url} is too small (${file_size} bytes) - likely not a valid package."
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
        log_info "Downloaded file size: ${file_size} bytes"
        
        if [[ ${file_size} -gt 1000000 ]]; then
          log_info "Package download successful and verified from: ${url}"
          download_success=true
          break
        else
          log_warn "Downloaded file from ${url} is too small (${file_size} bytes) - likely not a valid package."
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
        local file_size=$(stat -f%z "${pkg_path}" 2>/dev/null || echo "0")
        log_info "Downloaded file size: ${file_size} bytes"
        
        if [[ ${file_size} -gt 1000000 ]]; then
          log_info "Package download successful and verified."
          download_success=true
        else
          log_warn "Downloaded file is too small (${file_size} bytes) - likely not a valid package."
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
        log_info "Downloaded file size: ${file_size} bytes"
        
        if [[ ${file_size} -gt 1000000 ]]; then
          log_info "Package download successful and verified from: ${url}"
          download_success=true
          break
        else
          log_warn "Downloaded file from ${url} is too small (${file_size} bytes) - likely not a valid package."
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
        log_info "Downloaded file size: ${file_size} bytes"
        
        if [[ ${file_size} -gt 1000000 ]]; then
          log_info "Package download successful and verified from: ${url}"
          download_success=true
          break
        else
          log_warn "Downloaded file from ${url} is too small (${file_size} bytes) - likely not a valid package."
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
  
  # Run erase-install with list-only flag
  log_info "Running erase-install in list-only mode..." >&2
  "${SCRIPT_PATH}" --list-only > "$tmp_file" 2>&1
  
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
      
      # Extract the latest macOS version
      available_version=$(/usr/bin/plutil -extract "OSVersions.0.Latest.ProductVersion" raw "$json_cache" 2>/dev/null | head -n 1)
      
      if [[ -z "$available_version" ]]; then
        # Try the latestProductionVersion as a fallback
        log_info "Trying latestProductionVersion as a fallback" >&2
        available_version=$(/usr/bin/plutil -extract "latestProductionVersion" raw "$json_cache" 2>/dev/null | head -n 1)
      fi
      
      if [[ -n "$available_version" ]]; then
        log_info "Successfully extracted version from SOFA: $available_version" >&2
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

# ---------------- Deferral State ----------------

init_plist() {
  if [[ ! -f "${PLIST}" ]]; then
    defaults write "${PLIST}" scriptVersion -string "${SCRIPT_VERSION}"
    defaults write "${PLIST}" deferCount -int 0
    defaults write "${PLIST}" firstPromptDate -string "$(date -u +%s)"
    
    # Add initial OS version and target version info
    local current_os=$(sw_vers -productVersion)
    defaults write "${PLIST}" initialOSVersion -string "${current_os}"
    
    # Use erase-install to determine available version
    local available_version
    available_version=$(get_available_macos_version)
    defaults write "${PLIST}" targetOSVersion -string "${available_version}"
    
    log_info "Stored initial OS: $current_os and target OS: $available_version"
  else
    local ver; ver=$(defaults read "${PLIST}" scriptVersion 2>/dev/null || echo "")
    if [[ "${ver}" != "${SCRIPT_VERSION}" ]]; then
      log_info "New version detected; resetting deferral history."
      defaults write "${PLIST}" scriptVersion -string "${SCRIPT_VERSION}"
      defaults write "${PLIST}" deferCount -int 0
      defaults write "${PLIST}" firstPromptDate -string "$(date -u +%s)"
      
      # Reset OS version info
      local current_os=$(sw_vers -productVersion)
      defaults write "${PLIST}" initialOSVersion -string "${current_os}"
      
      # Use erase-install to determine available version
      local available_version
      available_version=$(get_available_macos_version)
      defaults write "${PLIST}" targetOSVersion -string "${available_version}"
      
      log_info "Updated initial OS: $current_os and target OS: $available_version"
    fi
  fi
  
  defaults read "${PLIST}" deferCount &>/dev/null || defaults write "${PLIST}" deferCount -int 0
  defaults read "${PLIST}" firstPromptDate &>/dev/null || defaults write "${PLIST}" firstPromptDate -string "$(date -u +%s)"
  defaults read "${PLIST}" initialOSVersion &>/dev/null || defaults write "${PLIST}" initialOSVersion -string "$(sw_vers -productVersion)"
  defaults read "${PLIST}" abortCount &>/dev/null || defaults write "${PLIST}" abortCount -int 0
  
  # Make sure we have target version
  if ! defaults read "${PLIST}" targetOSVersion &>/dev/null; then
    # Use erase-install to determine available version
    local available_version
    available_version=$(get_available_macos_version)
    defaults write "${PLIST}" targetOSVersion -string "${available_version}"
    log_info "Added missing target OS version: $available_version"
  fi
}

reset_deferrals() {
  log_info "Resetting deferral count."
  defaults write "${PLIST}" deferCount -int 0
  defaults write "${PLIST}" firstPromptDate -string "$(date -u +%s)"
  defaults write "${PLIST}" abortCount -int 0  # Add this line
  log_info "Deferral and abort counts reset."
}

get_deferral_state() {
  deferCount=$(defaults read "${PLIST}" deferCount 2>/dev/null || echo 0)
  firstDate=$(defaults read "${PLIST}" firstPromptDate 2>/dev/null || echo 0)
  local now; now=$(date -u +%s)
  local elapsed=$((now - firstDate))
  log_debug "deferCount=${deferCount}, elapsed=${elapsed}s, MAX_DEFERS=${MAX_DEFERS}"
  DEFERRAL_EXCEEDED=false
  if (( deferCount >= MAX_DEFERS )) || (( elapsed >= FORCE_TIMEOUT_SECONDS )); then
    DEFERRAL_EXCEEDED=true
    log_info "Deferral limit exceeded: count=${deferCount}/${MAX_DEFERS}, elapsed=${elapsed}s/${FORCE_TIMEOUT_SECONDS}s"
  else
    log_debug "Deferral limit not exceeded: count=${deferCount}/${MAX_DEFERS}, elapsed=${elapsed}s/${FORCE_TIMEOUT_SECONDS}s"
  fi
}

# ---------------- LaunchDaemon ----------------

# Function to safely remove all LaunchDaemons
remove_existing_launchdaemon() {
  log_info "Checking for existing LaunchDaemons to remove..."
  local found_count=0
  local removed_count=0
  local is_scheduled=false
  local preserve_parent_daemon=""
  local preserve_abort_daemon=false
  
  # Parse the arguments
  for arg in "$@"; do
    case "$arg" in
      --preserve-scheduled)
        is_scheduled=true
        ;;
      --preserve-parent=*)
        preserve_parent_daemon="${arg#*=}"
        log_info "Will preserve parent daemon: $preserve_parent_daemon during cleanup"
        ;;
      --preserve-abort-daemon)
        preserve_abort_daemon=true
        log_info "Will preserve all abort daemons during cleanup"
        ;;
    esac
  done
  
  # First forcefully remove lingering entries from launchctl
  for label in $(launchctl list 2>/dev/null | grep -E "com.macjediwizard.eraseinstall|com.github.grahampugh.erase-install" | awk '{print $3}'); do
    if [ -n "$label" ]; then
      # Skip if this is our parent daemon that we want to preserve
      if [[ -n "$preserve_parent_daemon" && "$label" == "$preserve_parent_daemon" ]]; then
        log_info "Skipping removal of parent daemon: $label"
        continue
      fi
      
      # Skip if this is an abort daemon and we're preserving abort daemons
      if [[ "$preserve_abort_daemon" == "true" && "$label" == *".abort."* ]]; then
        log_info "Skipping removal of abort daemon: $label"
        continue
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
          log_info "Force removing lingering agent for user $user: $label"
          launchctl asuser "$user_id" launchctl remove "$label" 2>/dev/null || log_warn "Failed to remove: $label"
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
    echo "${loaded_daemons}" | while IFS= read -r label; do
      [ -z "${label}" ] && continue
      
      # Skip scheduled daemons if we're preserving them
      if [[ "${is_scheduled}" == "true" ]] && sudo launchctl list "${label}" 2>/dev/null | grep -q -- "--scheduled"; then
        log_info "Preserving scheduled daemon: ${label}"
        continue
      fi
      
      # Skip abort daemons if we're preserving them
      if [[ "$preserve_abort_daemon" == "true" && "${label}" == *".abort."* ]]; then
        log_info "Preserving abort daemon: ${label}"
        continue
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
    done
  else
    log_debug "No loaded daemons found"
  fi
  
  # Find and remove ALL matching plist files, even if not loaded
  while IFS= read -r file; do
    [ -z "${file}" ] && continue
    
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
  sudo rm -f "/Library/Management/erase-install/erase-install-watchdog*.sh" 2>/dev/null
  for user in $(ls /Users); do
    sudo -u "$user" rm -f "/Users/$user/Library/Application Support/erase-install-helper*.sh" 2>/dev/null
  done
  
  # Clean up trigger files
  sudo rm -f /var/tmp/erase-install-trigger* 2>/dev/null
  
  # Clean up any control files left by erase-install
  sudo rm -f /var/tmp/dialog.* 2>/dev/null
  
  # Final explicit check for any remaining files - use find directly
  log_info "Performing final deep cleanup check for any remaining files"
  for plist in $(sudo find /Library/LaunchDaemons -name "*eraseinstall*.plist" -o -name "*erase-install*.plist" 2>/dev/null); do
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
    # Force unload all remaining items
    for label in $(launchctl list 2>/dev/null | grep -E "com.macjediwizard.eraseinstall|com.github.grahampugh.erase-install" | awk '{print $3}'); do
      log_info "Final attempt to remove daemon: $label"
      sudo launchctl remove "$label" 2>/dev/null
    done
  fi
  
  # One final check for the problematic daemons using wildcard patterns
  for problematic_pattern in "/Library/LaunchDaemons/com.github.grahampugh.erase-install.*.plist" "/Library/LaunchDaemons/com.macjediwizard.eraseinstall.*.plist"; do
    for daemon in $(ls $problematic_pattern 2>/dev/null); do
      if [ -f "$daemon" ]; then
        log_warn "Critical: Found problematic daemon after cleanup: $daemon"
        # Get the label from the filename
        local daemon_label=$(basename "$daemon" .plist)
        # Try to unload it
        sudo launchctl remove "$daemon_label" 2>/dev/null
        # Then remove the file
        sudo rm -f "$daemon" && log_info "Forcefully removed: $daemon" || log_error "FAILED to forcefully remove: $daemon"
      fi
    done
  done
  
  # Verify cleanup
  if [ -f "${LAUNCHDAEMON_PATH}" ] || [ -f "${LAUNCHDAEMON_PATH}.bak" ] || [ -f "/Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist" ]; then
    log_error "LaunchDaemon cleanup incomplete - files still exist"
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
  
  # Check if this is a silent deferral (should not show UI)
  local show_ui=true
  if [[ "$mode" == "defer" ]]; then
    show_ui=false
    log_info "Creating defer-type silent schedule for $(printf '%02d:%02d' ${hour_num} ${minute_num}) (no UI will be shown)"
  else
    log_info "Creating ${mode}-type schedule with UI for $(printf '%02d:%02d' ${hour_num} ${minute_num})"
  fi
  
  # Set the global variable for other functions to access
  CURRENT_RUN_ID="$run_id"
  
  # Debug info
  [[ "${DEBUG_MODE}" = true ]] && log_debug "Creating scheduled items for ${hour_num}:${minute_num} with test_mode=${TEST_MODE}, debug_mode=${DEBUG_MODE}"
  
  # Create a shared trigger file that will connect the UI and installation processes
  local trigger_file="/var/tmp/erase-install-trigger-${run_id}"
  
  # Get console user for UI references
  local console_user=""
  console_user=$(stat -f%Su /dev/console 2>/dev/null || echo "")
  [ -z "$console_user" ] && console_user=$(who | grep "console" | awk '{print $1}' | head -n1)
  [ -z "$console_user" ] && console_user=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && !/loginwindow/ { print $3 }')
  
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
  if [[ "$mode" == "scheduled" && "${ENABLE_ABORT_BUTTON}" == "true" ]]; then
    # Check current abort count
    local abort_count=$(defaults read "${PLIST}" abortCount 2>/dev/null || echo 0)
    if [[ $abort_count -lt $MAX_ABORTS ]]; then
      # Don't use a variable for this part - insert directly into the helper script below
      log_info "Adding abort button to dialog (abort count: ${abort_count}/${MAX_ABORTS})"
      local USE_ABORT_BUTTON=true
    else
      log_info "Maximum aborts reached (${abort_count}/${MAX_ABORTS}) - not showing abort button"
      local USE_ABORT_BUTTON=false
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

# Display dialog with countdown - enhanced for visibility
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
  --commandfile "/var/tmp/dialog-cmd-${run_id}"

DIALOG_RESULT=\$?
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Dialog completed with status: \$DIALOG_RESULT" >> "\$LOG_FILE"

# Check if abort was clicked (dialog result = 2)
if [ \$DIALOG_RESULT -eq 2 ]; then
  echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Abort button was clicked" >> "\$LOG_FILE"
  # Create abort file for watchdog to detect
  touch "/var/tmp/erase-install-abort-${run_id}"
  echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Created abort signal file at: /var/tmp/erase-install-abort-${run_id}" >> "\$LOG_FILE"
  
  # Verify the abort file was created
  if [ -f "/var/tmp/erase-install-abort-${run_id}" ]; then
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Abort signal file verified" >> "\$LOG_FILE"
  else
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to create abort signal file" >> "\$LOG_FILE"
    # Try again with sudo
    sudo touch "/var/tmp/erase-install-abort-${run_id}" 2>/dev/null
  fi
  
  # Show abort countdown dialog
  "${DIALOG_BIN}" --title "Aborting Installation" \\
    --message "Emergency abort activated. Installation will be postponed for ${ABORT_DEFER_MINUTES} minutes." \\
    --icon ${ABORT_ICON} \\
    --button1text "OK" \\
    --timer ${ABORT_COUNTDOWN} \\
    --progress ${ABORT_COUNTDOWN} \\
    --progresstext "Aborting in \${ABORT_COUNTDOWN} seconds..." \\
    --position "${DIALOG_POSITION}" \\
    --moveable \\
    --ontop \\
    --height ${ABORT_HEIGHT} \\
    --width ${ABORT_WIDTH} 
    
  # Signal success to the user
  osascript -e "display notification \"Installation aborted and will be rescheduled\" with title \"macOS Upgrade\"" 2>/dev/null || true
  
  # Exit without creating trigger file
  exit 0
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
cleanup_watchdog() {
  # Create a unique identifier for this cleanup run
  local cleanup_id="${RUN_ID}-$(date +%s)"
  local cleanup_mutex="/var/tmp/erase-install-cleanup-${cleanup_id}.lock"
  local cleanup_log="/var/log/erase-install-cleanup-${cleanup_id}.log"
  
  log_message "Starting coordinated cleanup with ID: ${cleanup_id}"
  log_message "Cleanup log will be at: ${cleanup_log}"
  
  # Check if an abort daemon exists for this run ID
  local abort_daemon_path="/Library/LaunchDaemons/com.macjediwizard.eraseinstall.abort.${RUN_ID}.plist"
  local preserve_abort=false
  
  if [ -f "$abort_daemon_path" ]; then
    log_message "Abort daemon detected for run ID ${RUN_ID} - will preserve during cleanup"
    preserve_abort=true
    
    # Verify the daemon is loaded
    if launchctl list | grep -q "com.macjediwizard.eraseinstall.abort.${RUN_ID}"; then
      log_message "✓ Abort daemon is active in launchctl"
    else
      log_message "! Abort daemon exists but is not loaded - attempting to load it"
      launchctl load "$abort_daemon_path" 2>>"${cleanup_log}" || true
    fi
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
    pkill -9 -f "erase-install.sh" 2>/dev/null || true
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
    
    # Store preserve_abort value for background process
    local bg_preserve_abort="$preserve_abort"
    local bg_abort_daemon_path="$abort_daemon_path"
    
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
        if [ "$bg_preserve_abort" = "true" ] && [ "$daemon_path" = "$bg_abort_daemon_path" ]; then
          echo "$(date '+%Y-%m-%d %H:%M:%S') Preserving abort daemon: $daemon_path" >> "${cleanup_log}"
          continue
        fi
        
        echo "$(date '+%Y-%m-%d %H:%M:%S') Found lingering daemon: $daemon_path" >> "${cleanup_log}"
        daemon_label=$(basename "$daemon_path" .plist)
        launchctl remove "$daemon_label" 2>/dev/null || true
        rm -f "$daemon_path" 2>/dev/null || true
      fi
    done
    
    # Clean up any watchdog scripts in the Management directory
    for script in /Library/Management/erase-install/erase-install-watchdog-*.sh; do
      if [ -e "$script" ] && [ "$script" != "$WATCHDOG_SCRIPT" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') Removing lingering watchdog script: $script" >> "${cleanup_log}"
        rm -f "$script" 2>/dev/null || true
      fi
    done
    
    # Remove self (watchdog script) at the very end
    if [ -n "$WATCHDOG_SCRIPT" ] && [ -f "$WATCHDOG_SCRIPT" ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') Cleaning up watchdog script: $WATCHDOG_SCRIPT" >> "${cleanup_log}"
      mv "$WATCHDOG_SCRIPT" "${WATCHDOG_SCRIPT}.removed" 2>/dev/null
      rm -f "${WATCHDOG_SCRIPT}.removed" 2>/dev/null || true
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

# Add these after the cleanup_watchdog function
verify_abort_schedule() {
  local abort_daemon_label="$1"
  
  if launchctl list | grep -q "$abort_daemon_label"; then
    log_message "✅ Abort schedule successfully loaded and active"
    return 0
  else
    log_message "❌ Abort schedule not active in launchctl"
    return 1
  fi
}

# Add a daemon file monitor to detect and remove startosinstall plist
(
  log_message "Starting startosinstall plist monitor"
  while true; do
    if [ -f "/Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist" ]; then
      log_message "Detected startosinstall daemon - immediately removing"
      launchctl remove "com.github.grahampugh.erase-install.startosinstall" 2>/dev/null
      launchctl bootout system/com.github.grahampugh.erase-install.startosinstall 2>/dev/null
      rm -f "/Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist"
      log_message "Removed startosinstall daemon"
    fi
    sleep 2
  done
) &

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

# Check for abort file
if [ -f "$ABORT_FILE" ]; then
  log_message "Abort request detected, scheduling short-term deferral"
  rm -f "$ABORT_FILE"
  
  # Increment abort count
  abort_count=$(defaults read "$PLIST" abortCount 2>/dev/null || echo 0)
  abort_count=$((abort_count + 1))
  defaults write "$PLIST" abortCount -int "$abort_count"
  log_message "Abort count incremented to $abort_count/$MAX_ABORTS"
  
  # Calculate new defer time (ABORT_DEFER_MINUTES from now)
  current_hour=$(date +%H)
  current_min=$(date +%M)
  current_hour=$((10#$current_hour))
  current_min=$((10#$current_min))
  
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
    # Need tomorrow's date
    defer_day=$(date -v+1d +%d)
    defer_month=$(date -v+1d +%m)
  else
    # Use today's date
    defer_day=$(date +%d)
    defer_month=$(date +%m)
  fi
  
  # Format with leading zeros
  defer_hour=$(printf "%02d" $current_hour)
  defer_min=$(printf "%02d" $current_min)
  
  log_message "Scheduling aborted installation to resume at $defer_hour:$defer_min"
  
  # Create a function to handle the LaunchDaemon creation to avoid using local outside of functions
  create_abort_daemon() {
    # Create a LaunchDaemon for the aborted installation
    abort_daemon_label="com.macjediwizard.eraseinstall.abort.${RUN_ID}"
    abort_daemon_path="/Library/LaunchDaemons/${abort_daemon_label}.plist"
    
    log_message "Creating abort LaunchDaemon to run at $defer_hour:$defer_min"
    
    # Create LaunchDaemon plist for the aborted installation
    cat > "$abort_daemon_path" << ABORTDAEMON
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
$([ -n "${defer_day}" ] && printf "        <key>Day</key>\n        <integer>%d</integer>\n" "${defer_day}")
$([ -n "${defer_month}" ] && printf "        <key>Month</key>\n        <integer>%d</integer>\n" "${defer_month}")
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
    
    # Set proper permissions
    if [ -f "$abort_daemon_path" ]; then
      chmod 644 "$abort_daemon_path"
      chown root:wheel "$abort_daemon_path"
      log_message "Successfully created abort LaunchDaemon at: $abort_daemon_path"
      return 0
    else
      log_message "ERROR: Failed to create abort LaunchDaemon"
      return 1
    fi
  }
  
  # Call the function to create the daemon
  if create_abort_daemon; then
    # Load the LaunchDaemon
    log_message "Loading abort LaunchDaemon $abort_daemon_label"
    launchctl load "$abort_daemon_path" 2>/dev/null

    # Verify schedule was loaded
    verify_abort_schedule "$abort_daemon_label"
    
    # Check if loading was successful
    if launchctl list | grep -q "$abort_daemon_label"; then
      log_message "Successfully loaded abort LaunchDaemon"
    else
      log_message "WARNING: Failed to load abort LaunchDaemon, trying alternative method"
      # Try alternative loading method
      launchctl bootstrap system "$abort_daemon_path" 2>/dev/null

      # Verify schedule was loaded
      verify_abort_schedule "$abort_daemon_label"
    fi
  else
    log_message "ERROR: Unable to create abort daemon, cleanup will proceed without rescheduling"
  fi
  
  # Notify user
  osascript -e "display notification \"Installation rescheduled for $defer_hour:$defer_min\" with title \"macOS Upgrade Aborted\"" 2>/dev/null || true
  
  # Clean up and exit
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
  
  # Build command arguments properly - FIX FOR THE EMPTY COMMAND ISSUE
  CMD="$ERASE_INSTALL_PATH"
  
  # Add reinstall parameter
  if [[ "$REINSTALL" == "true" ]]; then
    log_message "Mode: Reinstall (not erase-install)"
    CMD="$CMD --reinstall"
  fi
  
  # Add reboot delay if specified
  if [ "$REBOOT_DELAY" -gt 0 ]; then
    log_message "Using reboot delay: $REBOOT_DELAY seconds"
    CMD="$CMD --rebootdelay $REBOOT_DELAY"
  fi
  
  # Add no filesystem option if enabled
  if [ "$NO_FS" = true ]; then
    log_message "File system check disabled (--no-fs)"
    CMD="$CMD --no-fs"
  fi
  
  # Add power check and wait limit if enabled
  if [ "$CHECK_POWER" = true ]; then
    log_message "Power check enabled: erase-install will verify power connection"
    CMD="$CMD --check-power"
    
    if [ "$POWER_WAIT_LIMIT" -gt 0 ]; then
      log_message "Power wait limit set to $POWER_WAIT_LIMIT seconds"
      CMD="$CMD --power-wait-limit $POWER_WAIT_LIMIT"
    else
      log_message "Using default power wait limit (60 seconds)"
    fi
  else
    log_message "Power check disabled: installation will proceed regardless of power status"
  fi
  
  # Add minimum drive space
  log_message "Minimum drive space: $MIN_DRIVE_SPACE GB"
  CMD="$CMD --min-drive-space $MIN_DRIVE_SPACE"
  
  # Add cleanup option if enabled
  if [ "$CLEANUP_AFTER_USE" = true ]; then
    log_message "Cleanup after use enabled"
    CMD="$CMD --cleanup-after-use"
  fi
  
  # Add test mode if enabled
  if [[ $TEST_MODE == true ]]; then
    log_message "Test mode enabled"
    CMD="$CMD --test-run"
  fi
  
  # Add verbose logging if debug mode enabled
  if [ "$DEBUG_MODE" = true ]; then
    log_message "Verbose logging enabled for erase-install"
    CMD="$CMD --verbose"
  fi
  
  # Log command before no-reboot check
  log_message "Command before no-reboot check: $CMD"
  
  # Add no-reboot override if enabled (highest safety priority)
  # This should be last to override any other reboot settings
  if [ "$PREVENT_ALL_REBOOTS" = "true" ]; then
    log_message "SAFETY FEATURE: --no-reboot flag added to prevent any reboots"
    CMD="$CMD --no-reboot"
    log_message "VERIFIED: Final command with --no-reboot: $CMD"
  elif [ "$TEST_MODE" = "true" ]; then
    # Double safety check - always add no-reboot in test mode regardless of PREVENT_ALL_REBOOTS
    log_message "SAFETY FEATURE: Adding --no-reboot flag because test mode is enabled"
    CMD="$CMD --no-reboot"
    log_message "VERIFIED: Final command with --no-reboot (test mode): $CMD"
  fi

  # Safety check to verify test mode flag is correctly passed
  if [ "$TEST_MODE" = "true" ] && [[ "$CMD" != *"--test-run"* ]]; then
    log_message "CRITICAL SAFETY CHECK FAILED: Test mode enabled but --test-run missing from command"
    log_message "Command was: $CMD"
    log_message "Aborting installation to prevent unintended reboot"
    exit 1
  fi

  # Execute the command with proper error handling
  log_message "Command about to execute: $CMD"
  log_message "PREVENT_ALL_REBOOTS value: $PREVENT_ALL_REBOOTS"
  log_message "TEST_MODE value: $TEST_MODE"
  
  # Critical safety check - absolutely prevent reboots in test mode
  if [[ "$TEST_MODE" = "true" && "$CMD" != *"--no-reboot"* ]]; then
    log_message "CRITICAL SAFETY FAILURE: Test mode enabled but --no-reboot missing from command"
    log_message "Adding --no-reboot as emergency safety measure"
    CMD="$CMD --no-reboot"
    log_message "Modified command: $CMD"
  fi
  
  # Final verification - log full command
  log_message "FINAL COMMAND TO EXECUTE: $CMD"
  
  # Add PATH to ensure binary can be found
  export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
  
  # Execute the command
  eval "$CMD"
  
  # Save exit code with enhanced error handling
  RESULT=$?
  log_message "erase-install completed with exit code: $RESULT"
  
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
    
  # Now replace all the placeholders in the script
  # This method avoids variable expansion during the heredoc creation
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
  # Add enhanced logging to debug the substitution
  log_info "DEBUG: PREVENT_ALL_REBOOTS value before substitution: '${PREVENT_ALL_REBOOTS}'"
  
  # Use explicit string replacement to avoid any issues with the variable
  if [[ "${PREVENT_ALL_REBOOTS}" == "true" ]]; then
    sed -i '' "s|__PREVENT_ALL_REBOOTS__|true|g" "$watchdog_script"
    log_info "Set PREVENT_ALL_REBOOTS to 'true' in watchdog script"
  else
    sed -i '' "s|__PREVENT_ALL_REBOOTS__|false|g" "$watchdog_script"
    log_info "Set PREVENT_ALL_REBOOTS to 'false' in watchdog script"
  fi
  
  # Enhanced debugging for critical parameters
  log_info "SCRIPT DEBUG: Before substitution, parameters summary:"
  log_info "SCRIPT DEBUG: PREVENT_ALL_REBOOTS='${PREVENT_ALL_REBOOTS}'"
  log_info "SCRIPT DEBUG: TEST_MODE='${TEST_MODE}'"
  log_info "SCRIPT DEBUG: REINSTALL='${REINSTALL}'"
  log_info "SCRIPT DEBUG: Watchdog script path='${watchdog_script}'"
  log_info "SCRIPT DEBUG: Run ID='${run_id}'"
  
  # erase-install parameters
  sed -i '' "s|__ERASE_INSTALL_PATH__|${SCRIPT_PATH}|g" "$watchdog_script"
  sed -i '' "s|__REBOOT_DELAY__|${REBOOT_DELAY}|g" "$watchdog_script"
  sed -i '' "s|__REINSTALL__|${REINSTALL}|g" "$watchdog_script"
  sed -i '' "s|__NO_FS__|${NO_FS}|g" "$watchdog_script"
  sed -i '' "s|__CHECK_POWER__|${CHECK_POWER}|g" "$watchdog_script"
  sed -i '' "s|__POWER_WAIT_LIMIT__|${POWER_WAIT_LIMIT}|g" "$watchdog_script"
  sed -i '' "s|__MIN_DRIVE_SPACE__|${MIN_DRIVE_SPACE}|g" "$watchdog_script"
  sed -i '' "s|__CLEANUP_AFTER_USE__|${CLEANUP_AFTER_USE}|g" "$watchdog_script"
  sed -i '' "s|__TEST_MODE__|${TEST_MODE}|g" "$watchdog_script"
  sed -i '' "s|__DEBUG_MODE__|${DEBUG_MODE}|g" "$watchdog_script"
  
  # Auth notice parameters
  sed -i '' "s|__SHOW_AUTH_NOTICE__|${SHOW_AUTH_NOTICE}|g" "$watchdog_script"
  sed -i '' "s|__AUTH_NOTICE_TITLE__|${AUTH_NOTICE_TITLE}|g" "$watchdog_script"
  sed -i '' "s|__AUTH_NOTICE_TITLE_TEST_MODE__|${AUTH_NOTICE_TITLE_TEST_MODE}|g" "$watchdog_script"
  sed -i '' "s|__AUTH_NOTICE_MESSAGE__|$(echo "${AUTH_NOTICE_MESSAGE}" | sed 's/[\/&]/\\&/g')|g" "$watchdog_script"
  sed -i '' "s|__AUTH_NOTICE_BUTTON__|${AUTH_NOTICE_BUTTON}|g" "$watchdog_script"
  sed -i '' "s|__AUTH_NOTICE_ICON__|${AUTH_NOTICE_ICON}|g" "$watchdog_script"
  sed -i '' "s|__AUTH_NOTICE_HEIGHT__|${AUTH_NOTICE_HEIGHT}|g" "$watchdog_script"
  sed -i '' "s|__AUTH_NOTICE_WIDTH__|${AUTH_NOTICE_WIDTH}|g" "$watchdog_script"
  sed -i '' "s|__DIALOG_PATH__|${DIALOG_BIN}|g" "$watchdog_script"
  sed -i '' "s|__DIALOG_POSITION__|${DIALOG_POSITION}|g" "$watchdog_script"
  
  sed -i '' "s|__ABORT_FILE__|/var/tmp/erase-install-abort-${run_id}|g" "$watchdog_script"
  sed -i '' "s|__ABORT_DEFER_MINUTES__|${ABORT_DEFER_MINUTES}|g" "$watchdog_script"
  sed -i '' "s|__MAX_ABORTS__|${MAX_ABORTS}|g" "$watchdog_script"
  sed -i '' "s|__PLIST__|${PLIST}|g" "$watchdog_script"
  sed -i '' "s|__SCRIPT_MODE__|${mode}|g" "$watchdog_script"
  
  # Add enhanced logging to debug the substitution
  log_info "DEBUG: PREVENT_ALL_REBOOTS value before substitution: '${PREVENT_ALL_REBOOTS}'"
  
  # Use explicit string replacement to avoid any issues with the variable
  if [[ "${PREVENT_ALL_REBOOTS}" == "true" ]]; then
    sed -i '' "s|__PREVENT_ALL_REBOOTS__|true|g" "$watchdog_script"
    log_info "Set PREVENT_ALL_REBOOTS to 'true' in watchdog script"
  else
    sed -i '' "s|__PREVENT_ALL_REBOOTS__|false|g" "$watchdog_script"
    log_info "Set PREVENT_ALL_REBOOTS to 'false' in watchdog script"
  fi  
  
  # Add verification of the substitution if debug mode is on
  if [[ "${DEBUG_MODE}" == "true" ]]; then
    log_info "SCRIPT DEBUG: Verifying PREVENT_ALL_REBOOTS substitution in watchdog script:"
    if grep -q "PREVENT_ALL_REBOOTS=\"true\"" "$watchdog_script"; then
      log_info "SCRIPT DEBUG: ✅ PREVENT_ALL_REBOOTS successfully set to 'true' in watchdog script"
    elif grep -q "PREVENT_ALL_REBOOTS=\"false\"" "$watchdog_script"; then
      log_info "SCRIPT DEBUG: ✅ PREVENT_ALL_REBOOTS successfully set to 'false' in watchdog script"
    else
      log_error "SCRIPT DEBUG: ❌ Failed to properly substitute PREVENT_ALL_REBOOTS in watchdog script"
      grep "PREVENT_ALL_REBOOTS" "$watchdog_script" | head -1 | log_debug
    fi
    
    # Also verify TEST_MODE substitution
    if grep -q "TEST_MODE=\"true\"" "$watchdog_script"; then
      log_info "SCRIPT DEBUG: ✅ TEST_MODE successfully set to 'true' in watchdog script"
    elif grep -q "TEST_MODE=\"false\"" "$watchdog_script"; then
      log_info "SCRIPT DEBUG: ✅ TEST_MODE successfully set to 'false' in watchdog script"
    else
      log_error "SCRIPT DEBUG: ❌ Failed to properly substitute TEST_MODE in watchdog script"
    fi
  fi
  
  # Validate the generated watchdog script
  log_info "Validating watchdog script integrity..."
  if ! bash -n "$watchdog_script" 2>/dev/null; then
    log_error "CRITICAL: Generated watchdog script contains syntax errors"
    
    # Create a backup for troubleshooting
    watchdog_backup="${watchdog_script}.broken-$(date +%s)"
    cp "$watchdog_script" "$watchdog_backup"
    log_error "Created backup at ${watchdog_backup} for troubleshooting"
    
    # Log script size and last few lines for debugging
    log_error "Generated script size: $(wc -l < "$watchdog_script") lines"
    log_error "Last 10 lines of script for debugging:"
    tail -10 "$watchdog_script" | while IFS= read -r line; do
      log_error "  $line"
    done
    
    # Return failure
    return 1
  fi
  
  log_info "Watchdog script validation successful"
  
  # Use explicit string replacement to avoid any issues with the variable
  if [[ "${PREVENT_ALL_REBOOTS}" == "true" ]]; then
    sed -i '' "s|__PREVENT_ALL_REBOOTS__|true|g" "$watchdog_script"
    log_info "Set PREVENT_ALL_REBOOTS to 'true' in watchdog script"
  else
    sed -i '' "s|__PREVENT_ALL_REBOOTS__|false|g" "$watchdog_script"
    log_info "Set PREVENT_ALL_REBOOTS to 'false' in watchdog script"
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
  
  # Only create and load UI agent if not in defer mode
  if [ "$show_ui" = true ]; then
    log_info "Creating LaunchAgent for UI display at $(printf '%02d:%02d' "${hour_num}" "${minute_num}")${day:+ on day $day_num}${month:+ month $month_num}"
    # Create the agent plist
    printf "%s" "${agent_content}" | sudo -u "$console_user" tee "$agent_path" > /dev/null
    sudo -u "$console_user" chmod 644 "$agent_path"
    
    # Load the agent
    log_info "Loading LaunchAgent for UI..."
    if ! launchctl asuser "$(id -u "$console_user")" sudo -u "$console_user" launchctl bootstrap gui/"$(id -u "$console_user")" "$agent_path" 2>/dev/null; then
      # Try legacy load method
      launchctl asuser "$(id -u "$console_user")" sudo -u "$console_user" launchctl load "$agent_path"
    fi
  else
    log_info "Defer mode - skipping UI agent creation"
  fi
  
  # Always write the daemon plist
  printf "%s" "${daemon_content}" | sudo tee "$daemon_path" > /dev/null
  # Ensure proper permissions
  sudo chown root:wheel "$daemon_path"
  sudo chmod 644 "$daemon_path"
  
  # Load the daemon with better error handling and pause
  log_info "Loading LaunchDaemon for installation..."
  
  # Add a pause to ensure previous unloading completes
  log_info "Pausing briefly to ensure previous daemon is fully unloaded..."
  sleep 3
  
  # Check if daemon file exists before attempting to load
  if [ ! -f "$daemon_path" ]; then
    log_error "LaunchDaemon file does not exist at: $daemon_path - cannot load it"
    
    # Check if directory is writeable
    if [ ! -w "/Library/LaunchDaemons" ]; then
      log_error "LaunchDaemons directory is not writeable - permissions issue"
      ls -la /Library/LaunchDaemons/ | head -5 | log_debug
    fi
    
    return 1
  fi
  
  # Verify file
  
  # Verify daemon is loaded
  sleep 1
  if sudo launchctl list | grep -q "$daemon_label"; then
    log_info "Verified LaunchDaemon is loaded"
  else
    log_warn "LaunchDaemon might not be properly loaded"
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
    for pid in $(ps -ef | grep -i '[s]tartosinstall' | awk '{print $2}'); do
      log_info "Killing startosinstall process: $pid"
      kill -9 $pid 2>/dev/null
    done
    
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
  console_user=$(stat -f%Su /dev/console 2>/dev/null || echo "")
  log_debug "Detection method 1 result: '$console_user'"
  
  if [ -z "$console_user" ]; then
    console_user=$(who | grep "console" | awk '{print $1}' | head -n1)
    log_debug "Detection method 2 result: '$console_user'"
  fi
  if [ -z "$console_user" ]; then
    console_user=$(ls -l /dev/console | awk '{print $3}')
    log_debug "Detection method 3 result: '$console_user'"
  fi
  if [ -z "$console_user" ] || [ "$console_user" = "root" ]; then
    console_user=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && !/loginwindow/ { print $3 }')
    log_debug "Detection method 4 result: '$console_user'"
  fi
  [ -z "$console_user" ] && console_user="$SUDO_USER" && log_debug "Using SUDO_USER: '$console_user'"
  [ -z "$console_user" ] && console_user="$(id -un)" && log_debug "Using current user: '$console_user'"
  
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
  
  # Check if abort button should be shown
  local abort_button_args=""
  if [[ "${ENABLE_ABORT_BUTTON}" == "true" ]]; then
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
  local defer_text
  if [[ "$TEST_MODE" == "true" ]]; then
    defer_text="Defer 5 Minutes   (TEST MODE)"
    # Also set the variable for later use in case statement
    DIALOG_DEFER_TEXT_TEST_MODE="$defer_text"
  else
    defer_text="${DIALOG_DEFER_TEXT}"
  fi
  
  # Log the deferral status clearly
  if [[ "${DEFERRAL_EXCEEDED}" = true ]]; then
    OPTIONS="${DIALOG_INSTALL_NOW_TEXT},${DIALOG_SCHEDULE_TODAY_TEXT}"
    log_info "DEFERRAL_EXCEEDED=true - Removing defer option from dialog"
  else
    OPTIONS="${DIALOG_INSTALL_NOW_TEXT},${DIALOG_SCHEDULE_TODAY_TEXT},${defer_text}"
    log_info "DEFERRAL_EXCEEDED=false - Including defer option in dialog: '${defer_text}'"
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
  console_user=$(stat -f%Su /dev/console 2>/dev/null || echo "")
  [ -z "$console_user" ] && console_user=$(who | grep "console" | awk '{print $1}' | head -n1)
  [ -z "$console_user" ] && console_user=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && !/loginwindow/ { print $3 }')
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
  
  local raw; raw=$("${DIALOG_BIN}" --title "${display_title}" --message "${DIALOG_MESSAGE}" --button1text "${DIALOG_CONFIRM_TEXT}" --height ${DIALOG_HEIGHT} --width ${DIALOG_WIDTH} --moveable --icon "${DIALOG_ICON}" --ontop --timeout 0 --showicon true --position "${DIALOG_POSITION}" --messagefont ${DIALOG_MESSAGEFONT} --selecttitle "Select an action:" --select --selectvalues "${OPTIONS}" --selectdefault "${DIALOG_INSTALL_NOW_TEXT}" --jsonoutput 2>&1 | tee -a "${WRAPPER_LOG}")
  local code=$?
  log_debug "SwiftDialog exit code: ${code}"
  log_debug "SwiftDialog raw output: ${raw}"
  
  [[ $code -ne 0 || -z "$raw" ]] && { log_warn "No valid JSON from SwiftDialog; aborting."; return 1; }
  
  local selection; selection=$(parse_dialog_output "$raw" "SelectedOption")
  [[ -z "$selection" || "$selection" == "null" ]] && { log_warn "No selection made; aborting."; return 1; }
  
  log_info "User selected: ${selection}"
  
  case "$selection" in
    "${DIALOG_INSTALL_NOW_TEXT}")
      # Ensure any existing LaunchDaemons are removed for "Install Now"
      remove_existing_launchdaemon
      reset_deferrals
      
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
      local sub; sub=$("${DIALOG_BIN}" --title "${display_title}" --message "Select installation time:" --button1text "${DIALOG_CONFIRM_TEXT}" --height ${SCHEDULED_HEIGHT} --width ${SCHEDULED_WIDTH} --moveable --icon "${DIALOG_ICON}" --ontop --timeout 0 --showicon true --position "${DIALOG_POSITION}" --messagefont "${SCHEDULED_DIALOG_MESSAGEFONT}" --selecttitle "Choose time:" --select --selectvalues "${time_options}" --selectdefault "$(echo "$time_options" | cut -d',' -f1)" --jsonoutput 2>&1 | tee -a "${WRAPPER_LOG}")
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
        
        # Show error dialog
        "${DIALOG_BIN}" --title "${ERROR_DIALOG_TITLE}" --message "${ERROR_DIALOG_MESSAGE}" --icon "${ERROR_DIALOG_ICON}" --button1text "${ERROR_CONTINUE_TEXT}" --height ${ERROR_DIALOG_HEIGHT} --width ${ERROR_DIALOG_WIDTH} --position "${DIALOG_POSITION}"
        
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
      
      # Remove any existing daemons
      remove_existing_launchdaemon
      
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
      
      reset_deferrals
    ;;
    # Handle both normal and test mode defer options
    "${DIALOG_DEFER_TEXT}" | "${DIALOG_DEFER_TEXT_TEST_MODE}")
      if [[ "${DEFERRAL_EXCEEDED}" = true ]]; then
        log_warn "Maximum deferrals (${MAX_DEFERS}) reached."
        reset_deferrals
        
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
        newCount=$((deferCount + 1))
        defaults write "${PLIST}" deferCount -int "$newCount"
        
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
          local defer_hour; defer_hour=$(date -v+24H +%H)
          local defer_min; defer_min=$(date -v+24H +%M)
          local defer_day; defer_day=$(date -v+1d +%d)
          local defer_month; defer_month=$(date -v+1d +%m)
        fi
        
        # Ensure clean state - preserve abort daemon if running from one
        if [[ "$RUNNING_FROM_ABORT_DAEMON" == "true" ]]; then
          log_info "Running from abort daemon - preserving abort daemons during cleanup"
          remove_existing_launchdaemon "--preserve-abort-daemon"
        else
          remove_existing_launchdaemon
        fi
        
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
              
              # Check if daemon is loaded in launchctl
              local daemon_label="${LAUNCHDAEMON_LABEL}.watchdog.${CURRENT_RUN_ID}"
              if launchctl list | grep -q "$daemon_label"; then
                log_info "Verified LaunchDaemon is loaded in launchctl: $daemon_label"
              else
                log_warn "LaunchDaemon file exists but may not be loaded: $daemon_label"
                log_info "Attempting to load LaunchDaemon again..."
                launchctl load "$expected_daemon_path" 2>/dev/null || log_warn "Failed to load daemon"
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
            if [[ "$TEST_MODE" == "true" ]]; then
              log_info "TEST MODE: Scheduled re-prompt for $defer_hour:$defer_min (in approximately 5 minutes)"
              
              # Show a notification to the user if possible
              if [ -n "$console_user" ] && [ "$console_user" != "root" ] && [ -n "$console_uid" ]; then
                launchctl asuser "$console_uid" sudo -u "$console_user" osascript -e 'display notification "Due to test mode, the deferral is set for 5 minutes instead of 24 hours." with title "macOS Upgrade - Test Mode"'
              fi
            else
              log_info "Scheduled re-prompt for tomorrow at $(printf '%02d:%02d' "${display_hour}" "${display_min}")"
            fi
          else
            log_error "LaunchDaemon creation appeared to succeed but verification failed"
            
            # Try direct retry with more permissions
            log_info "Attempting direct retry of LaunchDaemon creation..."
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
  console_user=$(stat -f%Su /dev/console 2>/dev/null || echo "")
  log_debug "Detection method 1 result: '$console_user'"
  
  if [ -z "$console_user" ]; then
    console_user=$(who | grep "console" | awk '{print $1}' | head -n1)
    log_debug "Detection method 2 result: '$console_user'"
  fi
  if [ -z "$console_user" ]; then
    console_user=$(ls -l /dev/console | awk '{print $3}')
    log_debug "Detection method 3 result: '$console_user'"
  fi
  if [ -z "$console_user" ] || [ "$console_user" = "root" ]; then
    console_user=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && !/loginwindow/ { print $3 }')
    log_debug "Detection method 4 result: '$console_user'"
  fi
  [ -z "$console_user" ] && console_user="$SUDO_USER" && log_debug "Using SUDO_USER: '$console_user'"
  [ -z "$console_user" ] && console_user="$(id -un)" && log_debug "Using current user: '$console_user'"
  
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
  
  # Create a temporary script for dialog display
  log_debug "Creating temporary script for dialog display"
  TMP_DIR=$(mktemp -d)
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
  # MOST RELIABLE: Check for our global early detection flag first
  if [[ "$RUNNING_FROM_ABORT_DAEMON" == "true" ]]; then
    log_debug "Detected running from abort daemon via early detection flag"
    return 0  # True - already detected in early phase
  fi
  
  # SECOND MOST RELIABLE: Check environment variable
  if [[ "${ERASE_INSTALL_ABORT_DAEMON:-}" == "true" ]]; then
    log_debug "Detected running from abort daemon via environment variable"
    return 0  # True - environment indicates we're from abort daemon
  fi
  
  # THIRD MOST RELIABLE: Check command line arguments
  for arg in "$@"; do
    if [[ "$arg" == "--from-abort-daemon" ]]; then
      log_debug "Detected running from abort daemon via command line argument"
      return 0  # True - explicit command line flag
    fi
  done
  
  # FOURTH MOST RELIABLE: Check if our parent process has "abort" in its command line
  local parent_cmd=""
  if [ -n "$PPID" ]; then
    parent_cmd=$(ps -o command= -p "$PPID" 2>/dev/null || echo "")
    if [[ "$parent_cmd" == *"com.macjediwizard.eraseinstall.abort"* ]]; then
      log_debug "Detected running from abort daemon via parent process command: $parent_cmd"
      return 0  # True - running from abort daemon
    fi
  fi
  
  # FIFTH MOST RELIABLE: Check our own process name/command
  local own_cmd=""
  own_cmd=$(ps -p $$ -o command= 2>/dev/null || echo "")
  if [[ "$own_cmd" == *"com.macjediwizard.eraseinstall.abort"* ]]; then
    log_debug "Detected running from abort daemon via own process command: $own_cmd"
    return 0  # True - own process command contains abort daemon reference
  fi
  
  # None of the abort daemon detection methods succeeded
  return 1  # False - not running from abort daemon
}

# Main script execution for non-scheduled mode
init_logging
log_info "Starting erase-install wrapper script v${SCRIPT_VERSION}"
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
  console_user=$(stat -f%Su /dev/console 2>/dev/null || echo "")
  [ -z "$console_user" ] && console_user=$(who | grep "console" | awk '{print $1}' | head -n1)
  [ -z "$console_user" ] && console_user=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && !/loginwindow/ { print $3 }')
  
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
get_deferral_state

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