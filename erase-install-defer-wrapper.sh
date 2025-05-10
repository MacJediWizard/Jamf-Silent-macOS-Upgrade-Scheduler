#!/bin/bash

#########################################################################################################################################################################
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
# v1.4.17 - Implemented centralized LaunchDaemon control mechanism, fixed time formatting issues, and improved window behavior
# v1.4.16 - Fixed printf error with leading zeros by enforcing base-10 interpretation
# v1.4.15 - Removed --mini flag and adjusted window dimensions for proper display of UI elements
# v1.4.14 - Added --mini flag to all SwiftDialog commands, implemented proper countdown with auto-continue
# v1.4.13 - Fixed scheduled installation countdown window, ensured wrapper script is called properly
# v1.4.12 - Fixed SwiftDialog selection parsing, padded log times, enforced LaunchDaemon unload, deferred flow fix
# v1.4.11 - Fixed LaunchDaemon creation consistency and improved error handling
# v1.4.10 - Fixed Bash octal parsing bug when scheduling times like 08:00 or 09:00
# v1.4.9 - Enhanced logging system with rotation and additional log levels
# v1.4.8 - Enhanced UI with proper dropdown selections and improved response handling
# v1.4.7 - Fixed JSON parsing to correctly extract dropdown selections from nested SwiftDialog output
# v1.4.6 - Switched to dropdown UI with three options (Install Now, Schedule Today, Defer 24 Hours)
# v1.4.5 - Reverted to multi-button UI: Install Now, Schedule Today, Defer 24 Hours
# v1.4.4 - Updated logging functions to simplified date expansion syntax
# v1.4.3 - Switched to dropdown UI with single OK button (then reverted)
# v1.4.2 - Preserved --mini UI and added debug logging of SwiftDialog exit codes/output
# v1.4.1 - Fixed syntax in install functions ($(mktemp -d))
# v1.4.0 - Persistent deferral count across runs and reset when new script version is detected
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
SCRIPT_VERSION="1.5.3"              # Current version of this script
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
DIALOG_ICON="SF=gear"                          # Icon (SF Symbol or path to image)
DIALOG_POSITION="topright"                     # Dialog position: topleft, topright, center, bottomleft, bottomright
DIALOG_HEIGHT=250                              # Dialog height in pixels
DIALOG_WIDTH=550                               # Dialog width in pixels
DIALOG_MESSAGEFONT="size=14"                   # Font size for dialog message
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
PREINSTALL_HEIGHT=250                          # Height of pre-installation dialog
PREINSTALL_WIDTH=550                           # Width of pre-installation dialog
PREINSTALL_DIALOG_MESSAGEFONT="size=14"        # Font size for pre-installation dialog message
#
# ---- Scheduled Installation Dialog ----
SCHEDULED_TITLE="macOS Upgrade Scheduled"      # Title for scheduled dialog
SCHEDULED_TITLE_TEST_MODE="$SCHEDULED_TITLE\n                (TEST MODE)"   # Title for scheduled dialog Test Mode
SCHEDULED_MESSAGE="Your scheduled macOS upgrade is ready to begin.\n\nThe upgrade will start automatically in 60 seconds, or click Continue to begin now."  # Message text
SCHEDULED_PROGRESS_TEXT_MESSAGE="Installation will begin in 60 seconds....."   # Progress Text Message
SCHEDULED_CONTINUE_TEXT="Continue Now"        # Button text for continue button
SCHEDULED_COUNTDOWN=60                        # Countdown duration in seconds
SCHEDULED_HEIGHT=350                          # Height of scheduled dialog
SCHEDULED_WIDTH=550                           # Width of scheduled dialog
SCHEDULED_DIALOG_MESSAGEFONT="size=14"        # Font size for scheduled dialog message
#
# ---- Error Dialog Configuration ----
ERROR_DIALOG_TITLE="Invalid Time"              # Title for error dialog
ERROR_DIALOG_MESSAGE="The selected time is invalid.\nPlease select a valid time (00:00-23:59)."  # Error message
ERROR_DIALOG_ICON="SF=exclamationmark.triangle" # Icon for error dialog
ERROR_DIALOG_HEIGHT=250                        # Height of error dialog
ERROR_DIALOG_WIDTH=550                         # Width of error dialog
ERROR_CONTINUE_TEXT="OK"                       # Button text for continue button
#
# ---- Options passed to erase-install.sh ----
# These settings control which arguments are passed to Graham Pugh's script
REBOOT_DELAY=60                    # Delay in seconds before rebooting
REINSTALL=true                     # true=reinstall, false=erase and install
NO_FS=true                         # Skip file system creation
CHECK_POWER=true                   # Check if on AC power before installing
MIN_DRIVE_SPACE=50                 # Minimum free drive space in GB
CLEANUP_AFTER_USE=true             # Clean up temp files after use
#
########################################################################################################################################################################

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
  WRAPPER_PATH="$(readlink "${0}")"
else
  WRAPPER_PATH="${0}"
fi

