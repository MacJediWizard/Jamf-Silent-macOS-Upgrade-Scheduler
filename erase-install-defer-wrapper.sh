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
# - Prompts users only at decision point via swiftDialog
# - Allows 24-hour deferral (up to 3 times)
# - Forces install after max deferral or timeout (72 hours)
# - Supports scheduling install later today
# - Fully supports erase-install's --test-run for dry-run testing
# - Automatically installs missing dependencies if enabled
# - Configurable dialog text, buttons, and window positioning
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
#
#########################################################################################################################################################################

# ---------------- Configuration ----------------

WRAPPER_LOG="/var/log/erase-install-wrapper.log"
PLIST="/Library/Preferences/com.macjediwizard.eraseinstall.plist"
SCRIPT_PATH="/Library/Management/erase-install/erase-install.sh"
DIALOG_BIN="/usr/local/bin/dialog"

INSTALLER_OS="15"                # macOS Version e.g. 14 = Sonoma, 15 = Sequoia
MAX_DEFERS=3                     # Max allowed 24-hour deferrals
DEFER_TIMEOUT_SECONDS=86400      # 24 hours
FORCE_TIMEOUT_SECONDS=259200     # 72 hours

TEST_MODE=true                   # Set true for dry-run without real install
AUTO_INSTALL_DEPENDENCIES=true    # Set to true to auto-install missing dependencies
DEBUG_MODE=false                 # Set true for debug logging

LAUNCHDAEMON_LABEL="com.macjediwizard.eraseinstall.schedule"
LAUNCHDAEMON_PATH="/Library/LaunchDaemons/${LAUNCHDAEMON_LABEL}.plist"

# ---------------- Dialog Text Configuration ----------------

DIALOG_TITLE="macOS Upgrade Required"
DIALOG_MESSAGE="Please install macOS $INSTALLER_OS. You may install now or schedule a convenient time today."
DIALOG_INSTALL_NOW_TEXT="Install Now"
DIALOG_SCHEDULE_TODAY_TEXT="Schedule Today"
DIALOG_DEFER_TEXT="Defer 24 Hours"
DIALOG_ICON="SF=gear"
DIALOG_POSITION="topright"

# ---------------- Helper Functions ----------------

log_info() {
    echo "[INFO] [$(date +"%Y-%m-%d %H:%M:%S")] $1" | tee -a "$WRAPPER_LOG"
}

log_warn() {
    echo "[WARN] [$(date +"%Y-%m-%d %H:%M:%S")] $1" | tee -a "$WRAPPER_LOG"
}

log_error() {
    echo "[ERROR] [$(date +"%Y-%m-%d %H:%M:%S")] $1" | tee -a "$WRAPPER_LOG" >&2
}

log_debug() {
    if [ "$DEBUG_MODE" = true ]; then
        echo "[DEBUG] [$(date +"%Y-%m-%d %H:%M:%S")] $1" | tee -a "$WRAPPER_LOG"
    fi
}

install_erase_install() {
    log_info "erase-install not found. Attempting to download and install..."
    local tempDir
    tempDir=$(mktemp -d)
    curl -fsSL -o "$tempDir/erase-install.pkg" "https://github.com/grahampugh/erase-install/releases/latest/download/erase-install.pkg"
    if [ $? -ne 0 ]; then
        log_error "Failed to download erase-install package."
        exit 1
    fi
    /usr/sbin/installer -pkg "$tempDir/erase-install.pkg" -target /
    if [ $? -eq 0 ]; then
        log_info "Successfully installed erase-install."
    else
        log_error "Failed to install erase-install package."
        exit 1
    fi
    rm -rf "$tempDir"
}

install_swiftDialog() {
    log_info "swiftDialog not found. Attempting to download and install..."
    local tempDir
    tempDir=$(mktemp -d)
    curl -fsSL -o "$tempDir/dialog.pkg" "https://github.com/bartreardon/swiftDialog/releases/latest/download/dialog.pkg"
    if [ $? -ne 0 ]; then
        log_error "Failed to download swiftDialog package."
        exit 1
    fi
    /usr/sbin/installer -pkg "$tempDir/dialog.pkg" -target /
    if [ $? -eq 0 ]; then
        log_info "Successfully installed swiftDialog."
    else
        log_error "Failed to install swiftDialog package."
        exit 1
    fi
    rm -rf "$tempDir"
}

dependency_check() {
    if [ ! -x "$SCRIPT_PATH" ]; then
        if [ "$AUTO_INSTALL_DEPENDENCIES" = true ]; then
            install_erase_install
        else
            log_error "erase-install not found at $SCRIPT_PATH. Exiting."
            exit 1
        fi
    fi
    if [ ! -x "$DIALOG_BIN" ]; then
        if [ "$AUTO_INSTALL_DEPENDENCIES" = true ]; then
            install_swiftDialog
        else
            log_error "swiftDialog not found at $DIALOG_BIN. Exiting."
            exit 1
        fi
    fi
}

init_plist() {
    if [ ! -f "$PLIST" ]; then
        defaults write "$PLIST" deferCount -int 0
        defaults write "$PLIST" firstPromptDate -string "$(date -u +%s)"
    fi
    if ! defaults read "$PLIST" deferCount &>/dev/null; then defaults write "$PLIST" deferCount -int 0; fi
    if ! defaults read "$PLIST" firstPromptDate &>/dev/null; then defaults write "$PLIST" firstPromptDate -string "$(date -u +%s)"; fi
}

