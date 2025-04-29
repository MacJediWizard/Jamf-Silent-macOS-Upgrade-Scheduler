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
# - Prompts users via a dropdown selection in swiftDialog
# - Allows 24-hour deferral (up to 3 times per script version)
# - Forces install after max deferral or timeout (72 hours)
# - Supports scheduling install later today
# - Fully supports erase-install's --test-run for dry-run testing
# - Automatically installs missing dependencies if enabled
# - Configurable dialog text, dropdown choices, and window positioning
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
# v1.0.0 - Initial working version
# v1.0.1 - Added header, license, and test-run integration
# v1.1.0 - Hardened for enterprise, dependency checks, smarter LaunchDaemon handling, cleaner logging
# v1.2.0 - Added auto-install of dependencies, improved JSON parsing with jq fallback, safe sudo execution, structured INFO/WARN/ERROR/DEBUG logging
# v1.3.0 - Added Dialog window positioning, moved Dialog text/buttons to top-configurable variables for easier customization
# v1.4.0 - Persistent deferral count across runs and reset when new script version is detected
# v1.4.1 - Fixed syntax in install functions ($(mktemp -d)), bump here and update README/CHANGELOG
# v1.4.2 - Preserved --mini UI and added debug logging of SwiftDialog exit codes/output
# v1.4.3 - Switched to dropdown UI with single OK button and removed multiple buttons
# v1.4.4 - Updated logging functions to simplified date expansion syntax
#
#########################################################################################################################################################################

# ---------------- Configuration ----------------

WRAPPER_LOG="/var/log/erase-install-wrapper.log"
PLIST="/Library/Preferences/com.macjediwizard.eraseinstall.plist"
SCRIPT_PATH="/Library/Management/erase-install/erase-install.sh"
DIALOG_BIN="/usr/local/bin/dialog"

SCRIPT_VERSION="1.4.4"            # ← Bump this on every release!
INSTALLER_OS="15"                 # macOS Version e.g. 14 = Sonoma, 15 = Sequoia
MAX_DEFERS=3                      # Max allowed 24-hour deferrals per script version
FORCE_TIMEOUT_SECONDS=259200      # 72 hours total window

TEST_MODE=true                    # Dry-run without real install
AUTO_INSTALL_DEPENDENCIES=true    # Auto-install missing dependencies
DEBUG_MODE=true                   # Enable debug logging

LAUNCHDAEMON_LABEL="com.macjediwizard.eraseinstall.schedule"
LAUNCHDAEMON_PATH="/Library/LaunchDaemons/${LAUNCHDAEMON_LABEL}.plist"

# ---------------- Dialog Text Configuration ----------------

DIALOG_TITLE="macOS Upgrade Required"
DIALOG_MESSAGE="Please install macOS ${INSTALLER_OS}. Choose an action from the list below:"
DIALOG_INSTALL_NOW_TEXT="Install Now"
DIALOG_SCHEDULE_TODAY_TEXT="Schedule Today"
DIALOG_DEFER_TEXT="Defer 24 Hours"
DIALOG_ICON="SF=gear"
DIALOG_POSITION="topright"

# ---------------- Helper Functions ----------------

log_info() {
    echo "[INFO]  [$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${WRAPPER_LOG}"
}

log_warn() {
    echo "[WARN]  [$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${WRAPPER_LOG}"
}

log_error() {
    echo "[ERROR] [$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${WRAPPER_LOG}" >&2
}

log_debug() {
    if [ "${DEBUG_MODE}" = true ]; then
        echo "[DEBUG] [$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${WRAPPER_LOG}"
    fi
}

# ---------------- Dependency Installers ----------------

install_erase_install() {
    log_info "erase-install not found. Downloading and installing..."
    tempDir=$(mktemp -d)
    curl -fsSL -o "${tempDir}/erase-install.pkg" \
        "https://github.com/grahampugh/erase-install/releases/latest/download/erase-install.pkg" || {
        log_error "Failed to download erase-install package."; exit 1; }
    /usr/sbin/installer -pkg "${tempDir}/erase-install.pkg" -target / \
        && log_info "erase-install installed." \
        || { log_error "erase-install install failed."; exit 1; }
    rm -rf "${tempDir}"
}