# Convert to absolute path if not already
if [[ ! "${WRAPPER_PATH}" = /* ]]; then
  # Get the directory of the script and combine with basename
  WRAPPER_DIR="$(cd "$(dirname "${WRAPPER_PATH}")" 2>/dev/null && pwd)"
  if [[ -n "${WRAPPER_DIR}" ]]; then
    WRAPPER_PATH="${WRAPPER_DIR}/$(basename "${WRAPPER_PATH}")"
  else
    # Fallback for Jamf and other deployment scenarios
    # Most reliable location is the script parameter $0
    WRAPPER_PATH="${0}"
    # Log that we're using the original path
    echo "WARNING: Could not determine absolute path, using original path: ${WRAPPER_PATH}" >> "${WRAPPER_LOG}" 2>&1
  fi
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

log_system_info() {
  log_system "Script Version: ${SCRIPT_VERSION}"
  log_system "macOS Version: $(sw_vers -productVersion)"
  log_system "Hardware Model: $(sysctl -n hw.model)"
  log_system "Available Disk Space: $(df -h / | awk 'NR==2 {print $4}')"
  log_system "Current User: $(whoami)"
  log_system "Effective User ID: ${EUID}"
  log_system "Dialog Version: $("${DIALOG_BIN}" --version 2>/dev/null || echo 'Not installed')"
  
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

# ---- OS Version Check Test Function ----

test_os_version_check() {
  log_info "===== OS VERSION CHECK TEST MODE ====="
  log_info "Test modes active: TEST_MODE=${TEST_MODE}, SKIP_OS_VERSION_CHECK=${SKIP_OS_VERSION_CHECK}"
  
  # Get current OS version
  local current_os=$(sw_vers -productVersion)
  log_info "Current OS version: $current_os"
  
  # Get target OS version
  local target_os=$(defaults read "${PLIST}" targetOSVersion 2>/dev/null || echo "${INSTALLER_OS}")
  log_info "Target OS version: $target_os"
  
  # Run the normal OS version check
  if check_os_already_updated; then
    log_info "TEST RESULT: System is already running the target OS version."
    log_info "In normal mode, the script would exit here."
    log_info "Since SKIP_OS_VERSION_CHECK=${SKIP_OS_VERSION_CHECK}, the script will continue."
  else
    log_info "TEST RESULT: System needs to be updated to the target OS version."
  fi
  
  # Run the deferral OS check
  if check_if_os_upgraded_during_deferral; then
    log_info "TEST RESULT: OS has been upgraded during deferral period or is already at target."
    log_info "In normal mode, a scheduled installation would exit here."
    log_info "Since SKIP_OS_VERSION_CHECK=${SKIP_OS_VERSION_CHECK}, the script will continue."
  else
    log_info "TEST RESULT: OS has NOT been upgraded during deferral and needs update."
  fi
  
  log_info "===== OS VERSION CHECK TEST COMPLETE ====="
  
  # Return true (0) to allow script to continue regardless of actual OS versions
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

# ---------------- Dependency Management ----------------

install_erase_install() {
  log_info "erase-install not found. Downloading and installing..."
  local tmp; tmp=$(mktemp -d)
  curl -fsSL -o "${tmp}/erase-install.pkg" "https://github.com/grahampugh/erase-install/releases/latest/download/erase-install.pkg" || { log_error "Failed to download erase-install."; rm -rf "${tmp}"; return 1; }
  /usr/sbin/installer -pkg "${tmp}/erase-install.pkg" -target / || { log_error "Installation of erase-install failed."; rm -rf "${tmp}"; return 1; }
  log_info "erase-install installed successfully."
  rm -rf "${tmp}"
}

install_swiftDialog() {
  log_info "swiftDialog not found. Downloading and installing..."
  local tmp; tmp=$(mktemp -d)
  
  # Download the latest version of swiftDialog
  log_info "Downloading latest swiftDialog..."
  curl -fsSL -o "${tmp}/dialog.pkg" "https://github.com/bartreardon/swiftDialog/releases/latest/download/dialog.pkg" || { log_error "Failed to download swiftDialog."; rm -rf "${tmp}"; return 1; }
  
  # Install the package
  log_info "Installing swiftDialog package..."
  /usr/sbin/installer -pkg "${tmp}/dialog.pkg" -target / || { log_error "Installation of swiftDialog failed."; rm -rf "${tmp}"; return 1; }
  
  # Create a symlink from the app location to /usr/local/bin if needed
  if [ -e "/Library/Application Support/Dialog/Dialog.app/Contents/MacOS/Dialog" ]; then
    log_info "Creating symlink for swiftDialog in /usr/local/bin..."
    mkdir -p /usr/local/bin
    ln -sf "/Library/Application Support/Dialog/Dialog.app/Contents/MacOS/Dialog" "/usr/local/bin/dialog"
  elif [ -e "/Library/Management/erase-install/Dialog.app/Contents/MacOS/Dialog" ]; then
    log_info "Creating symlink for erase-install bundled swiftDialog in /usr/local/bin..."
    mkdir -p /usr/local/bin
    ln -sf "/Library/Management/erase-install/Dialog.app/Contents/MacOS/Dialog" "/usr/local/bin/dialog"
  fi
  
  # Verify the installation
  if [ -x "/usr/local/bin/dialog" ]; then
    log_info "swiftDialog installed and accessible at /usr/local/bin/dialog"
  else
    log_error "swiftDialog installation verification failed - binary not found at expected location"
    # Try to find where Dialog might be installed
    log_info "Searching for Dialog binary..."
    find /Library -name "Dialog" -type f -executable 2>/dev/null || log_error "Could not locate Dialog binary"
  fi
  
  log_info "swiftDialog installation completed."
  rm -rf "${tmp}"
}

dependency_check() {
  local has_error=0
  
  if [ ! -x "${SCRIPT_PATH}" ]; then
    if [ "${AUTO_INSTALL_DEPENDENCIES}" = true ]; then
      if ! install_erase_install; then
        log_error "erase-install installation failed and is required to continue"
        has_error=1
      fi
    else
      log_error "erase-install missing and auto-install disabled"
      has_error=1
    fi
  fi
  
  if [ ! -x "${DIALOG_BIN}" ]; then
    if [ "${AUTO_INSTALL_DEPENDENCIES}" = true ]; then
      if ! install_swiftDialog; then
        log_error "swiftDialog installation failed and is required to continue"
        has_error=1
      fi
    else
      log_error "swiftDialog missing and auto-install disabled"
      has_error=1
    fi
  fi
  
  return $has_error
}

# ---------------- Version Check Functions ----------------

get_available_macos_version() {
  # Redirect all log output to stderr instead of stdout
  log_info "Using erase-install to check available macOS version..." >&2
  
  # Create a temporary file to store the output
  local tmp_file=$(mktemp)
  
  # Run erase-install with list-only flag
  # This will show available macOS versions without downloading anything
  log_info "Running erase-install in list-only mode..." >&2
  
  # The --list-only flag shows available installers without downloading
  "${SCRIPT_PATH}" --list-only > "$tmp_file" 2>&1
  
  # Extract the version information from the output
  local available_version=""
  
  # First check if erase-install found an installer
  if grep -q "Installer is at:" "$tmp_file"; then
    log_info "Installer found by erase-install" >&2
    
    # Look for system version in the output
    if grep -q "System version:" "$tmp_file"; then
      available_version=$(grep "System version:" "$tmp_file" | head -1 | awk -F': ' '{print $2}' | awk '{print $1}')
      log_info "Using system version from erase-install output: $available_version" >&2
      # Look for macOS Sequoia or similar name patterns
    elif grep -q "Install macOS.*\.app" "$tmp_file"; then
      # Extract the app name
      local app_name=$(grep "Install macOS.*\.app" "$tmp_file" | head -1 | grep -o "Install macOS.*\.app")
      log_info "Found installer app: $app_name" >&2
      
      # Get the version directly from the system
      if [[ -f "/Applications/$app_name/Contents/Info.plist" ]]; then
        available_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "/Applications/$app_name/Contents/Info.plist" 2>/dev/null)
        log_info "Extracted version from installer app: $available_version" >&2
      fi
    fi
  fi
  
  # If we still don't have a version, look for more patterns in the output
  if [[ -z "$available_version" ]]; then
    # Try to extract from any Build value mentions
    if grep -q "Build.*[0-9][0-9][A-Z][0-9]" "$tmp_file"; then
      log_info "Found Build value in erase-install output" >&2
      
      # Since we have a build but not a version, we should use the system version
      available_version=$(sw_vers -productVersion)
      log_info "Using current system version as target: $available_version" >&2
    fi
  fi
  
  # Clean up
  rm -f "$tmp_file"
  
  # If we couldn't get a version, use INSTALLER_OS as fallback
  if [[ -z "$available_version" ]]; then
    available_version="$INSTALLER_OS"
    log_info "Using INSTALLER_OS as fallback version: $available_version" >&2
  fi
  
  # Only return the version, not any logs or debug output
  echo "$available_version"
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
}

get_deferral_state() {
  deferCount=$(defaults read "${PLIST}" deferCount 2>/dev/null || echo 0)
  firstDate=$(defaults read "${PLIST}" firstPromptDate 2>/dev/null || echo 0)
  local now; now=$(date -u +%s)
  local elapsed=$((now - firstDate))
  log_debug "deferCount=${deferCount}, elapsed=${elapsed}s"
  DEFERRAL_EXCEEDED=false
  if (( deferCount >= MAX_DEFERS )) || (( elapsed >= FORCE_TIMEOUT_SECONDS )); then
    DEFERRAL_EXCEEDED=true
    log_info "Deferral limit exceeded: count=${deferCount}, elapsed=${elapsed}s"
  fi
}

# ---------------- LaunchDaemon ----------------

# Function to safely remove all LaunchDaemons
remove_existing_launchdaemon() {
  log_info "Checking for existing LaunchDaemons to remove..."
  local found_count=0
  local removed_count=0
  local is_scheduled=false
  
  # Check if this is a scheduled run
  [[ "$1" == "--preserve-scheduled" ]] && is_scheduled=true
  
  # First forcefully remove lingering entries from launchctl
  for label in $(launchctl list 2>/dev/null | grep -E "com.macjediwizard.eraseinstall|com.github.grahampugh.erase-install" | awk '{print $3}'); do
    if [ -n "$label" ]; then
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
  
  # Convert all values to base-10 integers
  local hour_num=$((10#${hour}))
  local minute_num=$((10#${minute}))
  local day_num=$([ -n "$day" ] && printf '%d' "$((10#${day}))" || echo "")
  local month_num=$([ -n "$month" ] && printf '%d' "$((10#${month}))" || echo "")
  
  # Generate a unique ID for this scheduled run
  local run_id="$(date +%Y%m%d%H%M%S)"
  
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
  
  log_info "Creating LaunchAgent for UI display at $(printf '%02d:%02d' "${hour_num}" "${minute_num}")${day:+ on day $day_num}${month:+ month $month_num}"
  
  # Create directory if it doesn't exist
  sudo -u "$console_user" mkdir -p "/Users/$console_user/Library/LaunchAgents"
  
  # For test mode, add indication in the dialog title
  local display_title="$SCHEDULED_TITLE"
  [[ "$TEST_MODE" = true ]] && display_title="${SCHEDULED_TITLE_TEST_MODE}"
  
  # Create a helper script that will run dialog and then trigger the installer
  local helper_script="/Users/$console_user/Library/Application Support/erase-install-helper-${run_id}.sh"
  mkdir -p "/Users/$console_user/Library/Application Support"
  
  cat > "$helper_script" << EOF
#!/bin/bash

# Run dialog with countdown
export DISPLAY=:0
export PATH='/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'

# Log script execution
LOG_FILE="/Users/$console_user/Library/Logs/erase-install-wrapper-ui.${run_id}.log"
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Helper script starting dialog" >> "\$LOG_FILE"

# Display dialog with countdown
"${DIALOG_BIN}" --title "${display_title}" \\
  --message "${SCHEDULED_MESSAGE}" \\
  --button1text "${SCHEDULED_CONTINUE_TEXT}" \\
  --icon "${DIALOG_ICON}" \\
  --height ${SCHEDULED_HEIGHT} \\
  --width ${SCHEDULED_WIDTH} \\
  --moveable \\
  --ontop \\
  --position "${DIALOG_POSITION}" \\
  --messagefont ${SCHEDULED_DIALOG_MESSAGEFONT} \\
  --progress ${SCHEDULED_COUNTDOWN} \\
  --progresstext "${SCHEDULED_PROGRESS_TEXT_MESSAGE}" \\
  --timer ${SCHEDULED_COUNTDOWN}

DIALOG_RESULT=\$?
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Dialog completed with status: \$DIALOG_RESULT" >> "\$LOG_FILE"

# Wait for watchdog to be ready before creating trigger file
WATCHDOG_READY_FLAG="/var/tmp/erase-install-watchdog-ready-${run_id}"
TIMEOUT=30
COUNTER=0

# Wait for watchdog to be ready or timeout
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Waiting for watchdog to be ready..." >> "\$LOG_FILE"
while [ ! -f "\$WATCHDOG_READY_FLAG" ] && [ \$COUNTER -lt \$TIMEOUT ]; do
  sleep 1
  COUNTER=\$((COUNTER + 1))
done

if [ -f "\$WATCHDOG_READY_FLAG" ]; then
  echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Watchdog is ready, creating trigger file" >> "\$LOG_FILE"
  # Create trigger file to start installation
  touch "$trigger_file"
  echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Created trigger file: $trigger_file" >> "\$LOG_FILE"
else
  echo "[\$(date '+%Y-%m-%d %H:%M:%S')] WARNING: Watchdog not ready after \$TIMEOUT seconds" >> "\$LOG_FILE"
  # Create trigger file anyway as last resort
  touch "$trigger_file"
  echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Created trigger file anyway: $trigger_file" >> "\$LOG_FILE"
fi

# Notify user that installation is starting
osascript -e 'display notification "Starting macOS installation process..." with title "macOS Upgrade"'

# Self-cleanup - unload the agent and remove it
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Unloading agent: $agent_label" >> "\$LOG_FILE"

# Try all possible methods to ensure agent is unloaded
launchctl unload "$agent_path" 2>/dev/null
launchctl remove "$agent_label" 2>/dev/null

# Use bootout as a backup method
launchctl bootout gui/\$(id -u)/"$agent_label" 2>/dev/null

# Finally remove the file
rm -f "$agent_path" 2>/dev/null
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Cleaned up LaunchAgent" >> "\$LOG_FILE"

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
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>LANG</key>
        <string>en_US.UTF-8</string>
        <key>DISPLAY</key>
        <string>:0</string>
    </dict>
</dict>
</plist>"
  
  # 2. Create a watchdog script that will monitor for the trigger file
  local watchdog_script="/Library/Management/erase-install/erase-install-watchdog-${run_id}.sh"
  mkdir -p "/Library/Management/erase-install"
  
  cat > "$watchdog_script" << EOF
#!/bin/bash

# Variables
TRIGGER_FILE="$trigger_file"
MAX_WAIT=180  # Maximum wait time in seconds
SLEEP_INTERVAL=1
RUN_ID="${run_id}"
CONSOLE_USER="$console_user"
AGENT_LABEL="$agent_label"
AGENT_PATH="$agent_path"
DAEMON_LABEL="${LAUNCHDAEMON_LABEL}.watchdog.${run_id}"
DAEMON_PATH="/Library/LaunchDaemons/\$DAEMON_LABEL.plist"
HELPER_SCRIPT="$helper_script"
WATCHDOG_SCRIPT="$watchdog_script"
LOG_FILE="/var/log/erase-install-wrapper.watchdog.\${RUN_ID}.log"
INSTALLER_OS="${INSTALLER_OS}"   # Target OS version to install
SKIP_OS_VERSION_CHECK="${SKIP_OS_VERSION_CHECK}"   # Flag to skip OS version checks for testing

# Function to create trigger file mutex
init_trigger_mutex() {
  # Create a flag to indicate watchdog is ready
  WATCHDOG_READY_FLAG="/var/tmp/erase-install-watchdog-ready-${RUN_ID}"
  
  # Wait a moment for proper initialization
  sleep 1
  
  # Create the ready flag
  touch "\$WATCHDOG_READY_FLAG"
  log_message "Watchdog initialization complete, ready for trigger file"
  
  # Clean up flag on exit
  trap 'rm -f "\$WATCHDOG_READY_FLAG" 2>/dev/null' EXIT
}

# Function to log with timestamp
log_message() {
  echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$1" >> "\$LOG_FILE"
}

# Initialize watchdog as early as possible
init_trigger_mutex

# Function to check if OS is already at or above the target version
check_os_already_updated() {
  # Get current OS version
  local current_os=\$(sw_vers -productVersion)
  log_message "Current OS version: \$current_os"
  
  # Get the target OS version from the plist
  local target_os=\$(defaults read "${PLIST}" targetOSVersion 2>/dev/null)
  if [[ -z "\$target_os" ]]; then
    # If we don't have it stored, use INSTALLER_OS
    target_os="\${INSTALLER_OS}"
    log_message "No stored target version found. Using INSTALLER_OS: \$target_os"
  else
    log_message "Using stored target OS version: \$target_os"
  fi
  
  # Extract major versions
  local current_major=\$(echo "\$current_os" | cut -d. -f1)
  local target_major=\$(echo "\$target_os" | cut -d. -f1)
  
  # Compare major versions
  if [[ \$current_major -gt \$target_major ]]; then
    log_message "Current OS major version (\$current_major) is greater than target major version (\$target_major)"
    return 0  # No update needed
  elif [[ \$current_major -lt \$target_major ]]; then
    log_message "Current OS major version (\$current_major) is less than target major version (\$target_major)"
    return 1  # Update needed
  else
    # Major versions are equal, compare minor versions
    log_message "Major versions are equal. Checking minor versions..."
    
    # Split versions by dots for comparison
    IFS='.' read -ra CURRENT_VER <<< "\$current_os"
    IFS='.' read -ra TARGET_VER <<< "\$target_os"
    
    # Compare each component
    for ((i=1; i<\${#CURRENT_VER[@]} && i<\${#TARGET_VER[@]}; i++)); do
      if [[ \${CURRENT_VER[i]} -gt \${TARGET_VER[i]} ]]; then
        log_message "Current version component \${CURRENT_VER[i]} is greater than target \${TARGET_VER[i]} at position \$i"
        return 0  # No update needed
      elif [[ \${CURRENT_VER[i]} -lt \${TARGET_VER[i]} ]]; then
        log_message "Current version component \${CURRENT_VER[i]} is less than target \${TARGET_VER[i]} at position \$i"
        return 1  # Update needed
      fi
    done
    
    # If we get here, all compared components are equal
    # If target has more components, check if they're significant
    if [[ \${#TARGET_VER[@]} -gt \${#CURRENT_VER[@]} ]]; then
      for ((i=\${#CURRENT_VER[@]}; i<\${#TARGET_VER[@]}; i++)); do
        if [[ \${TARGET_VER[i]} -gt 0 ]]; then
          log_message "Target version has additional significant component \${TARGET_VER[i]}"
          return 1  # Update needed
        fi
      done
    fi
    
    # If we get here, versions are compatible
    log_message "Current version \$current_os is compatible with target version \$target_os"
    return 0  # No update needed
  fi
}

# Function to check if OS was upgraded during deferral
check_if_os_upgraded_during_deferral() {
  log_message "Checking if OS was upgraded during deferral period..."
  
  # Get current OS version
  local current_os=\$(sw_vers -productVersion)
  log_message "Current OS version: \$current_os"
  
  # Get initial OS version when deferral started
  local initial_os=\$(defaults read "${PLIST}" initialOSVersion 2>/dev/null || echo "")
  if [[ -z "\$initial_os" ]]; then
    log_message "No initial OS version recorded. Using current OS version."
    initial_os="\$current_os"
  fi
  log_message "Initial OS version (when deferred): \$initial_os"
  
  # Get target OS version from plist
  local target_os=\$(defaults read "${PLIST}" targetOSVersion 2>/dev/null || echo "")
  if [[ -z "\$target_os" ]]; then
    log_message "No target OS version recorded. Using INSTALLER_OS value."
    target_os="\${INSTALLER_OS}"
  fi
  log_message "Target OS version: \$target_os"
  
  # Extract version components
  local current_major=\$(echo "\$current_os" | cut -d. -f1)
  local initial_major=\$(echo "\$initial_os" | cut -d. -f1)
  local target_major=\$(echo "\$target_os" | cut -d. -f1)
  
  # First, check if OS is already fully up-to-date compared to target
  log_message "Performing exact version comparison..."
  
  # Split versions into components for detailed comparison
  IFS='.' read -ra CURRENT_VER <<< "\$current_os"
  IFS='.' read -ra TARGET_VER <<< "\$target_os"
  
  # Flag to track if we need to update
  local needs_update=false
  
  # Check if major versions differ
  if [[ \${CURRENT_VER[0]} -lt \${TARGET_VER[0]} ]]; then
    log_message "Current major version (\${CURRENT_VER[0]}) is less than target (\${TARGET_VER[0]})"
    needs_update=true
  elif [[ \${CURRENT_VER[0]} -eq \${TARGET_VER[0]} ]]; then
    # Major versions match, check minor/patch versions
    log_message "Major versions match, checking minor versions..."
    
    # Compare each component after the major version
    for ((i=1; i<\${#CURRENT_VER[@]} && i<\${#TARGET_VER[@]}; i++)); do
      if [[ \${CURRENT_VER[i]} -lt \${TARGET_VER[i]} ]]; then
        log_message "Current version component \${CURRENT_VER[i]} is less than target \${TARGET_VER[i]} at position \$i"
        needs_update=true
        break
      elif [[ \${CURRENT_VER[i]} -gt \${TARGET_VER[i]} ]]; then
        log_message "Current version component \${CURRENT_VER[i]} is greater than target \${TARGET_VER[i]} at position \$i"
        break
      fi
      # If equal, continue to next component
    done
    
    # If target has more components than current, check if they're significant
    if [[ "\$needs_update" == "false" && \${#TARGET_VER[@]} -gt \${#CURRENT_VER[@]} ]]; then
      for ((i=\${#CURRENT_VER[@]}; i<\${#TARGET_VER[@]}; i++)); do
        if [[ \${TARGET_VER[i]} -gt 0 ]]; then
          log_message "Target version has additional significant component \${TARGET_VER[i]}"
          needs_update=true
          break
        fi
      done
    fi
  fi
  
  # If OS is already at or above target version, no update needed
  if [[ "\$needs_update" == "false" ]]; then
    log_message "Current OS version (\$current_os) is already at or above target version (\$target_os)"
    return 0  # No update needed
  fi
  
  # At this point, we know the current version isn't fully up-to-date
  log_message "Current OS version (\$current_os) is not fully up-to-date compared to target (\$target_os)"
  
  # Now check if a major upgrade occurred during deferral
  if [[ "\$current_major" -gt "\$initial_major" ]]; then
    log_message "Major OS upgrade detected during deferral (from \$initial_os to \$current_os)"
    
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

# Function to clean up watchdog components
cleanup_watchdog() {
  log_message "Starting cleanup of watchdog components"
  
  # Create a background cleanup process that can continue even if the main process exits
  (
    # Wait a moment to ensure main process can complete
    sleep 5
    
    # Get the UID of the console user
    local console_uid=\$(id -u "\$CONSOLE_USER")
    
    # Unload agent using multiple methods to ensure it's removed
    log_message "Unloading LaunchAgent for user \$CONSOLE_USER (UID: \$console_uid)"
    launchctl asuser "\$console_uid" sudo -u "\$CONSOLE_USER" launchctl remove "\$AGENT_LABEL" 2>/dev/null
    launchctl asuser "\$console_uid" sudo -u "\$CONSOLE_USER" launchctl unload "\$AGENT_PATH" 2>/dev/null
    launchctl asuser "\$console_uid" launchctl bootout gui/\$console_uid/"\$AGENT_LABEL" 2>/dev/null
    
    # Remove the agent file
    if [ -f "\$AGENT_PATH" ]; then
      log_message "Removing LaunchAgent file: \$AGENT_PATH"
      rm -f "\$AGENT_PATH"
    fi
    
    # Unload daemon using multiple methods to ensure it's removed
    log_message "Unloading LaunchDaemon"
    launchctl remove "\$DAEMON_LABEL" 2>/dev/null
    launchctl unload "\$DAEMON_PATH" 2>/dev/null
    launchctl bootout system/"\$DAEMON_LABEL" 2>/dev/null
    
    # Remove the daemon file
    if [ -f "\$DAEMON_PATH" ]; then
      log_message "Removing LaunchDaemon file: \$DAEMON_PATH"
      rm -f "\$DAEMON_PATH"
    fi
    
    # Remove trigger file if it exists
    if [ -f "\$TRIGGER_FILE" ]; then
      log_message "Removing trigger file: \$TRIGGER_FILE"
      rm -f "\$TRIGGER_FILE"
    fi
    
    # Remove helper script if it still exists
    if [ -f "\$HELPER_SCRIPT" ]; then
      log_message "Removing helper script: \$HELPER_SCRIPT"
      rm -f "\$HELPER_SCRIPT"
    fi
    
    # CRITICAL: Create a direct cleanup command that's guaranteed to run
    echo '#!/bin/bash
    # Aggressive cleanup script
    rm -f /Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist
    launchctl remove com.github.grahampugh.erase-install.startosinstall 2>/dev/null
    launchctl bootout system/com.github.grahampugh.erase-install.startosinstall 2>/dev/null
    
    # Remove all watchdog daemons and agents
    for file in /Library/LaunchDaemons/com.macjediwizard.eraseinstall.*.plist; do
      [ -f "$file" ] && rm -f "$file"
    done
    for file in /Users/*/Library/LaunchAgents/com.macjediwizard.eraseinstall.*.plist; do
      [ -f "$file" ] && rm -f "$file"
    done
    
    # Final log
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] Final cleanup completed" >> /var/log/erase-install-wrapper.watchdog.cleanup.log
    
    # Remove self
    rm -f "$0"
    ' > /tmp/final_cleanup.sh
    
    chmod +x /tmp/final_cleanup.sh
    
    # Schedule this to run in the next minute
    log_message "Scheduling final cleanup to run in 60 seconds"
    nohup /bin/bash -c "sleep 60 && /tmp/final_cleanup.sh" &
    
    # Clean up erase-install's files - improved version
    log_message "Cleaning up erase-install files"
    
    # Dialog command file
    rm -f /var/tmp/dialog.* 2>/dev/null
    
    # Remove any erase-install startosinstall daemon (MOST CRITICAL PART)
    if [ -f "/Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist" ]; then
      log_message "Removing startosinstall plist"
      launchctl remove "com.github.grahampugh.erase-install.startosinstall" 2>/dev/null
      launchctl bootout system/com.github.grahampugh.erase-install.startosinstall 2>/dev/null
      rm -f "/Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist" 2>/dev/null
      sleep 1
      # Double-check and force remove if needed
      if [ -f "/Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist" ]; then
        log_message "Force removing startosinstall plist"
        rm -f "/Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist" 2>/dev/null
      fi
    fi
    
    # Create a self-destruction script with elevated privileges
    echo '#!/bin/bash
    # Thorough cleanup - guaranteed to run as root
    sleep 5
    rm -f /Library/LaunchDaemons/com.macjediwizard.eraseinstall.*.plist
    rm -f /Library/LaunchDaemons/com.github.grahampugh.erase-install.*.plist

    # Remove all watchdog scripts
    rm -f /Library/Management/erase-install/erase-install-watchdog-*.sh

    # Remove self
    rm -f "$0"
    ' > /tmp/thorough_cleanup.sh

    chmod +x /tmp/thorough_cleanup.sh
    log_message "Creating thorough cleanup script to ensure complete daemon removal"
    sudo /bin/bash /tmp/thorough_cleanup.sh &
    
    # Final attempt to remove our own daemon
    log_message "Final attempt to remove watchdog daemon"
    rm -f "\$DAEMON_PATH" 2>/dev/null
    
    # Remove self (watchdog script) last
    log_message "Watchdog script cleaning up self"
    rm -f "\$WATCHDOG_SCRIPT" && log_message "Watchdog script removed"
    
    # Final message
    log_message "Cleanup completed via background process"
  ) &
  
  # Log that we've started the background cleanup process
  log_message "Background cleanup process started"
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

