#!/usr/bin/env bash
# Build script to create Kuyruk.app bundle
# Inspired by steipete/CodexBar packaging approach

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# Load version info
source "$ROOT/version.env"

# Configuration
CONF=${1:-release}
SIGNING_MODE=${KUYRUK_SIGNING:-dev}
APP_NAME="Kuyruk"
BUNDLE_ID="com.sertacozercan.Kuyruk"
BUILD_DIR="$ROOT/.build/app"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

# Build for host architecture by default; allow overriding via ARCHES (e.g., "arm64 x86_64" for universal).
ARCH_LIST=( ${ARCHES:-} )
if [[ ${#ARCH_LIST[@]} -eq 0 ]]; then
  HOST_ARCH=$(uname -m)
  case "$HOST_ARCH" in
    arm64) ARCH_LIST=(arm64) ;;
    x86_64) ARCH_LIST=(x86_64) ;;
    *) ARCH_LIST=("$HOST_ARCH") ;;
  esac
fi

echo "🔨 Building $APP_NAME ($CONF) for ${ARCH_LIST[*]}..."

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build for each architecture
for ARCH in "${ARCH_LIST[@]}"; do
  echo "  → Building for $ARCH..."
  swift build -c "$CONF" --arch "$ARCH"
done

# Create app bundle structure
echo "📦 Creating app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Build path helper
build_product_path() {
  local name="$1"
  local arch="$2"
  case "$arch" in
    arm64|x86_64) echo ".build/${arch}-apple-macosx/$CONF/$name" ;;
    *) echo ".build/$CONF/$name" ;;
  esac
}

# Verify binary architectures
verify_binary_arches() {
  local binary="$1"; shift
  local expected=("$@")
  local actual
  actual=$(lipo -archs "$binary")
  for arch in "${expected[@]}"; do
    if [[ "$actual" != *"$arch"* ]]; then
      echo "ERROR: $binary missing arch $arch (have: ${actual})" >&2
      exit 1
    fi
  done
}

# Install binary (handles universal builds)
install_binary() {
  local name="$1"
  local dest="$2"
  local binaries=()
  for arch in "${ARCH_LIST[@]}"; do
    local src
    src=$(build_product_path "$name" "$arch")
    if [[ ! -f "$src" ]]; then
      echo "ERROR: Missing ${name} build for ${arch} at ${src}" >&2
      exit 1
    fi
    binaries+=("$src")
  done
  if [[ ${#ARCH_LIST[@]} -gt 1 ]]; then
    lipo -create "${binaries[@]}" -output "$dest"
  else
    cp "${binaries[0]}" "$dest"
  fi
  chmod +x "$dest"
  verify_binary_arches "$dest" "${ARCH_LIST[@]}"
}

# Copy executable
install_binary "$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Generate Info.plist with build metadata
BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Sertac Ozercan. All rights reserved.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.sertacozercan.Kuyruk.oauth</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>kuyruk</string>
            </array>
        </dict>
    </array>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>
    <key>LSUIElement</key>
    <false/>
    <key>KuyrukBuildTimestamp</key>
    <string>${BUILD_TIMESTAMP}</string>
    <key>KuyrukGitCommit</key>
    <string>${GIT_COMMIT}</string>
</dict>
</plist>
PLIST

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Copy app icon (icns file)
ICON_PATH="$ROOT/Sources/Kuyruk/Resources/AppIcon.icns"
if [[ -f "$ICON_PATH" ]]; then
  echo "🎨 Copying app icon..."
  cp "$ICON_PATH" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Strip extended attributes to prevent AppleDouble (._*) files that break code sealing
xattr -cr "$APP_BUNDLE" 2>/dev/null || true
find "$APP_BUNDLE" -name '._*' -delete 2>/dev/null || true

# Sign the app
echo "🔏 Signing app..."
if [[ "$SIGNING_MODE" == "adhoc" ]]; then
  CODESIGN_ARGS=(--force --sign -)
elif [[ "$SIGNING_MODE" == "dev" ]]; then
  # Use Apple Development certificate - use SHA-1 hash to avoid ambiguity
  CODESIGN_HASH=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | awk '{print $2}')
  if [[ -z "$CODESIGN_HASH" ]]; then
    echo "ERROR: No Apple Development certificate found. Use KUYRUK_SIGNING=adhoc for ad-hoc signing." >&2
    exit 1
  fi
  CODESIGN_ARGS=(--force --sign "$CODESIGN_HASH")
else
  CODESIGN_ID="${APP_IDENTITY:-Developer ID Application}"
  CODESIGN_ARGS=(--force --timestamp --options runtime --sign "$CODESIGN_ID")
fi

# Sign with entitlements if present
if [[ -f "$ROOT/Kuyruk.entitlements" ]]; then
  codesign "${CODESIGN_ARGS[@]}" --entitlements "$ROOT/Kuyruk.entitlements" "$APP_BUNDLE"
else
  codesign "${CODESIGN_ARGS[@]}" "$APP_BUNDLE"
fi

echo ""
echo "✅ Build complete!"
echo "📍 App location: $APP_BUNDLE"
echo "   Version: ${MARKETING_VERSION} (${BUILD_NUMBER})"
echo "   Commit:  ${GIT_COMMIT}"
echo "   Arches:  ${ARCH_LIST[*]}"
echo ""
echo "To run: open $APP_BUNDLE"
echo "To install: cp -r $APP_BUNDLE /Applications/"
