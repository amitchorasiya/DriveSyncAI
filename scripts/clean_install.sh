#!/bin/bash
# Copyright 2026 Amit Chorasiya. All rights reserved.
# Licensed under the Business Source License 1.1. See LICENSE file.
#
# Removes all DriveSyncAI settings and data from the local system for a clean install.
# Run this with the app quit. After running, next launch will be like first install.

set -euo pipefail

BUNDLE_ID="com.amitchorasiya.drivesyncai"
KEYCHAIN_SERVICE="com.amitchorasiya.drivesyncai"
PREFS_PLIST="$HOME/Library/Preferences/${BUNDLE_ID}.plist"
APP_SUPPORT="$HOME/Library/Application Support/DriveSyncAI"
CACHES="$HOME/Library/Caches/$BUNDLE_ID"
DRIVESYNC_DIR="$HOME/.drivesyncai"

# Keychain accounts used by LLMConfigManager (llm_apikey_<provider>)
KEYCHAIN_ACCOUNTS=(
    "llm_apikey_llamaCpp"
    "llm_apikey_ollama"
    "llm_apikey_openai"
    "llm_apikey_anthropic"
    "llm_apikey_google"
    "llm_apikey_perplexity"
)

echo "=== DriveSyncAI Clean Install ==="
echo "This will remove all app settings, config, and data so the next launch is like a fresh install."
echo ""

# Quit the app if running
if pgrep -x "DriveSyncAI" >/dev/null 2>&1; then
    echo "Quitting DriveSyncAI..."
    osascript -e 'quit app "DriveSyncAI"' 2>/dev/null || true
    sleep 2
    if pgrep -x "DriveSyncAI" >/dev/null 2>&1; then
        echo "Please quit DriveSyncAI manually and run this script again."
        exit 1
    fi
fi

echo "[1/5] Removing Preferences..."
rm -f "$PREFS_PLIST"

echo "[2/5] Removing Application Support..."
rm -rf "$APP_SUPPORT"

echo "[3/5] Removing Caches..."
rm -rf "$CACHES"

echo "[4/5] Removing ~/.drivesyncai (config, LLM config, sync state, profiles, etc.)..."
rm -rf "$DRIVESYNC_DIR"

echo "[5/5] Removing Keychain entries (saved API keys)..."
for account in "${KEYCHAIN_ACCOUNTS[@]}"; do
    security delete-generic-password -s "$KEYCHAIN_SERVICE" -a "$account" 2>/dev/null || true
done

echo ""
echo "=== Done ==="
echo "All DriveSyncAI settings and data have been removed."
echo "Next time you open DriveSyncAI it will start as a clean install (onboarding, license, etc.)."
echo "The built-in AI engine will need to be set up again if you use it."