# Wait for trigger file to appear
COUNTER=0
log_message "Watchdog script started (PID: \$$)"
log_message "Waiting for trigger file: \$TRIGGER_FILE"
while [ ! -f "\$TRIGGER_FILE" ] && [ \$COUNTER -lt \$MAX_WAIT ]; do
  sleep \$SLEEP_INTERVAL
  COUNTER=\$((COUNTER + SLEEP_INTERVAL))
done

# If trigger file exists, first check OS version, then run erase-install if needed
if [ -f "\$TRIGGER_FILE" ]; then
  # Remove trigger file
  rm -f "\$TRIGGER_FILE"
  log_message "Trigger file found, checking OS version before starting installation"
  
  # Check if OS was upgraded during deferral
  if [[ "\$SKIP_OS_VERSION_CHECK" == "true" ]]; then
    log_message "SKIP_OS_VERSION_CHECK is enabled - testing but continuing regardless of OS version"
    # Run the check but ignore the result
    check_if_os_upgraded_during_deferral
    log_message "Test mode - proceeding with installation regardless of OS version"
  elif check_if_os_upgraded_during_deferral; then
    log_message "OS already updated to meet target version. No need to install. Exiting."
    # Display a notification to the user
    osascript -e 'display notification "Your macOS is already up to date. No installation required." with title "macOS Upgrade"'
    # Clean up and exit
    cleanup_watchdog
    exit 0
  fi
  
  # OS needs update, proceed with installation
  log_message "OS needs to be updated. Running erase-install with parameters: --reinstall --rebootdelay ${REBOOT_DELAY} $([ "$NO_FS" = true ] && echo "--no-fs") $([ "$CHECK_POWER" = true ] && echo "--check-power") --min-drive-space ${MIN_DRIVE_SPACE} $([ "$CLEANUP_AFTER_USE" = true ] && echo "--cleanup-after-use") $([ "$TEST_MODE" = true ] && echo "--test-run") $([ "$DEBUG_MODE" = true ] && echo "--verbose")"
  
  /Library/Management/erase-install/erase-install.sh --reinstall --rebootdelay ${REBOOT_DELAY} $([ "$NO_FS" = true ] && echo "--no-fs") $([ "$CHECK_POWER" = true ] && echo "--check-power") --min-drive-space ${MIN_DRIVE_SPACE} $([ "$CLEANUP_AFTER_USE" = true ] && echo "--cleanup-after-use") $([ "$TEST_MODE" = true ] && echo "--test-run") $([ "$DEBUG_MODE" = true ] && echo "--verbose")
  
  # Save exit code
  RESULT=\$?
  log_message "erase-install completed with exit code: \$RESULT"
  
  # Clean up
  cleanup_watchdog
  
  exit \$RESULT
