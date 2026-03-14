#!/bin/bash
# Copyright 2026 Amit Chorasiya. All rights reserved.
# Licensed under the Business Source License 1.1. See LICENSE file.
#
# Creates a styled DMG installer for DriveSyncAI.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="DriveSyncAI"
VERSION="1.6.1"
DMG_NAME="$APP_NAME-$VERSION"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_TMP="$DIST_DIR/${DMG_NAME}_tmp.dmg"
DMG_FINAL="$DIST_DIR/$DMG_NAME.dmg"
DMG_VOLUME="/Volumes/$APP_NAME"
BG_IMG="$PROJECT_DIR/build_tmp/dmg_background.png"

echo "=== Building DriveSyncAI DMG Installer ==="

# Step 1: Build .app
echo "[1/6] Building .app bundle..."
bash "$SCRIPT_DIR/build_app.sh"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "ERROR: App bundle not found at $APP_BUNDLE"
    exit 1
fi

# Step 2: Generate DMG background
if [ ! -f "$BG_IMG" ]; then
    echo "[2/6] Generating DMG background..."
    swift "$SCRIPT_DIR/generate_dmg_background.swift"
else
    echo "[2/6] DMG background already exists."
fi

# Step 3: Create empty writable DMG, then populate it
echo "[3/6] Creating temporary DMG..."
rm -f "$DMG_TMP" "$DMG_FINAL"

APP_SIZE_KB=$(du -sk "$APP_BUNDLE" | cut -f1)
DMG_SIZE_KB=$((APP_SIZE_KB + 20480))

hdiutil create \
    -volname "$APP_NAME" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -size "${DMG_SIZE_KB}k" \
    -type SPARSE \
    "$DMG_TMP" 2>&1

# hdiutil appends .sparseimage to the path
if [ -f "${DMG_TMP}.sparseimage" ]; then
    DMG_TMP="${DMG_TMP}.sparseimage"
fi

# Step 4: Mount, populate, and style
echo "[4/6] Styling DMG..."
MOUNT_OUT=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_TMP" 2>&1)
DEVICE=$(echo "$MOUNT_OUT" | grep '^/dev/' | head -1 | awk '{print $1}')

sleep 2

cp -R "$APP_BUNDLE" "$DMG_VOLUME/"
ln -sf /Applications "$DMG_VOLUME/Applications"

mkdir -p "$DMG_VOLUME/.background"
cp "$BG_IMG" "$DMG_VOLUME/.background/background.png"

# Style the DMG window with AppleScript
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 840, 600}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set background picture of viewOptions to file ".background:background.png"
        set position of item "$APP_NAME.app" of container window to {150, 240}
        set position of item "Applications" of container window to {490, 240}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

# Ensure changes are written
sync

# Step 5: Unmount and convert to compressed DMG
echo "[5/6] Converting to compressed DMG..."
hdiutil detach "$DEVICE" 2>&1 || true
sleep 1

hdiutil convert "$DMG_TMP" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_FINAL" 2>&1

rm -f "$DMG_TMP"

# Step 6: Clean up
echo "[6/6] Cleaning up..."
rm -rf "$PROJECT_DIR/build_tmp"

echo ""
echo "=== Success ==="
echo "DMG: $DMG_FINAL"
echo "Size: $(du -h "$DMG_FINAL" | cut -f1)"
echo ""
echo "Done! Distribute $DMG_FINAL to users."
