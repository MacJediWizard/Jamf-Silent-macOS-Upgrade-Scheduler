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

SCRIPT_VERSION="1.4.9"            # ← Bump this on every release!
INSTALLER_OS="15"                 # macOS Version e.g. 14=Sonoma, 15=Sequoia
MAX_DEFERS=3                       # Max allowed 24-hour deferrals per script version
FORCE_TIMEOUT_SECONDS=259200       # 72 hours total window

TEST_MODE=true                     # Dry-run without real install
AUTO_INSTALL_DEPENDENCIES=true     # Auto-install missing dependencies
DEBUG_MODE=true                    # Enable debug logging

LAUNCHDAEMON_LABEL="com.macjediwizard.eraseinstall.schedule"
LAUNCHDAEMON_PATH="/Library/LaunchDaemons/${LAUNCHDAEMON_LABEL}.plist"

# ---------------- Logging System ----------------

# Log file configuration
WRAPPER_LOG="/var/log/erase-install-wrapper.log"
MAX_LOG_SIZE_MB=10
MAX_LOG_FILES=5

# Initialize logging system
init_logging() {
    # Create log directory if it doesn't exist
    log_dir=$(dirname "${WRAPPER_LOG}")
    [[ -d "${log_dir}" ]] || mkdir -p "${log_dir}"

    # Rotate logs if needed
    if [[ -f "${WRAPPER_LOG}" ]]; then
        current_size=$(du -m "${WRAPPER_LOG}" | cut -f1)
        if [[ ${current_size} -gt ${MAX_LOG_SIZE_MB} ]]; then
            # Rotate existing logs
            for i in $(seq $((MAX_LOG_FILES-1)) -1 1); do
                [[ -f "${WRAPPER_LOG}.${i}" ]] && mv "${WRAPPER_LOG}.${i}" "${WRAPPER_LOG}.$((i+1))"
            done
            mv "${WRAPPER_LOG}" "${WRAPPER_LOG}.1"
            touch "${WRAPPER_LOG}"
            echo "[INFO]    [$(date +'%Y-%m-%d %H:%M:%S')] Log file rotated due to size (${current_size}MB)" | tee -a "${WRAPPER_LOG}"
        fi
    fi

    # Ensure log file exists and has correct permissions
    touch "${WRAPPER_LOG}"
    chmod 644 "${WRAPPER_LOG}"
}

# Enhanced logging functions
log_info()    { echo "[INFO]    [$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${WRAPPER_LOG}"; }
log_warn()    { echo "[WARN]    [$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${WRAPPER_LOG}"; }
log_error()   { echo "[ERROR]   [$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${WRAPPER_LOG}" >&2; }
log_debug()   { [[ "${DEBUG_MODE}" = true ]] && echo "[DEBUG]   [$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${WRAPPER_LOG}"; }
log_trace()   { [[ "${DEBUG_MODE}" = true ]] && echo "[TRACE]   [$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${WRAPPER_LOG}"; }
log_verbose() { [[ "${DEBUG_MODE}" = true ]] && echo "[VERBOSE] [$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${WRAPPER_LOG}"; }
log_system()  { echo "[SYSTEM]  [$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${WRAPPER_LOG}"; }
log_audit()   { echo "[AUDIT]   [$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${WRAPPER_LOG}"; }

# System information logging
log_system_info() {
    log_system "Script Version: ${SCRIPT_VERSION}"
    log_system "macOS Version: $(sw_vers -productVersion)"
    log_system "Hardware Model: $(sysctl -n hw.model)"
    log_system "Available Disk Space: $(df -h / | awk 'NR==2 {print $4}')"
    log_system "Current User: $(whoami)"
    log_system "Dialog Version: $("${DIALOG_BIN}" --version 2>/dev/null || echo 'Not installed')"
    if [ -f "${SCRIPT_PATH}" ]; then
      # Grab the version number that follows your “# Version of this script” comment
      erase_install_ver=$(grep -m1 -A1 '^# Version of this script' "${SCRIPT_PATH}" \
      | grep -m1 -oE 'version="[^"]+"' \
      | cut -d'"' -f2)
      
      # Fallback if nothing was found
      if [ -z "${erase_install_ver}" ]; then
        erase_install_ver="Unknown"
      fi
      
      log_system "Erase-Install Version: ${erase_install_ver}"
    else
      log_system "Erase-Install Version: Not installed"
    fi
}