else
  # If timeout occurred, log an error
  log_message "Timeout waiting for trigger file"
  
  # Clean up
  cleanup_watchdog
  
  exit 1
fi
EOF
  
  # Set proper permissions
  chmod +x "$watchdog_script"
  
  # 3. Create the LaunchDaemon for the watchdog
  local daemon_label="${LAUNCHDAEMON_LABEL}.watchdog.${run_id}"
  local daemon_path="/Library/LaunchDaemons/$daemon_label.plist"
  
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
  
  # Write the agent plist
  printf "%s" "${agent_content}" | sudo -u "$console_user" tee "$agent_path" > /dev/null
  sudo -u "$console_user" chmod 644 "$agent_path"
  
  # Write the daemon plist
  printf "%s" "${daemon_content}" | sudo tee "$daemon_path" > /dev/null
  # Ensure proper permissions
  sudo chown root:wheel "$daemon_path"
  sudo chmod 644 "$daemon_path"
  
  # Load the agent
  log_info "Loading LaunchAgent for UI..."
  if ! launchctl asuser "$(id -u "$console_user")" sudo -u "$console_user" launchctl bootstrap gui/"$(id -u "$console_user")" "$agent_path" 2>/dev/null; then
    # Try legacy load method
    launchctl asuser "$(id -u "$console_user")" sudo -u "$console_user" launchctl load "$agent_path"
  fi
  
  # Load the daemon with better error handling and pause
  log_info "Loading LaunchDaemon for installation..."
  
  # Add a pause to ensure previous unloading completes
  log_info "Pausing briefly to ensure previous daemon is fully unloaded..."
  sleep 3
  
  # Try multiple loading methods with better error handling
  if ! sudo launchctl bootstrap system "$daemon_path" 2>/dev/null; then
    log_warn "Bootstrap loading failed, trying traditional load method..."
    sleep 1
    if ! sudo launchctl load -w "$daemon_path" 2>/dev/null; then
      log_warn "Traditional loading failed, trying direct submit method..."
      sleep 1
      # Last resort - use submit
      if ! sudo launchctl submit -l "$daemon_label" -p "/bin/bash" -a "$watchdog_script" 2>/dev/null; then
        log_error "All loading methods failed for LaunchDaemon"
        # Don't fail completely, as the agent might still work
      else
        log_info "Successfully loaded LaunchDaemon using submit method"
      fi
    else
      log_info "Successfully loaded LaunchDaemon using traditional method"
    fi
  else
    log_info "Successfully loaded LaunchDaemon using bootstrap method"
  fi
  
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
  CURRENT_RUN_ID="${run_id}"
  
  return 0
}

