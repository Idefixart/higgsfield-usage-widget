#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Higgsfield Usage"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
APP_ID="com.higgsfield.usage-widget"
WIDGET_ID="$APP_ID.HiggsfieldUsageWidget"
TARGET="arm64-apple-macos14"
VERSION="1.0.0"

echo "Building $APP_NAME..."

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# --- Compile main app (main.swift has top-level code) ---
swiftc "$SCRIPT_DIR/main.swift" \
    "$SCRIPT_DIR/AppSupport.swift" \
    "$SCRIPT_DIR/Store.swift" \
    "$SCRIPT_DIR/Views.swift" \
    "$SCRIPT_DIR/Sources/HiggsfieldUsageCore/"*.swift \
    -framework AppKit \
    -framework SwiftUI \
    -framework Combine \
    -framework WidgetKit \
    -target "$TARGET" \
    -O \
    -o "$BUILD_DIR/HiggsfieldUsage"
echo "App binary compiled."

# --- Compile widget extension (@main WidgetBundle, no top-level code) ---
swiftc "$SCRIPT_DIR/HiggsfieldWidget.swift" \
    "$SCRIPT_DIR/Sources/HiggsfieldUsageCore/"*.swift \
    -framework WidgetKit \
    -framework SwiftUI \
    -target "$TARGET" \
    -O \
    -o "$BUILD_DIR/HiggsfieldUsageWidgetExt"
echo "Widget binary compiled."

# --- Assemble .app bundle ---
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/HiggsfieldUsage" "$APP_BUNDLE/Contents/MacOS/HiggsfieldUsage"

# Optional app icon
if [ -f "$SCRIPT_DIR/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Higgsfield Usage</string>
    <key>CFBundleDisplayName</key>
    <string>Higgsfield Usage</string>
    <key>CFBundleIdentifier</key>
    <string>$APP_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>HiggsfieldUsage</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# --- Assemble widget extension (.appex) inside Contents/PlugIns ---
APPEX="$APP_BUNDLE/Contents/PlugIns/HiggsfieldUsageWidget.appex"
mkdir -p "$APPEX/Contents/MacOS"
cp "$BUILD_DIR/HiggsfieldUsageWidgetExt" "$APPEX/Contents/MacOS/HiggsfieldUsageWidgetExt"

cat > "$APPEX/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>HiggsfieldUsageWidget</string>
    <key>CFBundleDisplayName</key>
    <string>Higgsfield Usage</string>
    <key>CFBundleIdentifier</key>
    <string>$WIDGET_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>HiggsfieldUsageWidgetExt</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
PLIST

# --- Code sign (ad-hoc). Inner extension first, then the app bundle. ---
codesign --force --sign - \
    --entitlements "$SCRIPT_DIR/widget.entitlements" \
    --identifier "$WIDGET_ID" \
    "$APPEX"
echo "Widget extension signed (ad-hoc)."

codesign --force --sign - \
    --entitlements "$SCRIPT_DIR/app.entitlements" \
    --identifier "$APP_ID" \
    "$APP_BUNDLE"
echo "App bundle signed (ad-hoc)."

echo "App bundle created: $APP_BUNDLE"
echo ""
echo "To install, run: ./install.sh"
echo "Or open directly: open \"$APP_BUNDLE\""
