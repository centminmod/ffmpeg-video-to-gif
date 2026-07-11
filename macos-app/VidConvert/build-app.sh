#!/bin/zsh
# Assembles VidConvert.app (Phase 1 posture: arm64, sandbox off, ad-hoc signed) from
# the SPM release build + the pinned Vendor/ binaries in Contents/Helpers.
set -euo pipefail
cd "$(dirname "$0")"

for tool in ffmpeg ffprobe gifsicle; do
  [ -x "../Vendor/$tool" ] || { echo "ERROR: ../Vendor/$tool missing — see ../Vendor/MANIFEST.md" >&2; exit 1; }
done

swift build -c release

APP=build/VidConvert.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers"
cp .build/release/VidConvert "$APP/Contents/MacOS/VidConvert"
cp Info.plist "$APP/Contents/Info.plist"
cp ../Vendor/ffmpeg ../Vendor/ffprobe ../Vendor/gifsicle "$APP/Contents/Helpers/"

# M2 Finder Quick Action appex, built without an Xcode project: a non-UI Action
# Extension is a plain executable whose entry point is Foundation's NSExtensionMain.
# No -application-extension flag: the handler needs NSWorkspace for the app handoff.
APPEX="$APP/Contents/PlugIns/VidConvertAction.appex"
mkdir -p "$APPEX/Contents/MacOS"
xcrun swiftc Extension/ActionRequestHandler.swift \
  -o "$APPEX/Contents/MacOS/VidConvertAction" \
  -module-name VidConvertAction -parse-as-library -O \
  -target arm64-apple-macos14.0 \
  -framework AppKit \
  -Xlinker -e -Xlinker _NSExtensionMain
cp Extension/Info.plist "$APPEX/Contents/Info.plist"

# Inner-to-outer: helpers and appex first (appex sandboxed — extensions require it).
codesign --force -s - "$APP/Contents/Helpers/"*
codesign --force -s - --entitlements Extension/VidConvertAction.entitlements "$APPEX"
codesign --force -s - "$APP"
echo "Built $PWD/$APP"
echo "Launch: open $PWD/$APP"