# Function to perform emergency cleanup of all known daemons
emergency_daemon_cleanup() {
  log_info "Performing emergency cleanup of all LaunchDaemons"
  
  # First try normal removal
  remove_existing_launchdaemon
  
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
  
  # Handle com.github.grahampugh.erase-install.startosinstall.plist (always remove this)
  if [ -f "/Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist" ]; then
    log_info "Found startosinstall daemon - removing"
    rm -f "/Library/LaunchDaemons/com.github.grahampugh.erase-install.startosinstall.plist"
  fi
  
  # Only continue if we have no current run ID
  log_info "No active scheduled task - checking for any lingering daemons"
  
  # For the LaunchDaemons
  for daemon in /Library/LaunchDaemons/com.macjediwizard.eraseinstall.schedule.watchdog.*.plist; do
    # Skip if glob doesn't match any files
    [ ! -f "$daemon" ] && continue
    
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

# ---------------- Installer ----------------

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
  
  # Run the installation with proper user context for UI
  log_info "Starting erase-install..."
  
  # Build command with proper options
  local cmd_args=()
  cmd_args+=("${SCRIPT_PATH}")
  
  # Add options based on configuration variables
  [[ "$REBOOT_DELAY" -gt 0 ]] && cmd_args+=("--rebootdelay" "$REBOOT_DELAY")
  [[ "$REINSTALL" == "true" ]] && cmd_args+=("--reinstall")
  [[ "$NO_FS" == "true" ]] && cmd_args+=("--no-fs")
  [[ "$CHECK_POWER" == "true" ]] && cmd_args+=("--check-power")
  cmd_args+=("--min-drive-space" "$MIN_DRIVE_SPACE")
  [[ "$CLEANUP_AFTER_USE" == "true" ]] && cmd_args+=("--cleanup-after-use")
  [[ "$TEST_MODE" == "true" ]] && cmd_args+=("--test-run")
  
  if [ -z "$console_user" ] || [ "$console_user" = "root" ] || [ "$console_user" = "_mbsetupuser" ]; then
    log_warn "No valid console user detected. UI interactions may not work correctly."
  fi
  
  # Log the command we're about to run
  log_info "Running erase-install with args: ${cmd_args[*]}"
  
  # Set UI environment for the console user
  export DISPLAY=:0
  if [ -n "$console_uid" ] && [ "$console_uid" != "0" ]; then
    launchctl asuser "$console_uid" sudo -u "$console_user" defaults write org.swift.SwiftDialog FrontmostApplication -bool true
  fi
  
  # Execute with proper error handling
  if ! sudo "${cmd_args[@]}"; then
    log_error "erase-install command failed"
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
  
  # Skip countdown if show_countdown is false
  if [[ "$show_countdown" == "false" ]]; then
    log_info "Skipping pre-install countdown, proceeding directly to installation..."
    run_erase_install
    return
  fi
  
  # Create a temporary file to track countdown progress
  local tmp_progress
  tmp_progress=$(mktemp)
  echo "$countdown" > "$tmp_progress"
  
  # Launch dialog with countdown and progress bar
  "$DIALOG_BIN" --title "$display_title" \
  --message "$PREINSTALL_MESSAGE" \
  --button1text "$PREINSTALL_CONTINUE_TEXT" \
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
  
  if [[ "${DEFERRAL_EXCEEDED}" = true ]]; then
    OPTIONS="${DIALOG_INSTALL_NOW_TEXT},${DIALOG_SCHEDULE_TODAY_TEXT}"
  else
    OPTIONS="${DIALOG_INSTALL_NOW_TEXT},${DIALOG_SCHEDULE_TODAY_TEXT},${defer_text}"
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
    "${DIALOG_DEFER_TEXT}" | "${DIALOG_DEFER_TEXT_TEST_MODE}" | "Defer 5 Minutes"* | "Defer 24 Hours"*)
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
        
        # Ensure clean state
        remove_existing_launchdaemon
        
        # Create LaunchDaemon with original time values (preserving leading zeros)
        if create_scheduled_launchdaemon "${defer_hour}" "${defer_min}" "${defer_day}" "${defer_month}" "prompt"; then
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
          log_error "Failed to schedule re-prompt"
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

