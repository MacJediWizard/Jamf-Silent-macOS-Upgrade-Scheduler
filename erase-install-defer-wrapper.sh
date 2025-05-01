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
#########################################################################################################################################################################

# ---------------- Configuration ----------------

PLIST="/Library/Preferences/com.macjediwizard.eraseinstall.plist"
SCRIPT_PATH="/Library/Management/erase-install/erase-install.sh"
DIALOG_BIN="/Library/Management/erase-install/Dialog.app/Contents/MacOS/Dialog"
# Fallback to traditional location if primary doesn't exist
[ ! -x "$DIALOG_BIN" ] && DIALOG_BIN="/usr/local/bin/dialog"

SCRIPT_VERSION="1.4.18"
INSTALLER_OS="15"
MAX_DEFERS=3
FORCE_TIMEOUT_SECONDS=259200

# Set to false for production
TEST_MODE=true
AUTO_INSTALL_DEPENDENCIES=true
DEBUG_MODE=true

LAUNCHDAEMON_LABEL="com.macjediwizard.eraseinstall.schedule"
LAUNCHDAEMON_PATH="/Library/LaunchDaemons/${LAUNCHDAEMON_LABEL}.plist"
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

WRAPPER_LOG="/var/log/erase-install-wrapper.log"
MAX_LOG_SIZE_MB=10
MAX_LOG_FILES=5

# ---------------- Logging ----------------

init_logging() {
  local log_dir; log_dir=$(dirname "${WRAPPER_LOG}")
  [[ -d "${log_dir}" ]] || mkdir -p "${log_dir}"
  
  if [[ -f "${WRAPPER_LOG}" ]]; then
    local current_size; current_size=$(du -m "${WRAPPER_LOG}" | cut -f1)
    if [[ ${current_size} -gt ${MAX_LOG_SIZE_MB} ]]; then
      for i in $(seq $((MAX_LOG_FILES-1)) -1 1); do
        [[ -f "${WRAPPER_LOG}.${i}" ]] && mv "${WRAPPER_LOG}.${i}" "${WRAPPER_LOG}.$((i+1))"
      done
      mv "${WRAPPER_LOG}" "${WRAPPER_LOG}.1"
      touch "${WRAPPER_LOG}"
      printf "[INFO]    [%s] Log file rotated due to size (%sMB)\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$current_size" | tee -a "${WRAPPER_LOG}"
    fi
  fi
  
  touch "${WRAPPER_LOG}"
  chmod 644 "${WRAPPER_LOG}"
}

log_info()    { printf "[INFO]    [%s] %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1" | tee -a "${WRAPPER_LOG}"; }
log_warn()    { printf "[WARN]    [%s] %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1" | tee -a "${WRAPPER_LOG}"; }
log_error()   { printf "[ERROR]   [%s] %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1" | tee -a "${WRAPPER_LOG}" >&2; }
log_debug()   { [[ "${DEBUG_MODE}" = true ]] && printf "[DEBUG]   [%s] %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1" | tee -a "${WRAPPER_LOG}"; }
log_system()  { printf "[SYSTEM]  [%s] %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1" | tee -a "${WRAPPER_LOG}"; }

log_system_info() {
  log_system "Script Version: ${SCRIPT_VERSION}"
  log_system "macOS Version: $(sw_vers -productVersion)"
  log_system "Hardware Model: $(sysctl -n hw.model)"
  log_system "Available Disk Space: $(df -h / | awk 'NR==2 {print $4}')"
  log_system "Current User: $(whoami)"
  log_system "Dialog Version: $("${DIALOG_BIN}" --version 2>/dev/null || echo 'Not installed')"
  
  if [ -f "${SCRIPT_PATH}" ]; then
    local erase_install_ver; erase_install_ver=$(grep -m1 -A1 '^# Version of this script' "${SCRIPT_PATH}" | grep -m1 -oE 'version="[^"]+"' | cut -d'"' -f2)
    [[ -z "${erase_install_ver}" ]] && erase_install_ver="Unknown"
    log_system "Erase-Install Version: ${erase_install_ver}"
  else
    log_system "Erase-Install Version: Not installed"
  fi
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
  [ -x "${SCRIPT_PATH}" ] || { [ "${AUTO_INSTALL_DEPENDENCIES}" = true ] && install_erase_install || { log_error "erase-install missing and auto-install disabled"; exit 1; }; }
  [ -x "${DIALOG_BIN}" ] || { [ "${AUTO_INSTALL_DEPENDENCIES}" = true ] && install_swiftDialog || { log_error "swiftDialog missing and auto-install disabled"; exit 1; }; }
}