# ---------------- Dialog Text Configuration ----------------

DIALOG_TITLE="macOS Upgrade Required"
DIALOG_MESSAGE="Please install macOS ${INSTALLER_OS}. Select an action:"
DIALOG_INSTALL_NOW_TEXT="Install Now"
DIALOG_SCHEDULE_TODAY_TEXT="Schedule Today"
DIALOG_DEFER_TEXT="Defer 24 Hours"

# Set OPTIONS based on deferral count
set_options() {
    if [[ "${DEFERRAL_EXCEEDED}" = true ]]; then
        OPTIONS="${DIALOG_INSTALL_NOW_TEXT},${DIALOG_SCHEDULE_TODAY_TEXT}"
    else
        OPTIONS="${DIALOG_INSTALL_NOW_TEXT},${DIALOG_SCHEDULE_TODAY_TEXT},${DIALOG_DEFER_TEXT}"
    fi
}

DIALOG_ICON="SF=gear"
DIALOG_POSITION="topright"

# ---------------- Helper Functions ----------------

# ---------------- Dependency Installers ----------------

install_erase_install() {
    log_info "erase-install not found. Downloading and installing..."
    tmp=$(mktemp -d)
    curl -fsSL -o "${tmp}/erase-install.pkg" \
        "https://github.com/grahampugh/erase-install/releases/latest/download/erase-install.pkg" || { log_error "Failed to download erase-install."; exit 1; }
    /usr/sbin/installer -pkg "${tmp}/erase-install.pkg" -target / && log_info "erase-install installed." || { log_error "Installation failed."; exit 1; }
    rm -rf "${tmp}"
}

install_swiftDialog() {
    log_info "swiftDialog not found. Downloading and installing..."
    tmp=$(mktemp -d)
    curl -fsSL -o "${tmp}/dialog.pkg" \
        "https://github.com/bartreardon/swiftDialog/releases/latest/download/dialog.pkg" || { log_error "Failed to download swiftDialog."; exit 1; }
    /usr/sbin/installer -pkg "${tmp}/dialog.pkg" -target / && log_info "swiftDialog installed." || { log_error "Installation failed."; exit 1; }
    rm -rf "${tmp}"
}

dependency_check(){
    [ -x "${SCRIPT_PATH}" ] || { ${AUTO_INSTALL_DEPENDENCIES} && install_erase_install || { log_error "erase-install missing"; exit 1; }; }
    [ -x "${DIALOG_BIN}"   ] || { ${AUTO_INSTALL_DEPENDENCIES} && install_swiftDialog   || { log_error "swiftDialog missing"; exit 1; }; }
}

# ---------------- Plist State ----------------

init_plist(){
    if [ ! -f "${PLIST}" ]; then
        defaults write "${PLIST}" scriptVersion   -string "${SCRIPT_VERSION}"
        defaults write "${PLIST}" deferCount      -int    0
        defaults write "${PLIST}" firstPromptDate -string "$(date -u +%s)"
    else
        ver=$(defaults read "${PLIST}" scriptVersion 2>/dev/null || echo "")
        if [ "${ver}" != "${SCRIPT_VERSION}" ]; then
            log_info "New version detected; resetting deferral history."
            defaults write "${PLIST}" scriptVersion   -string "${SCRIPT_VERSION}"
            defaults write "${PLIST}" deferCount      -int    0
            defaults write "${PLIST}" firstPromptDate -string "$(date -u +%s)"
        fi
    fi
    defaults read "${PLIST}" deferCount      &>/dev/null || defaults write "${PLIST}" deferCount      -int 0
    defaults read "${PLIST}" firstPromptDate &>/dev/null || defaults write "${PLIST}" firstPromptDate -string "$(date -u +%s)"
}

