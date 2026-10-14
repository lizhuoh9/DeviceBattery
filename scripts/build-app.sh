#!/bin/zsh
# Builds "Device Battery.app" in the project folder: release binary, Info.plist, icon,
# ad-hoc signature. Re-signing changes the code identity, so macOS asks for the
# Input Monitoring permission again after each rebuild.
set -euo pipefail
cd "${0:A:h}/.."

app="Device Battery.app"
work=".build/app"

swift build -c release
mkdir -p "$work"

if [[ ! -f "$work/AppIcon.icns" ]]; then
  swift scripts/make-icon.swift "$work/AppIcon.iconset"
  iconutil -c icns "$work/AppIcon.iconset" -o "$work/AppIcon.icns"
fi

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/DeviceBattery" "$app/Contents/MacOS/DeviceBattery"
strip -x "$app/Contents/MacOS/DeviceBattery"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp "$work/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier local.DeviceBattery "$app"

echo "Built $(pwd)/$app ($(du -sh "$app" | cut -f1))"
