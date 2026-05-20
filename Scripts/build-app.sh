#!/bin/bash
set -euo pipefail

TARGET_NAME="CodeFM"
DISPLAY_NAME="Code FM"
APP_BUNDLE="build/$DISPLAY_NAME.app"

echo "Building $DISPLAY_NAME (arm64)..."
swift build -c release --triple arm64-apple-macosx

echo "Building $DISPLAY_NAME (x86_64)..."
swift build -c release --triple x86_64-apple-macosx

echo "Creating universal binary..."
mkdir -p build
lipo -create \
    .build/arm64-apple-macosx/release/$TARGET_NAME \
    .build/x86_64-apple-macosx/release/$TARGET_NAME \
    -output "build/$TARGET_NAME"

echo "Assembling app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

mv "build/$TARGET_NAME" "$APP_BUNDLE/Contents/MacOS/$DISPLAY_NAME"
cp Resources/Info.plist "$APP_BUNDLE/Contents/"
cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/"
cp Resources/streams.json "$APP_BUNDLE/Contents/Resources/"

echo "Signing app bundle..."
codesign --deep --force --sign - --entitlements Resources/CodeFM.entitlements "$APP_BUNDLE"

echo "Done: $APP_BUNDLE"
echo "Run:  open \"$APP_BUNDLE\""
echo "Install: cp -r \"$APP_BUNDLE\" /Applications/"