get_deferral_state() {
    deferCount=$(defaults read "$PLIST" deferCount 2>/dev/null || echo 0)
    firstPromptDate=$(defaults read "$PLIST" firstPromptDate 2>/dev/null || echo 0)
    now=$(date -u +%s)
    secondsSinceFirstPrompt=$((now - firstPromptDate))

    if (( deferCount >= MAX_DEFERS || secondsSinceFirstPrompt >= FORCE_TIMEOUT_SECONDS )); then
        DEFERRAL_EXCEEDED=true
    else
        DEFERRAL_EXCEEDED=false
    fi
}

remove_existing_launchdaemon() {
    if [ -f "$LAUNCHDAEMON_PATH" ]; then
        launchctl unload "$LAUNCHDAEMON_PATH" 2>/dev/null
        rm -f "$LAUNCHDAEMON_PATH"
        log_warn "Existing LaunchDaemon removed."
    fi
}

schedule_launchdaemon() {
    local launchTime="$1"
    IFS=":" read -r hour minute <<< "$launchTime"

    remove_existing_launchdaemon

    /bin/cat << EOF > "$LAUNCHDAEMON_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LAUNCHDAEMON_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPT_PATH</string>
        <string>--reinstall</string>
        <string>--os=$INSTALLER_OS</string>
        <string>--no-fs</string>
        <string>--check-power</string>
        <string>--min-drive-space=50</string>
        <string>--cleanup-after-use</string>
$( [ "$TEST_MODE" = true ] && echo "        <string>--test-run</string>")
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>$hour</integer>
        <key>Minute</key>
        <integer>$minute</integer>
    </dict>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
EOF

    chmod 644 "$LAUNCHDAEMON_PATH"
    chown root:wheel "$LAUNCHDAEMON_PATH"
    launchctl load "$LAUNCHDAEMON_PATH"
    log_info "LaunchDaemon scheduled for $launchTime"
}

show_prompt() {
    log_info "Displaying swiftDialog prompt."

    if [ "$DEFERRAL_EXCEEDED" = true ]; then
        buttonList="--button1text \"$DIALOG_INSTALL_NOW_TEXT\" --button2text \"$DIALOG_SCHEDULE_TODAY_TEXT\""
    else
        buttonList="--button1text \"$DIALOG_INSTALL_NOW_TEXT\" --button2text \"$DIALOG_SCHEDULE_TODAY_TEXT\" --button3text \"$DIALOG_DEFER_TEXT\""
    fi

    response=$("$DIALOG_BIN" \
        --title "$DIALOG_TITLE" \
        --message "$DIALOG_MESSAGE" \
        $buttonList --height 160 --width 500 --moveable --icon "$DIALOG_ICON" --ontop --mini \
        --timeout 0 --showicon true --json --position "$DIALOG_POSITION")

    if [[ -z "$response" ]]; then
        log_warn "No response from swiftDialog (user closed dialog or error)."
        exit 1
    fi

    if [ -x "/usr/bin/jq" ]; then
        buttonClicked=$(echo "$response" | /usr/bin/jq -r '.buttonReturned')
    else
        buttonClicked=$(echo "$response" | /usr/bin/sed -n 's/.*\"buttonReturned\"[ ]*:[ ]*\"\\([^\"]*\\)\".*/\\1/p')
    fi

    log_info "User clicked button: $buttonClicked"

    if [[ "$buttonClicked" == "$DIALOG_INSTALL_NOW_TEXT" ]]; then
        log_info "User selected: Install Now."
        /usr/bin/sudo "$SCRIPT_PATH" --reinstall --os="$INSTALLER_OS" --no-fs --check-power --min-drive-space=50 --cleanup-after-use $( [ "$TEST_MODE" = true ] && echo "--test-run" )
        exit 0
    fi

    if [[ "$buttonClicked" == "$DIALOG_SCHEDULE_TODAY_TEXT" ]]; then
        selectedTime=$("$DIALOG_BIN" \
            --title "Schedule Installation" \
            --selecttitle "Select a time today to install" \
            --selectvalues "17:00,18:00,19:00,20:00,21:00" \
            --icon "SF=calendar" --height 140 --width 400 --moveable --ontop --json --position "$DIALOG_POSITION")

        if [ -x "/usr/bin/jq" ]; then
            scheduledChoice=$(echo "$selectedTime" | /usr/bin/jq -r '.selectedValue')
        else
            scheduledChoice=$(echo "$selectedTime" | /usr/bin/sed -n 's/.*\"selectedValue\"[ ]*:[ ]*\"\\([^\"]*\\)\".*/\\1/p')
        fi

        log_info "User selected scheduled time: $scheduledChoice"
        schedule_launchdaemon "$scheduledChoice"
        exit 0
    fi

    if [[ "$buttonClicked" == "$DIALOG_DEFER_TEXT" ]]; then
        log_info "User deferred 24 hours."
        deferCount=$((deferCount + 1))
        defaults write "$PLIST" deferCount -int "$deferCount"
        if [ "$deferCount" -eq 1 ]; then
            defaults write "$PLIST" firstPromptDate -string "$(date -u +%s)"
        fi
        exit 0
    fi
}

# ---------------- Main Execution ----------------

log_info "Starting erase-install wrapper."

dependency_check
init_plist
get_deferral_state
show_prompt