# ---------------- Deferral State ----------------

init_plist() {
  if [[ ! -f "${PLIST}" ]]; then
    defaults write "${PLIST}" scriptVersion -string "${SCRIPT_VERSION}"
    defaults write "${PLIST}" deferCount -int 0
    defaults write "${PLIST}" firstPromptDate -string "$(date -u +%s)"
  else
    local ver; ver=$(defaults read "${PLIST}" scriptVersion 2>/dev/null || echo "")
    if [[ "${ver}" != "${SCRIPT_VERSION}" ]]; then
      log_info "New version detected; resetting deferral history."
      defaults write "${PLIST}" scriptVersion -string "${SCRIPT_VERSION}"
      defaults write "${PLIST}" deferCount -int 0
      defaults write "${PLIST}" firstPromptDate -string "$(date -u +%s)"
    fi
  fi
  
  defaults read "${PLIST}" deferCount &>/dev/null || defaults write "${PLIST}" deferCount -int 0
  defaults read "${PLIST}" firstPromptDate &>/dev/null || defaults write "${PLIST}" firstPromptDate -string "$(date -u +%s)"
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

# Function to list all existing LaunchDaemons related to this script
list_existing_launchdaemons() {
  log_debug "Searching for existing LaunchDaemons..."
  # Use a static base label for consistent search
  local base_label="com.macjediwizard.eraseinstall"
  local loaded_daemons="" fs_daemons=""
  
  # First, get loaded daemons
  if launchctl list &>/dev/null; then
    loaded_daemons=$(launchctl list 2>/dev/null | grep -F "${base_label}" | awk '{print $3}' 2>/dev/null || echo "")
  fi
  
  # Then, get filesystem daemons (both active and backup)
  if [ -d "/Library/LaunchDaemons" ]; then
    fs_daemons=$(find /Library/LaunchDaemons -type f \( -name "${base_label}*.plist" -o -name "${base_label}*.plist.bak" \) 2>/dev/null || echo "")
  fi
  
  # Return unique entries, filtering empty lines
  (echo "${loaded_daemons}"; echo "${fs_daemons}") | grep -v '^[[:space:]]*$' | sort -u
}

# Function to safely remove a single LaunchDaemon
remove_existing_launchdaemon() {
  log_info "Checking for existing LaunchDaemons to remove..."
  local found_count=0 
  local removed_count=0
  
  # Check if this is a scheduled run
  local is_scheduled=false
  [[ "$1" == "--preserve-scheduled" ]] && is_scheduled=true
  
  # First bootout any non-scheduled daemons
  launchctl list 2>/dev/null | grep -F "com.macjediwizard.eraseinstall" | while read -r pid status label; do
    if [ -n "${label}" ]; then
      # Skip scheduled daemons if we're preserving them
      if [[ "${is_scheduled}" == "true" ]] && sudo launchctl list "${label}" 2>/dev/null | grep -q -- "--scheduled"; then
        log_info "Preserving scheduled daemon: ${label}"
        continue
      fi
      
      log_info "Booting out daemon: ${label}"
      if ! sudo launchctl bootout system/$(sudo launchctl list | grep "${label}" | awk '{print $3}'); then
        log_error "Failed to bootout: ${label}"
      else
        log_info "Successfully booted out: ${label}"
      fi
    fi
  done
  
  # Then remove matching files, preserving scheduled if needed
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
    fi
  done < <(find /Library/LaunchDaemons -type f \( -name "com.macjediwizard.eraseinstall*.plist" -o -name "com.macjediwizard.eraseinstall*.plist.bak" \) 2>/dev/null)
  
  # Final explicit check and removal of known paths
  for file in "${LAUNCHDAEMON_PATH}" "${LAUNCHDAEMON_PATH}.bak"; do
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
  
  # Report results
  if [ ${found_count} -gt 0 ]; then
    log_info "LaunchDaemon cleanup complete. Removed: ${removed_count}, Failed: $((found_count - removed_count))"
  else
    log_debug "No LaunchDaemons found to remove"
  fi
  
  # Verify cleanup
  if [ -f "${LAUNCHDAEMON_PATH}" ] || [ -f "${LAUNCHDAEMON_PATH}.bak" ]; then
    log_error "LaunchDaemon cleanup incomplete - files still exist"
    return 1
  fi
  
  return 0
}

create_scheduled_launchdaemon() {
  local hour="$1" minute="$2" day="$3" month="$4" mode="$5"
  
  # Convert all values to base-10 integers
  local hour_num=$((10#${hour}))
  local minute_num=$((10#${minute}))
  local day_num=$([ -n "$day" ] && printf '%d' "$((10#${day}))" || echo "")
  local month_num=$([ -n "$month" ] && printf '%d' "$((10#${month}))" || echo "")
  
  # Get console user for user-level agent
  local console_user=""
  console_user=$(stat -f%Su /dev/console 2>/dev/null || echo "")
  [ -z "$console_user" ] && console_user=$(who | grep "console" | awk '{print $1}' | head -n1)
  [ -z "$console_user" ] && console_user=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && !/loginwindow/ { print $3 }')
  
  # Use user-level agent instead of system daemon
  local user_agent_dir="/Users/$console_user/Library/LaunchAgents"
  local user_agent_label="$LAUNCHDAEMON_LABEL"
  local user_agent_path="$user_agent_dir/$user_agent_label.plist"
  
  # Remove existing daemons and ensure clean state
  remove_existing_launchdaemon
  
  # Ensure the target directory exists
  sudo -u "$console_user" mkdir -p "$user_agent_dir"
  
  # Double-check no files exist before creating new ones
  sudo -u "$console_user" rm -f "$user_agent_path" 2>/dev/null
  
  log_info "Creating LaunchAgent for user $console_user at $(printf '%02d:%02d' "${hour_num}" "${minute_num}")${day:+ on day $day_num}${month:+ month $month_num}"
  
  # Create the plist content for user agent
  local plist_content="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key>
    <string>${user_agent_label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${WRAPPER_PATH}</string>
        <string>--scheduled</string>
        <string>--user-scheduled</string>
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

  # Write plist content as the user
  printf "%s" "${plist_content}" | sudo -u "$console_user" tee "$user_agent_path" > /dev/null
  
  # Set proper permissions
  sudo -u "$console_user" chmod 644 "$user_agent_path"
  
  # Validate plist
  if ! plutil -lint "$user_agent_path"; then
    log_error "Invalid LaunchAgent plist"
    sudo -u "$console_user" rm -f "$user_agent_path"
    return 1
  fi
  
  # Display plist content for debugging
  log_debug "Generated plist content:"
  log_debug "$(plutil -p "$user_agent_path")"
  
  # Bootstrap the agent with launchctl for the user
  log_info "Bootstrapping LaunchAgent..."
  local console_uid
  console_uid=$(id -u "$console_user")
  
  if ! sudo launchctl asuser "$console_uid" launchctl load "$user_agent_path"; then
    log_error "Failed to bootstrap LaunchAgent"
    sudo -u "$console_user" rm -f "$user_agent_path"
    return 1
  fi
  
  # Give the system a moment to process the bootstrap
  sleep 1
  
  # Verify the agent is loaded and properly configured
  local agent_status
  agent_status=$(sudo launchctl asuser "$console_uid" launchctl list | grep "${user_agent_label}" || echo "")
  if [[ -z "${agent_status}" ]]; then
    log_error "LaunchAgent not found after bootstrap"
    sudo -u "$console_user" rm -f "$user_agent_path"
    return 1
  fi
  
  # Double
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
  local args=( /usr/bin/sudo "$SCRIPT_PATH" --reinstall --os="$INSTALLER_OS" --no-fs --check-power --min-drive-space=50 --cleanup-after-use )
  [[ "$TEST_MODE" = true ]] && args+=( --test-run )
  log_info "Running erase-install: ${args[*]}"
  
  # Set UI environment for the console user
  export DISPLAY=:0
  launchctl asuser "$console_uid" sudo -u "$console_user" defaults write org.swift.SwiftDialog FrontmostApplication -bool true
  
  # Execute with proper error handling
  if ! "${args[@]}"; then
    log_error "erase-install command failed"
    return 1
  fi
  
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
  "$DIALOG_BIN" --title "$PREINSTALL_TITLE" \
    --message "$PREINSTALL_MESSAGE" \
    --button1text "$PREINSTALL_CONTINUE_TEXT" \
    --height 180 \
    --width 450 \
    --moveable \
    --icon "$DIALOG_ICON" \
    --ontop \
    --progress "$countdown" \
    --progresstext "Starting in $countdown seconds..." \
    --position "$DIALOG_POSITION" \
    --jsonoutput > /tmp/dialog_output.json &
  
  local dialog_pid=$!
  local countdown_remaining=$countdown
  local dialog_closed=false
  
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
  run_erase_install
  
  # Final cleanup
  remove_existing_launchdaemon
  log_info "Installation sequence completed"
}

# -------------- Prompt Handling --------------

DIALOG_TITLE="macOS Upgrade Required"
DIALOG_MESSAGE="Please install macOS ${INSTALLER_OS}. Select an action:"
DIALOG_ICON="SF=gear"
DIALOG_POSITION="topright"
DIALOG_INSTALL_NOW_TEXT="Install Now"
DIALOG_SCHEDULE_TODAY_TEXT="Schedule Today"
DIALOG_DEFER_TEXT="Defer 24 Hours"
PREINSTALL_TITLE="macOS Upgrade Starting"
PREINSTALL_MESSAGE="Your upgrade will begin in 60 seconds.\nClick Continue to start immediately."
PREINSTALL_CONTINUE_TEXT="Continue Now"
PREINSTALL_COUNTDOWN=60

set_options() {
  [[ "${DEFERRAL_EXCEEDED}" = true ]] && OPTIONS="${DIALOG_INSTALL_NOW_TEXT},${DIALOG_SCHEDULE_TODAY_TEXT}" || OPTIONS="${DIALOG_INSTALL_NOW_TEXT},${DIALOG_SCHEDULE_TODAY_TEXT},${DIALOG_DEFER_TEXT}"
}

generate_time_options() {
  local current_hour; current_hour=$(date +%-H)
  local current_minute; current_minute=$(date +%-M)
  local next_hour=$((current_hour + 1))
  local time_options=""
  
  # For current hour, only show future times (in 15-minute intervals)
  if [ $current_minute -lt 45 ]; then
    local formatted_hour; formatted_hour=$(printf "%02d" "$current_hour")
    # Calculate next available 15-minute interval
    if [ $current_minute -lt 15 ]; then
      time_options="${formatted_hour}:15"
    fi
    if [ $current_minute -lt 30 ]; then
      time_options="${time_options}${time_options:+,}${formatted_hour}:30"
    fi
    if [ $current_minute -lt 45 ]; then
      time_options="${time_options}${time_options:+,}${formatted_hour}:45"
    fi
  fi
  
  # For remaining hours of the day
  for h in $(seq "$next_hour" 23); do
    # Convert hour to base-10 explicitly to avoid octal interpretation
    local h_base10=$((h))
    local formatted_hour; formatted_hour=$(printf "%02d" "$h_base10")
    time_options="${time_options}${time_options:+,}${formatted_hour}:00,${formatted_hour}:15,${formatted_hour}:30,${formatted_hour}:45"
  done
  
  local count; count=$(echo "$time_options" | tr ',' '\n' | wc -l | tr -d ' ')
  if [[ "$count" -lt 3 ]]; then
    for h in $(seq 8 $((next_hour - 1))); do
      # Convert hour to base-10 explicitly to avoid octal interpretation
      local h_base10=$((h))
      local th; th=$(printf "%02d" "$h_base10")
      time_options="${time_options}${time_options:+,}Tomorrow ${th}:00,Tomorrow ${th}:15,Tomorrow ${th}:30,Tomorrow ${th}:45"
    done
  fi
  
  printf "%s" "$time_options"
}

validate_time() {
  local input="$1"
  local hour minute day month
  
  if [[ "$input" == "Tomorrow "* ]]; then
    local t; t=$(echo "$input" | awk '{print $2}')
    hour=$(echo "$t" | cut -d: -f1)
    minute=$(echo "$t" | cut -d: -f2)
    # Convert hour to base 10 to handle leading zeros
    hour=$((10#${hour}))
    day=$(date -v+1d +%d)
    month=$(date -v+1d +%m)
    printf "tomorrow %02d %s %s %s" "$hour" "$minute" "$day" "$month"
  else
    hour=$(echo "$input" | cut -d: -f1)
    minute=$(echo "$input" | cut -d: -f2)
    # Convert hour to base 10 to handle leading zeros
    hour=$((10#${hour}))
    [[ $hour -ge 0 && $hour -le 23 && $((10#$minute)) -ge 0 && $((10#$minute)) -le 59 ]] || return 1
    printf "today %02d %s" "$hour" "$minute"
  fi
}

show_prompt() {
  log_info "Displaying SwiftDialog dropdown prompt."
  local raw; raw=$("${DIALOG_BIN}" --title "${DIALOG_TITLE}" --message "${DIALOG_MESSAGE}" --button1text "Confirm" --height 250 --width 550 --moveable --icon "${DIALOG_ICON}" --ontop --timeout 0 --showicon true --position "${DIALOG_POSITION}" --messagefont "size=14" --selecttitle "Select an action:" --select --selectvalues "${OPTIONS}" --selectdefault "${DIALOG_INSTALL_NOW_TEXT}" --jsonoutput 2>&1 | tee -a "${WRAPPER_LOG}")
  local code=$?
  log_debug "SwiftDialog exit code: ${code}"
  log_debug "SwiftDialog raw output: ${raw}"
  
  [[ $code -ne 0 || -z "$raw" ]] && { log_warn "No valid JSON from SwiftDialog; aborting."; exit 1; }
  
  local selection; selection=$(parse_dialog_output "$raw" "SelectedOption")
  [[ -z "$selection" || "$selection" == "null" ]] && { log_warn "No selection made; aborting."; exit 1; }
  log_info "User selected: ${selection}"
  
  case "$selection" in
    "${DIALOG_INSTALL_NOW_TEXT}")
      # Ensure any existing LaunchDaemons are removed for "Install Now"
      remove_existing_launchdaemon
      reset_deferrals
      # Skip countdown for immediate installations - go directly to installation
      log_info "Install Now selected - proceeding directly to installation"
      run_erase_install
    ;;
    "${DIALOG_SCHEDULE_TODAY_TEXT}")
      local sched subcode time_data hour minute day month
      local time_options; time_options=$(generate_time_options)
      local sub; sub=$("${DIALOG_BIN}" --title "Schedule Installation" --message "Select installation time:" --button1text "Confirm" --height 280 --width 500 --moveable --icon "${DIALOG_ICON}" --ontop --timeout 0 --showicon true --position "${DIALOG_POSITION}" --messagefont "size=14" --selecttitle "Choose time:" --select --selectvalues "${time_options}" --selectdefault "$(echo "$time_options" | cut -d',' -f1)" --jsonoutput 2>&1 | tee -a "${WRAPPER_LOG}")
      subcode=$?
      log_debug "Schedule dialog exit code: ${subcode}"
      log_debug "Schedule raw output: ${sub}"
      [[ $subcode -ne 0 || -z "$sub" ]] && { log_warn "No time selected; aborting."; exit 1; }
      sched=$(parse_dialog_output "$sub" "SelectedOption")
      [[ -z "$sched" || "$sched" == "null" ]] && { log_warn "No time selected; aborting."; exit 1; }
      log_info "Selected time: ${sched}"
      
      time_data=$(validate_time "$sched")
      if [[ $? -ne 0 || -z "$time_data" ]]; then
        log_warn "Invalid time selection: $sched"
        exit 1
      fi
      
      # Parse time data
      # Parse time data
      read -r when hour minute day month <<< "$time_data"
      
      # Convert to proper numeric values for display
      local hour_num=${hour#0}
      local minute_num=${minute#0}
      
      # Remove any existing daemons
      remove_existing_launchdaemon
      
      if [[ "$when" == "tomorrow" ]]; then
        log_info "Scheduling for tomorrow at $(printf '%02d:%02d' $((hour_num)) $((minute_num)))"
        if ! create_scheduled_launchdaemon "$hour" "$minute" "$day" "$month" "scheduled"; then
          log_error "Failed to create scheduled LaunchDaemon for tomorrow"
          exit 1
        fi
      else
        log_info "Scheduling for today at $(printf '%02d:%02d' $((hour_num)) $((minute_num)))"
        if ! create_scheduled_launchdaemon "${hour}" "${minute}" "" "" "scheduled"; then
          log_error "Failed to create scheduled LaunchDaemon"
          exit 1
        fi
      fi
      
      reset_deferrals
    ;;
    "${DIALOG_DEFER_TEXT}")
      if [[ "${DEFERRAL_EXCEEDED}" = true ]]; then
        log_warn "Maximum deferrals (${MAX_DEFERS}) reached."
        reset_deferrals
        # Show countdown for installations after deferral expiry
        show_preinstall "true"
      else
        newCount=$((deferCount + 1))
        defaults write "${PLIST}" deferCount -int "$newCount"
        log_info "Deferred (${newCount}/${MAX_DEFERS})"
        
        # Get tomorrow's time
        local defer_hour; defer_hour=$(date -v+24H +%H)
        local defer_min; defer_min=$(date -v+24H +%M)
        local defer_day; defer_day=$(date -v+1d +%d)
        local defer_month; defer_month=$(date -v+1d +%m)
        
        # Ensure clean state
        remove_existing_launchdaemon
        
        # Create LaunchDaemon with original time values (preserving leading zeros)
        if create_scheduled_launchdaemon "${defer_hour}" "${defer_min}" "${defer_day}" "${defer_month}" "prompt"; then
            # Base-10 conversion only for display
            local display_hour=$((10#${defer_hour}))
            local display_min=$((10#${defer_min}))
            log_info "Scheduled re-prompt for tomorrow at $(printf '%02d:%02d' "${display_hour}" "${display_min}")"
        else
            log_error "Failed to schedule re-prompt"
            exit 1
        fi
      fi
      ;;
    *)
      log_warn "Unexpected selection: $selection"
      exit 1
    ;;
  esac
  
  exit 0
}

# ---------------- Main ----------------

if [[ "$1" == "--scheduled" ]]; then
  # Initialize logging first
  init_logging
  log_info "Starting scheduled installation process (PID: $$)"
  
  # Define cleanup function
  cleanup_and_exit() {
    local exit_code=$?
    log_info "Cleaning up scheduled installation process"
    # Try to remove LaunchDaemon multiple times if needed
    local retries=3
    while [ $retries -gt 0 ]; do
      if remove_existing_launchdaemon; then
        break
      fi
      retries=$((retries - 1))
      [ $retries -gt 0 ] && sleep 1
    done
    if [ -n "$LOCK_FILE" ]; then
      rm -rf "$LOCK_FILE" "$LOCK_TIMESTAMP"
    fi
    log_info "Scheduled installation process completed (exit code: $exit_code)"
    exit $exit_code
  }
  
  # Set up trap immediately
  trap 'cleanup_and_exit' EXIT TERM INT
  
  # Create a timestamped lock file for better tracking
  LOCK_FILE="/var/run/erase-install-wrapper.lock"
  LOCK_TIMESTAMP="/var/run/erase-install-wrapper.timestamp"
  
  # Check if another instance is already running
  if ! mkdir "$LOCK_FILE" 2>/dev/null; then
    if [ -f "$LOCK_TIMESTAMP" ]; then
      LOCK_AGE=$(($(date +%s) - $(cat "$LOCK_TIMESTAMP")))
      if [ $LOCK_AGE -gt 300 ]; then  # 5 minutes
        log_warn "Removing stale lock file (age: ${LOCK_AGE}s)"
        rm -rf "$LOCK_FILE" "$LOCK_TIMESTAMP"
        mkdir "$LOCK_FILE"
      else
        log_error "Another instance is running (started ${LOCK_AGE}s ago). Exiting."
        exit 1
      fi
    else
      log_error "Lock file exists but no timestamp found. Cleaning up."
      rm -rf "$LOCK_FILE"
      mkdir "$LOCK_FILE"
    fi
  fi
  
  # Record start time
  date +%s > "$LOCK_TIMESTAMP"
  
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
  launchctl asuser "$console_uid" sudo -u "$console_user" defaults write org.swift.SwiftDialog FrontmostApplication -bool true
  
  # Set dialog configuration for scheduled runs
  PREINSTALL_MESSAGE="Your scheduled macOS upgrade is ready to begin.\n\nThe upgrade will start automatically in 60 seconds, or click Continue to begin now."
  DIALOG_POSITION="center"
  DIALOG_ICON="SF=gearshape.circle.fill"
  
  # Run dialog as user with proper environment - enhanced for visibility
  log_info "Displaying scheduled installation dialog for user: $console_user"
  log_info "About to display dialogs for user: '$console_user' with UID: $console_uid"
  
  # First, try a simple notification to alert the user
  log_debug "Attempting AppleScript notification"
  sudo -i -u "$console_user" osascript -e "
    tell application \"System Events\"
      activate
      display dialog \"macOS Upgrade Scheduled\" buttons {\"OK\"} default button \"OK\" with title \"$PREINSTALL_TITLE\" with icon note giving up after 5
    end tell
  " 2>&1 | log_debug "AppleScript result: $(cat -)" || log_debug "AppleScript notification failed"
  
  # Then use a more robust way to run the dialog with multiple techniques to ensure visibility
  log_debug "Attempting SwiftDialog display via launchctl asuser"
  sudo launchctl asuser "$console_uid" sudo -u "$console_user" bash -c "
    export DISPLAY=:0
    export XAUTHORITY=/Users/$console_user/.Xauthority 2>/dev/null
    export PATH='/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'
    
    # Ensure dialog gets focus by using AppleScript
    osascript -e 'tell application \"System Events\" to activate' &
    
    \"$DIALOG_BIN\" --title \"$PREINSTALL_TITLE\" \\
      --message \"$PREINSTALL_MESSAGE\" \\
      --button1text \"$PREINSTALL_CONTINUE_TEXT\" \\
      --icon \"$DIALOG_ICON\" \\
      --height 200 \\
      --width 500 \\
      --moveable \\
      --ontop \\
      --forefront \\
      --position center \\
      --messagefont 'size=14' \\
      --blurscreen \\
      --progress 60 \\
      --progresstext \"Installation will begin in 60 seconds...\" \\
      --timer 60 \\
      --bannerimage \"/System/Library/PreferencePanes/SoftwareUpdate.prefPane/Contents/Resources/SoftwareUpdate.icns\" \\
      --bannertitle \"Scheduled macOS Upgrade\" \\
      --quitkey k"

  sleep 2  # Brief pause to ensure dialog is displayed

  # Run the actual installation
  log_info "Starting installation process"
  run_erase_install
  
  # Explicitly call cleanup to ensure proper exit
  cleanup_and_exit
fi

init_logging
log_info "Starting erase-install wrapper script v${SCRIPT_VERSION}"
log_system_info
dependency_check
init_plist
get_deferral_state
set_options
show_prompt

exit 0
