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
# v1.2.0 - Added auto-install for erase-install and swiftDialog dependencies
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

TEST_MODE=false                   # Set true for dry-run without real install
AUTO_INSTALL_DEPENDENCIES=true    # Set to true to auto-install missing dependencies

LAUNCHDAEMON_LABEL="com.macjediwizard.eraseinstall.schedule"
LAUNCHDAEMON_PATH="/Library/LaunchDaemons/${LAUNCHDAEMON_LABEL}.plist"

# ---------------- Helper Functions ----------------

log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" | tee -a "$WRAPPER_LOG"
}

install_erase_install() {
    log "erase-install not found. Attempting to download and install..."
    local tempDir
    tempDir=$(mktemp -d)
    curl -Ls -o "$tempDir/erase-install.pkg" "https://github.com/grahampugh/erase-install/releases/latest/download/erase-install.pkg"
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to download erase-install package."
        exit 1
    fi
    /usr/sbin/installer -pkg "$tempDir/erase-install.pkg" -target /
    if [ $? -eq 0 ]; then
        log "Successfully installed erase-install."
    else
        log "ERROR: Failed to install erase-install package."
        exit 1
    fi
    rm -rf "$tempDir"
}

install_swiftDialog() {
    log "swiftDialog not found. Attempting to download and install..."
    local tempDir
    tempDir=$(mktemp -d)
    curl -Ls -o "$tempDir/dialog.pkg" "https://github.com/bartreardon/swiftDialog/releases/latest/download/dialog.pkg"
    if [ $? -ne 0 ]; then
        log "ERROR: Failed to download swiftDialog package."
        exit 1
    fi
    /usr/sbin/installer -pkg "$tempDir/dialog.pkg" -target /
    if [ $? -eq 0 ]; then
        log "Successfully installed swiftDialog."
    else
        log "ERROR: Failed to install swiftDialog package."
        exit 1
    fi
    rm -rf "$tempDir"
}

dependency_check() {
    if [ ! -x "$SCRIPT_PATH" ]; then
        if [ "$AUTO_INSTALL_DEPENDENCIES" = true ]; then
            install_erase_install
        else
            log "ERROR: erase-install not found at $SCRIPT_PATH. Exiting."
            exit 1
        fi
    fi
    if [ ! -x "$DIALOG_BIN" ]; then
        if [ "$AUTO_INSTALL_DEPENDENCIES" = true ]; then
            install_swiftDialog
        else
            log "ERROR: swiftDialog not found at $DIALOG_BIN. Exiting."
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
        log "Existing LaunchDaemon removed."
    fi
}

schedule_launchdaemon() {
    launchTime="$1"
    IFS=":" read hour minute <<< "$launchTime"

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
    log "LaunchDaemon scheduled for $launchTime"
}

show_prompt() {
    log "Displaying swiftDialog prompt."

    if [ "$DEFERRAL_EXCEEDED" = true ]; then
        buttonList="--button1text 'Install Now' --button2text 'Schedule Today'"
    else
        buttonList="--button1text 'Install Now' --button2text 'Schedule Today' --button3text 'Defer 24 Hours'"
    fi

    choice=$("$DIALOG_BIN" \
        --title "macOS Upgrade Required" \
        --message "Please install macOS $INSTALLER_OS. You may install now or schedule a convenient time today." \
        $buttonList --height 160 --width 500 --moveable --icon "SF=gear" --ontop --mini \
        --timeout 0 --showicon true)

    if echo "$choice" | grep -q "button1"; then
        log "User selected: Install Now."
        if [ "$TEST_MODE" = true ]; then
            "$SCRIPT_PATH" --reinstall --os=$INSTALLER_OS --no-fs --check-power --min-drive-space=50 --cleanup-after-use --test-run
        else
            "$SCRIPT_PATH" --reinstall --os=$INSTALLER_OS --no-fs --check-power --min-drive-space=50 --cleanup-after-use
        fi
        exit 0
    fi

    if echo "$choice" | grep -q "button2"; then
        selectedTime=$("$DIALOG_BIN" \
            --title "Schedule Installation" \
            --selecttitle "Select a time today to install" \
            --selectvalues "17:00,18:00,19:00,20:00,21:00" \
            --icon "SF=calendar" --height 140 --width 400 --moveable --ontop)

        if [ "$TEST_MODE" = true ]; then
            log "[TEST MODE] Would schedule install for $selectedTime"
        else
            schedule_launchdaemon "$selectedTime"
        fi
        exit 0
    fi

    if echo "$choice" | grep -q "button3"; then
        log "User deferred 24 hours."
        deferCount=$((deferCount + 1))
        defaults write "$PLIST" deferCount -int "$deferCount"
        if [ "$deferCount" -eq 1 ]; then
            defaults write "$PLIST" firstPromptDate -string "$(date -u +%s)"
        fi
        exit 0
    fi
}

# ---------------- Main Execution ----------------

log "Starting erase-install wrapper."

dependency_check
init_plist
get_deferral_state
show_prompt