reset_deferrals() {
    log_info "Resetting deferral count."
    defaults write "${PLIST}" deferCount -int 0
    defaults write "${PLIST}" firstPromptDate -string "$(date -u +%s)"
}

get_deferral_state(){
    deferCount=$(defaults read "${PLIST}" deferCount 2>/dev/null || echo 0)
    firstDate=$(defaults read "${PLIST}" firstPromptDate 2>/dev/null || echo 0)
    now=$(date -u +%s)
    elapsed=$((now-firstDate))
    log_debug "deferCount=${deferCount}, elapsed=${elapsed}s"
    DEFERRAL_EXCEEDED=false
    ((deferCount>=MAX_DEFERS)) && DEFERRAL_EXCEEDED=true
}

# ---------------- LaunchDaemon ----------------

remove_existing_launchdaemon(){
    [ -f "${LAUNCHDAEMON_PATH}" ] && { launchctl unload "${LAUNCHDAEMON_PATH}" 2>/dev/null; rm -f "${LAUNCHDAEMON_PATH}"; log_warn "Existing LaunchDaemon removed."; }
}

schedule_launchdaemon(){
    IFS=":" read -r hour min <<< "$1"
    remove_existing_launchdaemon
    cat<<EOF>"${LAUNCHDAEMON_PATH}"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${LAUNCHDAEMON_LABEL}</string>
  <key>ProgramArguments</key><array>
    <string>${SCRIPT_PATH}</string><string>--reinstall</string><string>--os=${INSTALLER_OS}</string>
    <string>--no-fs</string><string>--check-power</string><string>--min-drive-space=50</string>
    <string>--cleanup-after-use</string>$( [ "${TEST_MODE}" = true ] && echo "<string>--test-run</string>" )
  </array>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>${hour}</integer><key>Minute</key><integer>${min}</integer></dict>
  <key>RunAtLoad</key><false/>
</dict></plist>
EOF
    chmod 644 "${LAUNCHDAEMON_PATH}"; chown root:wheel "${LAUNCHDAEMON_PATH}"; launchctl load "${LAUNCHDAEMON_PATH}"; log_info "LaunchDaemon scheduled for $1"
}

# ---------------- Prompt with Dropdown ----------------

