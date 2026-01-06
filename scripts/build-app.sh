#!/bin/bash
# Build script to create Kuyruk.app bundle

set -e

APP_NAME="Kuyruk"
BUNDLE_ID="com.sozercan.Kuyruk"
BUILD_DIR=".build/app"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "🔨 Building $APP_NAME..."

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build release binary with SPM
swift build -c release

# Create app bundle structure
echo "📦 Creating app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp ".build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Copy Info.plist from project root
cp "Info.plist" "$APP_BUNDLE/Contents/"

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Sign the app (ad-hoc signing for local development)
# Note: For distribution, use a proper Developer ID certificate
echo "🔏 Signing app..."
codesign --force --sign - "$APP_BUNDLE"

echo ""
echo "✅ Build complete!"
echo "📍 App location: $APP_BUNDLE"
echo ""
echo "To run: open $APP_BUNDLE"
echo "To install: cp -r $APP_BUNDLE /Applications/"