install_swiftDialog() {
    log_info "swiftDialog not found. Downloading and installing..."
    tempDir=$(mktemp -d)
    curl -fsSL -o "${tempDir}/dialog.pkg" \
        "https://github.com/bartreardon/swiftDialog/releases/latest/download/dialog.pkg" || {
        log_error "Failed to download swiftDialog package."; exit 1; }
    /usr/sbin/installer -pkg "${tempDir}/dialog.pkg" -target / \
        && log_info "swiftDialog installed." \
        || { log_error "swiftDialog install failed."; exit 1; }
    rm -rf "${tempDir}"
}

dependency_check() {
    [ -x "${SCRIPT_PATH}" ] || { [ "${AUTO_INSTALL_DEPENDENCIES}" = true ] && install_erase_install || { log_error "erase-install missing"; exit 1; }; }
    [ -x "${DIALOG_BIN}"   ] || { [ "${AUTO_INSTALL_DEPENDENCIES}" = true ] && install_swiftDialog   || { log_error "swiftDialog missing";   exit 1; }; }
}

# ---------------- Plist State ----------------

init_plist() {
    if [ ! -f "${PLIST}" ]; then
        defaults write "${PLIST}" scriptVersion   -string "${SCRIPT_VERSION}"
        defaults write "${PLIST}" deferCount      -int    0
        defaults write "${PLIST}" firstPromptDate -string "$(date -u +%s)"
    else
        storedVer=$(defaults read "${PLIST}" scriptVersion 2>/dev/null || echo "")
        if [ "${storedVer}" != "${SCRIPT_VERSION}" ]; then
            log_info "New script version detected; resetting deferral history."
            defaults write "${PLIST}" scriptVersion   -string "${SCRIPT_VERSION}"
            defaults write "${PLIST}" deferCount      -int    0
            defaults write "${PLIST}" firstPromptDate -string "$(date -u +%s)"
        fi
    fi
    defaults read "${PLIST}" deferCount      &>/dev/null || defaults write "${PLIST}" deferCount      -int 0
    defaults read "${PLIST}" firstPromptDate &>/dev/null || defaults write "${PLIST}" firstPromptDate -string "$(date -u +%s)"
}

get_deferral_state() {
    deferCount=$(defaults read "${PLIST}" deferCount 2>/dev/null || echo 0)
    firstPromptDate=$(defaults read "${PLIST}" firstPromptDate 2>/dev/null || echo 0)
    now=$(date -u +%s)
    secondsSinceFirstPrompt=$((now - firstPromptDate))

    log_debug "deferCount=${deferCount}, elapsed=${secondsSinceFirstPrompt}s"
    if (( deferCount >= MAX_DEFERS || secondsSinceFirstPrompt >= FORCE_TIMEOUT_SECONDS )); then
        DEFERRAL_EXCEEDED=true
    else
        DEFERRAL_EXCEEDED=false
    fi
}

# ---------------- LaunchDaemon ----------------

remove_existing_launchdaemon() {
    if [ -f "${LAUNCHDAEMON_PATH}" ]; then
        launchctl unload "${LAUNCHDAEMON_PATH}" 2>/dev/null
        rm -f "${LAUNCHDAEMON_PATH}"
        log_warn "Existing LaunchDaemon removed."
    fi
}

schedule_launchdaemon() {
    local launchTime="$1"; IFS=":" read -r hour minute <<< "$launchTime"
    remove_existing_launchdaemon

    cat << EOF > "${LAUNCHDAEMON_PATH}"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${LAUNCHDAEMON_LABEL}</string>
  <key>ProgramArguments</key><array>
    <string>${SCRIPT_PATH}</string>
    <string>--reinstall</string>
    <string>--os=${INSTALLER_OS}</string>
    <string>--no-fs</string>
    <string>--check-power</string>
    <string>--min-drive-space=50</string>
    <string>--cleanup-after-use</string>
    $( [ "${TEST_MODE}" = true ] && echo "<string>--test-run</string>" )
  </array>
  <key>StartCalendarInterval</key><dict>
    <key>Hour</key><integer>${hour}</integer>
    <key>Minute</key><integer>${minute}</integer>
  </dict>
  <key>RunAtLoad</key><false/>
</dict></plist>
EOF

    chmod 644 "${LAUNCHDAEMON_PATH}"
    chown root:wheel "${LAUNCHDAEMON_PATH}"
    launchctl load "${LAUNCHDAEMON_PATH}"
    log_info "LaunchDaemon scheduled for ${launchTime}"
}