show_prompt(){
    log_info "Displaying SwiftDialog dropdown prompt."
    raw=$("${DIALOG_BIN}" \
        --title "${DIALOG_TITLE}" \
        --message "${DIALOG_MESSAGE}" \
        --button1text "Confirm" \
        --height 200 --width 500 --moveable \
        --icon "${DIALOG_ICON}" --ontop --timeout 0 --showicon true \
        --position "${DIALOG_POSITION}" \
        --messagefont "size=14" \
        --selecttitle "Select an action:" \
        --select \
        --selectvalues "${OPTIONS}" \
        --selectdefault "${DIALOG_INSTALL_NOW_TEXT}" \
        --jsonoutput 2>&1 | tee -a "${WRAPPER_LOG}")
    code=$?
    log_debug "SwiftDialog exit code: ${code}"
    log_debug "SwiftDialog raw output: ${raw}"
    [[ ${code} -eq 0 && -n "${raw}" ]] || { log_warn "No valid JSON from SwiftDialog; aborting."; exit 1; }
    # Extract selected option from JSON-like output
    selection=""
    if echo "${raw}" | grep -q '"SelectedOption"'; then
        # Extract everything between the quotes after "SelectedOption" and clean up
        selection=$(echo "${raw}" | sed -n 's/.*"SelectedOption"[ ]*:[ ]*"\([^"]*\)".*/\1/p' | tr -d '\r')
    fi
    log_info "User selected: ${selection}"
    
    # Validate selection matches one of our options
    if ! echo "${OPTIONS}" | grep -q "${selection}"; then
        log_warn "Invalid selection: '${selection}'"
        log_debug "Expected one of: ${OPTIONS}"
        exit 1
    fi
    
    [[ -z "${selection}" || "${selection}" = "null" ]] && { log_warn "No selection made; aborting."; exit 1; }
    case "${selection}" in
        "${DIALOG_INSTALL_NOW_TEXT}")
            log_info "Installing now."
            reset_deferrals
            sudo "${SCRIPT_PATH}" --reinstall --os="${INSTALLER_OS}" --no-fs --check-power --min-drive-space=50 --cleanup-after-use $( [ "${TEST_MODE}" = true ] && echo "--test-run" )
            ;;
        "${DIALOG_SCHEDULE_TODAY_TEXT}")
            # Create a list of time slots from current hour to 23:00
            current_hour=$(date +%H)
            next_hour=$((current_hour + 1))
            time_options=""
            
            # Ensure we offer at least 3 hours of scheduling options
            max_hour=23
            min_options=3
            
            for h in $(seq $next_hour $max_hour); do
                # Format hour with leading zero if needed
                formatted_hour=$(printf "%02d" $h)
                time_options="${time_options}${time_options:+,}${formatted_hour}:00,${formatted_hour}:30"
            done
            
            # If we have too few options (e.g., it's late in the day), add tomorrow morning options
            num_options=$(echo "$time_options" | tr ',' '\n' | wc -l)
            if [ "$num_options" -lt "$min_options" ]; then
                for h in $(seq 8 $((next_hour - 1))); do
                    tomorrow_hour=$(printf "%02d" $h)
                    time_options="${time_options}${time_options:+,}Tomorrow ${tomorrow_hour}:00"
                done
            fi
            
            sub=$("${DIALOG_BIN}" \
                --title "Schedule Installation" \
                --message "Select installation time:" \
                --button1text "Confirm" \
                --height 230 --width 450 --moveable \
                --icon "${DIALOG_ICON}" --ontop --timeout 0 --showicon true \
                --position "${DIALOG_POSITION}" \
                --messagefont "size=14" \
                --selecttitle "Choose time:" \
                --select \
                --selectvalues "${time_options}" \
                --selectdefault "$(echo "${time_options}" | cut -d',' -f1)" \
                --jsonoutput 2>&1 | tee -a "${WRAPPER_LOG}")
            subcode=$?
            log_debug "Schedule dialog exit code: ${subcode}"
            log_debug "Schedule raw output: ${sub}"
            [[ ${subcode} -eq 0 && -n "${sub}" ]] || { log_warn "No time selected; aborting."; exit 1; }
            # Extract selected time from JSON-like output
            sched=""
            if echo "${sub}" | grep -q '"SelectedOption"'; then
                sched=$(echo "${sub}" | tr -d '\n\r ' | sed 's/.*"SelectedOption"[ ]*:[ ]*"\([^"]*\)".*/\1/')
            fi
            [[ -z "${sched}" || "${sched}" = "null" ]] && { log_warn "No time selected; aborting."; exit 1; }
            log_info "Selected time: ${sched}"
            
            # Check if this is a "Tomorrow" option
            if [[ "$sched" == "Tomorrow"* ]]; then
                # Extract the time portion (format: "Tomorrow HH:MM")
                time_part=$(echo "$sched" | awk '{print $2}')
                # Calculate tomorrow's date in YYYY-MM-DD format
                tomorrow=$(date -v+1d "+%Y-%m-%d")
                # Schedule for tomorrow at the specified time
                log_info "Scheduling for tomorrow at ${time_part}"
                hour=$(echo "$time_part" | cut -d: -f1)
                min=$(echo "$time_part" | cut -d: -f2)
                
                # Create a LaunchDaemon with StartCalendarInterval for tomorrow
                remove_existing_launchdaemon
                cat<<EOF>"${LAUNCHDAEMON_PATH}"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${LAUNCHDAEMON_LABEL}</string>
  <key>ProgramArguments</key><array>
    <string>${SCRIPT_PATH}</string><string>--reinstall</string><string>--os=${INSTALLER_OS}</string>
    <string>--no-fs</string><string>--check-power</string><string>--min-drive-space=50</string>
    <string>--cleanup-after-use</string>$( [ "${TEST_MODE}" = true ] && echo "<string>--test-run</string>" )
  </array>
  <key>StartCalendarInterval</key><dict>
    <key>Day</key><integer>$(date -v+1d "+%d")</integer>
    <key>Month</key><integer>$(date -v+1d "+%m")</integer>
    <key>Hour</key><integer>${hour}</integer>
    <key>Minute</key><integer>${min}</integer>
  </dict>
  <key>RunAtLoad</key><false/>
