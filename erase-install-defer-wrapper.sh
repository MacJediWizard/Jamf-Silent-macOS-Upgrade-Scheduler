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
DIALOG_BIN="/usr/local/bin/dialog"

SCRIPT_VERSION="1.4.17"
INSTALLER_OS="15"
MAX_DEFERS=3
FORCE_TIMEOUT_SECONDS=259200

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
  curl -fsSL -o "${tmp}/dialog.pkg" "https://github.com/bartreardon/swiftDialog/releases/latest/download/dialog.pkg" || { log_error "Failed to download swiftDialog."; rm -rf "${tmp}"; return 1; }
  /usr/sbin/installer -pkg "${tmp}/dialog.pkg" -target / || { log_error "Installation of swiftDialog failed."; rm -rf "${tmp}"; return 1; }
  log_info "swiftDialog installed successfully."
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
  log_info "Searching for existing LaunchDaemons..."
  # Find all LaunchDaemons that contain our label (full or partial matches)
  local base_label=$(echo "${LAUNCHDAEMON_LABEL}" | cut -d. -f1-3)
  local found_daemons=$(launchctl list | grep "${base_label}" | awk '{print $3}')
  
  # Also check file system for related plist files that might not be loaded
  local fs_daemons=$(find /Library/LaunchDaemons -name "*${base_label}*" -type f 2>/dev/null)
  
  # Combine and deduplicate results
  echo "${found_daemons}"$'\n'"${fs_daemons}" | grep -v "^$" | sort | uniq
}

# Function to safely remove a single LaunchDaemon
remove_launchdaemon() {
  local daemon_path="$1"
  local daemon_label=""
  
  # Extract label from plist if it's a file path
  if [[ "${daemon_path}" == *".plist" ]]; then
    daemon_label=$(defaults read "${daemon_path}" Label 2>/dev/null)
    log_info "Processing LaunchDaemon: ${daemon_path} (Label: ${daemon_label:-unknown})"
  else
    # If we were passed a label directly
    daemon_label="${daemon_path}"
    daemon_path="/Library/LaunchDaemons/${daemon_label}.plist"
    log_info "Processing LaunchDaemon with label: ${daemon_label}"
  fi
  
  # Attempt to unload/bootout the daemon
  if launchctl list | grep -q "${daemon_label}"; then
    log_info "Unloading active LaunchDaemon: ${daemon_label}"
    if ! launchctl bootout system "${daemon_path}" 2>/dev/null; then
      log_warn "Failed to bootout LaunchDaemon via path, trying by label..."
      if ! launchctl bootout system/${daemon_label} 2>/dev/null; then
        log_error "Failed to unload LaunchDaemon: ${daemon_label}"
        return 1
      fi
    fi
  fi
  
  # Remove the file if it exists
  if [ -f "${daemon_path}" ]; then
    log_info "Removing LaunchDaemon file: ${daemon_path}"
    if ! rm -f "${daemon_path}"; then
      log_error "Failed to remove LaunchDaemon file: ${daemon_path}"
      return 1
    fi
  fi
  
  log_info "LaunchDaemon ${daemon_label:-unknown} successfully removed."
  return 0
}

# Enhanced function to remove all existing LaunchDaemons related to this script
remove_existing_launchdaemon() {
  log_info "Checking for existing LaunchDaemons to remove..."
  
  # First, try to remove the primary LaunchDaemon
  if [ -f "${LAUNCHDAEMON_PATH}" ]; then
    remove_launchdaemon "${LAUNCHDAEMON_PATH}"
  fi
  
  # Now find and remove any other related LaunchDaemons
  local daemons=$(list_existing_launchdaemons)
  local removal_count=0
  local failure_count=0
  
  if [ -n "${daemons}" ]; then
    log_info "Found additional LaunchDaemons to clean up."
    while IFS= read -r daemon; do
      [ -z "${daemon}" ] && continue
      
      # Skip if this is the same as our primary LaunchDaemon (already handled)
      if [ "${daemon}" = "${LAUNCHDAEMON_PATH}" ]; then
        continue
      fi
      
      if remove_launchdaemon "${daemon}"; then
        removal_count=$((removal_count + 1))
      else
        failure_count=$((failure_count + 1))
      fi
    done <<< "${daemons}"
    
    log_info "LaunchDaemon cleanup complete. Removed: ${removal_count}, Failed: ${failure_count}"
  else
    log_info "No additional LaunchDaemons found."
  fi
}

