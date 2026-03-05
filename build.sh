#!/bin/bash
set -e

APP="MicMuteApp"
BUNDLE="${APP}.app"

echo "Compiling..."
swiftc MicMuteApp.swift -framework AppKit -framework CoreAudio -o "${APP}"

echo "Building app bundle..."
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"

cp "${APP}" "${BUNDLE}/Contents/MacOS/"
cp AppIcon.icns "${BUNDLE}/Contents/Resources/"

cat > "${BUNDLE}/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MicMuteApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.micmute</string>
    <key>CFBundleName</key>
    <string>Mic Mute</string>
    <key>CFBundleDisplayName</key>
    <string>Mic Mute</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Needed to read and control microphone mute state.</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS doesn't block the unsigned binary
codesign --sign - --force "${BUNDLE}"

echo "Done! MicMuteApp.app is ready."
echo "You can drag it to /Applications or double-click it from Finder."
