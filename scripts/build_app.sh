#!/bin/bash
# Copyright 2026 Amit Chorasiya. All rights reserved.
# Licensed under the Business Source License 1.1. See LICENSE file.
#
# Builds DriveSyncAI.app bundle from the Swift package.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="DriveSyncAI"
APP_BUNDLE="$PROJECT_DIR/dist/$APP_NAME.app"
VERSION="1.4.0"

echo "=== Building DriveSyncAI $VERSION ==="

# Step 1: Build release binary
echo "[1/5] Building release binary..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

BINARY_PATH="$PROJECT_DIR/.build/release/DriveSyncAI"
if [ ! -f "$BINARY_PATH" ]; then
    echo "ERROR: Release binary not found at $BINARY_PATH"
    exit 1
fi

# Step 2: Generate app icon
ICNS_PATH="$PROJECT_DIR/Sources/DriveSyncAI/Resources/AppIcon.icns"
if [ ! -f "$ICNS_PATH" ]; then
    echo "[2/5] Generating app icon..."
    swift "$SCRIPT_DIR/generate_icon.swift"
else
    echo "[2/5] App icon already exists, skipping generation."
fi

# Step 3: Create .app bundle structure
echo "[3/5] Assembling $APP_NAME.app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/DriveSyncAI"

# Copy Info.plist
cp "$PROJECT_DIR/Info.plist" "$APP_BUNDLE/Contents/"

# Copy icon
if [ -f "$ICNS_PATH" ]; then
    cp "$ICNS_PATH" "$APP_BUNDLE/Contents/Resources/"
fi

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Step 4: Ad-hoc code sign
echo "[4/5] Code signing (ad-hoc)..."
codesign --force --sign - --deep "$APP_BUNDLE" 2>&1

# Step 5: Verify
echo "[5/5] Verifying bundle..."
if [ -f "$APP_BUNDLE/Contents/MacOS/DriveSyncAI" ] && \
   [ -f "$APP_BUNDLE/Contents/Info.plist" ]; then
    echo ""
    echo "=== Success ==="
    echo "App bundle: $APP_BUNDLE"
    echo "Binary size: $(du -h "$APP_BUNDLE/Contents/MacOS/DriveSyncAI" | cut -f1)"
    echo "Bundle size: $(du -sh "$APP_BUNDLE" | cut -f1)"
else
    echo "ERROR: Bundle verification failed"
    exit 1
fi
