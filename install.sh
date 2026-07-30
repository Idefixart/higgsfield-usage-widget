#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Higgsfield Usage"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="/Applications"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Building first..."
    bash "$SCRIPT_DIR/build.sh"
fi

echo "Installing to $INSTALL_DIR..."
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP_BUNDLE" "$INSTALL_DIR/"
echo "Installed to $INSTALL_DIR/$APP_NAME.app"

# The widget won't appear in the gallery if macOS has stale copies of the same
# bundle id registered. Re-register the installed one.
LSR="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSR" ]; then
    echo "Cleaning stale widget registrations..."
    "$LSR" -u "$APP_BUNDLE" 2>/dev/null || true
    "$LSR" -u "$BUILD_DIR/dmg/$APP_NAME.app" 2>/dev/null || true
    "$LSR" -f "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true
    killall chronod 2>/dev/null || true
fi

echo ""
read -p "Beim Login automatisch starten? (j/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Jj]$ ]]; then
    osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$INSTALL_DIR/$APP_NAME.app\", hidden:true}"
    echo "Login-Item hinzugefuegt."
fi

echo ""
echo "Starte App..."
open "$INSTALL_DIR/$APP_NAME.app"
echo "Fertig! Du siehst jetzt das Blitz-Symbol in deiner Menueleiste."