create_scheduled_launchdaemon() {
  local hour="$1" minute="$2" day="$3" month="$4"
  
  # Convert hour and minute to base-10 to avoid octal interpretation
  if [[ -n "$hour" ]]; then
    hour=${hour#0}
  fi
  if [[ -n "$minute" ]]; then
    minute=${minute#0}
  fi
  
  # Ensure any existing LaunchDaemons are removed first
  remove_existing_launchdaemon
  
  log_info "Creating LaunchDaemon for $(printf '%02d:%02d' $((hour)) $((minute)))${day:+ on day $day}${month:+ month $month}"
  
  # Use defaults to create a properly formatted plist file
  defaults write "${LAUNCHDAEMON_PATH}" Label "${LAUNCHDAEMON_LABEL}"
  
  # Set up program arguments array
  local args=()
  args+=("/bin/bash" "${WRAPPER_PATH}")
  # Add --scheduled parameter only for non-prompt mode
  if [[ "$5" != "prompt" ]]; then
    args+=("--scheduled")
  fi
  defaults write "${LAUNCHDAEMON_PATH}" ProgramArguments -array "${args[@]}"
  
  # Set up calendar interval
  defaults write "${LAUNCHDAEMON_PATH}" StartCalendarInterval -dict Hour ${hour} Minute ${minute}
  [[ -n "$day" ]] && defaults write "${LAUNCHDAEMON_PATH}" StartCalendarInterval.Day -int ${day}
  [[ -n "$month" ]] && defaults write "${LAUNCHDAEMON_PATH}" StartCalendarInterval.Month -int ${month}
  
  # Set RunAtLoad to false
  defaults write "${LAUNCHDAEMON_PATH}" RunAtLoad -bool false
  
  # Set proper permissions
  chmod 644 "${LAUNCHDAEMON_PATH}"
  chown root:wheel "${LAUNCHDAEMON_PATH}"
  
  # Use bootstrap instead of load for better compatibility
  launchctl bootstrap system "${LAUNCHDAEMON_PATH}" 2>/dev/null || { log_error "Failed to bootstrap LaunchDaemon"; return 1; }
  log_info "LaunchDaemon created and loaded successfully"
}

# ---------------- Installer ----------------

run_erase_install() {
  local args=( /usr/bin/sudo "$SCRIPT_PATH" --reinstall --os="$INSTALLER_OS" --no-fs --check-power --min-drive-space=50 --cleanup-after-use )
  [[ "$TEST_MODE" = true ]] && args+=( --test-run )
  log_info "Running erase-install: ${args[*]}"
  "${args[@]}"
  local code=$?
  [[ $code -ne 0 ]] && log_error "erase-install failed with exit code $code"
  return $code
}

show_preinstall() {
  local show_countdown="${1:-true}"
  local countdown=${PREINSTALL_COUNTDOWN:-60}
  
  # Skip countdown if show_countdown is false
  if [[ "$show_countdown" == "false" ]]; then
    log_info "Skipping pre-install countdown, proceeding directly to installation..."
    run_erase_install
    return
  fi
  
  log_info "Showing pre-install countdown ($countdown seconds)..."
  
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
  
  # Update countdown progress
  while [[ $countdown_remaining -gt 0 ]]; do
    # Check if the dialog is still running
    if ! kill -0 $dialog_pid 2>/dev/null; then
      # Dialog was closed/button pressed - continue immediately
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
  if kill -0 $dialog_pid 2>/dev/null; then
    kill $dialog_pid 2>/dev/null
  fi
  
  # Cleanup temp file
  rm -f "$tmp_progress"
  
  # Check if dialog was closed by user action
  if [ -f /tmp/dialog_output.json ]; then
    local btn=$(cat /tmp/dialog_output.json | grep "button" | cut -d':' -f2 | tr -d '" ,')
    log_info "Pre-install dialog returned: [$btn] (or timed out)"
    rm -f /tmp/dialog_output.json
  else
    log_info "Pre-install dialog completed countdown, continuing automatically"
  fi
  
  # Run the installation
  run_erase_install
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
  local next_hour=$((current_hour + 1))
  local time_options=""
  
  for h in $(seq "$next_hour" 23); do
    # Convert hour to base-10 explicitly to avoid octal interpretation
    local h_base10=$((h))
    local formatted_hour; formatted_hour=$(printf "%02d" "$h_base10")
    time_options="${time_options}${time_options:+,}${formatted_hour}:00,${formatted_hour}:30"
  done
  
  local count; count=$(echo "$time_options" | tr ',' '\n' | wc -l | tr -d ' ')
  if [[ "$count" -lt 3 ]]; then
    for h in $(seq 8 $((next_hour - 1))); do
      # Convert hour to base-10 explicitly to avoid octal interpretation
      local h_base10=$((h))
      local th; th=$(printf "%02d" "$h_base10")
      time_options="${time_options}${time_options:+,}Tomorrow ${th}:00"
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
    day=$(date -v+1d +%d)
    month=$(date -v+1d +%m)
    printf "tomorrow %s %s %s %s" "$hour" "$minute" "$day" "$month"
  else
    hour=$(echo "$input" | cut -d: -f1)
    minute=$(echo "$input" | cut -d: -f2)
    [[ $hour -ge 0 && $hour -le 23 && $minute -ge 0 && $minute -le 59 ]] || return 1
    printf "today %s %s" "$hour" "$minute"
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
      read -r when hour minute day month <<< "$time_data"
      
      # Convert to proper numeric values for display
      local hour_num=${hour#0}
      local minute_num=${minute#0}
      
      # Ensure existing LaunchDaemons are removed before creating a new one
      remove_existing_launchdaemon
      
      if [[ "$when" == "tomorrow" ]]; then
        log_info "Scheduling for tomorrow at $(printf '%02d:%02d' $((hour_num)) $((minute_num)))"
        create_scheduled_launchdaemon "$hour" "$minute" "$day" "$month" "install"
      else
        log_info "Scheduling for today at $(printf '%02d:%02d' $((hour_num)) $((minute_num)))"
        create_scheduled_launchdaemon "$hour" "$minute" "" "" "install"
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
        
        local defer_hour; defer_hour=$(date -v+24H +%H)
        local defer_min; defer_min=$(date -v+24H +%M)
        local defer_day; defer_day=$(date -v+1d +%d)
        local defer_month; defer_month=$(date -v+1d +%m)
        
        # Convert to base-10 to avoid octal interpretation
        local defer_hour_num=${defer_hour#0}
        local defer_min_num=${defer_min#0}
        
        # Ensure existing LaunchDaemons are removed before creating a new one
        remove_existing_launchdaemon
        
        # Create the LaunchDaemon for tomorrow
        create_scheduled_launchdaemon "$defer_hour" "$defer_min" "$defer_day" "$defer_month" "prompt"
        log_info "Scheduled re-prompt for tomorrow at $(printf '%02d:%02d' "$defer_hour_num" "$defer_min_num")"
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
  init_logging
  log_info "Running in scheduled mode"
  log_system_info
  dependency_check
  # Ensure any existing LaunchDaemons are removed before running erase-install
  remove_existing_launchdaemon
  # Show pre-install countdown window for scheduled installations
  log_info "Running scheduled installation with countdown"
  show_preinstall "true"
  exit 0
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