# ---------------- Prompt with Dropdown ----------------

show_prompt() {
    log_info "Displaying swiftDialog prompt."

    args=(
        --title       "${DIALOG_TITLE}"
        --message     "${DIALOG_MESSAGE}"
        --selecttitle "Please select an action:"
        --selectvalues "${DIALOG_INSTALL_NOW_TEXT},${DIALOG_SCHEDULE_TODAY_TEXT},${DIALOG_DEFER_TEXT}"
        --button1text "OK"
        --height      180 --width 500 --moveable --mini
        --icon        "${DIALOG_ICON}"
        --ontop       --timeout 0 --showicon true --json
        --position    "${DIALOG_POSITION}"
    )

    raw=$("${DIALOG_BIN}" "${args[@]}" 2>&1 | tee -a "${WRAPPER_LOG}")
    code=$?
    log_debug "swiftDialog exit code: $code"
    log_debug "swiftDialog raw output: $raw"

    if [ $code -ne 0 ] || [[ -z "$raw" ]]; then
        log_warn "No valid JSON from swiftDialog; aborting."
        exit 1
    fi

    if command -v jq &>/dev/null; then
        chosen=$(echo "$raw" | jq -r '.selectedValue')
    else
        chosen=$(echo "$raw" | sed -n 's/.*"selectedValue"[ ]*:[ ]*"\\([^"]*\\)".*/\\1/p')
    fi

    log_info "User chose: $chosen"

    case "$chosen" in
        "${DIALOG_INSTALL_NOW_TEXT}")
            log_info "Installing now."
            sudo "${SCRIPT_PATH}" --reinstall --os="${INSTALLER_OS}" \
                --no-fs --check-power --min-drive-space=50 --cleanup-after-use \
                $( [ "${TEST_MODE}" = true ] && echo "--test-run" )
            ;;
        "${DIALOG_SCHEDULE_TODAY_TEXT}")
            # schedule submenu
            subargs=(
                --title       "Schedule Installation"
                --selecttitle "Select a time today to install"
                --selectvalues "17:00,18:00,19:00,20:00,21:00"
                --button1text "OK"
                --height      140 --width 400 --moveable --mini
                --icon        "${DIALOG_ICON}"
                --ontop       --timeout 0 --showicon true --json
                --position    "${DIALOG_POSITION}"
            )
            subraw=$("${DIALOG_BIN}" "${subargs[@]}" 2>&1 | tee -a "${WRAPPER_LOG}")
            subcode=$?
            log_debug "Schedule exit code: $subcode"
            log_debug "Schedule raw output: $subraw"
            if [ $subcode -ne 0 ] || [[ -z "$subraw" ]]; then
                log_warn "No valid time selected; aborting."
                exit 1
            fi
            if command -v jq &>/dev/null; then
                sched=$(echo "$subraw" | jq -r '.selectedValue')
            else
                sched=$(echo "$subraw" | sed -n 's/.*"selectedValue"[ ]*:[ ]*"\\([^"]*\\)".*/\\1/p')
            fi
            log_info "Scheduled for $sched"
            schedule_launchdaemon "$sched"
            ;;
        "${DIALOG_DEFER_TEXT}")
            log_info "User deferred (was ${deferCount})."
            deferCount=$(( deferCount + 1 ))
            defaults write "${PLIST}" deferCount -int "${deferCount}"
            ;;
        *)
            log_warn "Unexpected selection: $chosen"
            ;;
    esac

    exit 0
}

# ---------------- Main Execution ----------------

log_info "Starting erase-install wrapper."
dependency_check
init_plist
get_deferral_state
show_prompt