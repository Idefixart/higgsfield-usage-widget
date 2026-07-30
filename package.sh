#!/bin/bash
# Package the app as a shareable DMG.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Higgsfield Usage"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_DIR="$BUILD_DIR/dmg"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

# Build fresh (build.sh already ad-hoc signs app AND widget with their
# entitlements — do NOT re-sign with --deep here).
bash "$SCRIPT_DIR/build.sh"

rm -rf "$DMG_DIR" "$DMG_PATH"
mkdir -p "$DMG_DIR"
cp -R "$APP_BUNDLE" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

cat > "$DMG_DIR/LIES_MICH.txt" << 'EOF'
Higgsfield Usage Widget
=======================

Installation:
1. "Higgsfield Usage.app" in "Applications" ziehen.
2. Beim ersten Start: Rechtsklick -> "Oeffnen" (ungesigniert, ad-hoc).

Voraussetzungen:
- macOS 14+ (Apple Silicon)
- higgsfield CLI installiert und eingeloggt:
  brew install higgsfield && higgsfield auth login

Das Widget zeigt:
- Aktuelle Higgsfield Credits in der Menueleiste
- Popover: Guthaben-Verlauf, Model-Verbrauch (7d/30d/gesamt),
  letzte Transaktionen
- Desktop-Widget (klein + mittel) via "Widgets bearbeiten"
EOF

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

xattr -d com.apple.quarantine "$DMG_PATH" 2>/dev/null || true

echo ""
echo "DMG ready: $DMG_PATH"