# ---------------- Main ----------------

# Check for test mode argument
if [[ "$1" == "--test-os-check" ]]; then
  # Enable the OS version check test mode
  SKIP_OS_VERSION_CHECK=true
  shift  # Remove this argument and continue processing others
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
    test_os_version_check
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
    "${SCRIPT_PATH}" --reinstall --rebootdelay "$REBOOT_DELAY" --no-fs --check-power --min-drive-space "$MIN_DRIVE_SPACE" --cleanup-after-use ${TEST_MODE:+--test-run}
  else
    # When running as user, we need to use the normal run_erase_install function
    log_info "Running erase-install via run_erase_install function"
    run_erase_install
  fi
  
  # Explicitly call cleanup to ensure proper exit
  cleanup_and_exit
fi

#---------------------MAIN-------------------------------
# Main script execution for non-scheduled mode
init_logging
log_info "Starting erase-install wrapper script v${SCRIPT_VERSION}"
log_system_info

# Add emergency cleanup first thing
emergency_daemon_cleanup

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
elif check_os_already_updated; then
  log_info "System is already running the target OS version. No update needed."
  
  # Show a notification to the user
  console_user=""
  console_user=$(stat -f%Su /dev/console 2>/dev/null || echo "")
  [ -z "$console_user" ] && console_user=$(who | grep "console" | awk '{print $1}' | head -n1)
  [ -z "$console_user" ] && console_user=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && !/loginwindow/ { print $3 }')
  
  if [ -n "$console_user" ] && [ "$console_user" != "root" ]; then
    console_uid=""  # Fix: Remove 'local' keyword
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