</dict></plist>
EOF
                chmod 644 "${LAUNCHDAEMON_PATH}"; chown root:wheel "${LAUNCHDAEMON_PATH}"; launchctl load "${LAUNCHDAEMON_PATH}"; log_info "LaunchDaemon scheduled for tomorrow at ${time_part}"
                reset_deferrals
            else
                # Regular same-day scheduling
                log_info "Scheduled for ${sched}"
                reset_deferrals
                schedule_launchdaemon "${sched}"
            fi
            ;;
        "${DIALOG_DEFER_TEXT}")
            if [[ "${DEFERRAL_EXCEEDED}" = true ]]; then
                log_warn "Maximum deferrals (${MAX_DEFERS}) reached."
                reset_deferrals
                sudo "${SCRIPT_PATH}" --reinstall --os="${INSTALLER_OS}" --no-fs --check-power --min-drive-space=50 --cleanup-after-use $( [ "${TEST_MODE}" = true ] && echo "--test-run" )
            else
                newCount=$((deferCount + 1))
                defaults write "${PLIST}" deferCount -int "${newCount}"
                log_info "Deferred (${newCount}/${MAX_DEFERS})"
                
                # Schedule re-prompt in 24 hours
                remove_existing_launchdaemon
                tomorrow_time=$(date -v+24H "+%H:%M")
                tomorrow_hour=$(echo "${tomorrow_time}" | cut -d: -f1)
                tomorrow_min=$(echo "${tomorrow_time}" | cut -d: -f2)
                
                cat<<EOF>"${LAUNCHDAEMON_PATH}"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${LAUNCHDAEMON_LABEL}</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string>
    <string>${0}</string>
  </array>
  <key>StartCalendarInterval</key><dict>
    <key>Day</key><integer>$(date -v+1d "+%d")</integer>
    <key>Month</key><integer>$(date -v+1d "+%m")</integer>
    <key>Hour</key><integer>${tomorrow_hour}</integer>
    <key>Minute</key><integer>${tomorrow_min}</integer>
  </dict>
  <key>RunAtLoad</key><false/>
</dict></plist>
EOF
                chmod 644 "${LAUNCHDAEMON_PATH}"
                chown root:wheel "${LAUNCHDAEMON_PATH}"
                launchctl load "${LAUNCHDAEMON_PATH}"
                log_info "Scheduled re-prompt for tomorrow at ${tomorrow_time}"
            fi
            ;;
        *) log_warn "Unexpected selection: ${selection}";;
    esac
    exit 0
}

# ---------------- Main Execution ----------------

init_logging
log_info "Starting erase-install wrapper script v${SCRIPT_VERSION}"
log_system_info
dependency_check
init_plist
get_deferral_state
set_options
show_prompt
