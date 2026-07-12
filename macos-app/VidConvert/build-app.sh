#!/bin/zsh
# Assembles VidConvert.app (Phase 1 posture: arm64, sandbox off, ad-hoc signed) from
# the SPM release build + the pinned Vendor/ binaries in Contents/Helpers.
#
#   ./build-app.sh            build into build/VidConvert.app only
#   ./build-app.sh --install  … then install to /Applications and re-register the
#                             app + Finder Quick Action there (build/ stays disposable)
set -euo pipefail
cd "$(dirname "$0")"
INSTALL=0
[ "${1:-}" = "--install" ] && INSTALL=1

for tool in ffmpeg ffprobe gifsicle; do
  [ -x "../Vendor/$tool" ] || { echo "ERROR: ../Vendor/$tool missing — see ../Vendor/MANIFEST.md" >&2; exit 1; }
done

swift build -c release

# App icon: regenerate only when the generator changed (make-style staleness check).
# The .icns lives in disposable build/ (gitignored), never in the repo.
ICNS=build/AppIcon.icns
if [ ! -f "$ICNS" ] || [ Tools/make-icon.swift -nt "$ICNS" ]; then
  ICONSET=build/AppIcon.iconset
  rm -rf "$ICONSET"
  swift Tools/make-icon.swift "$ICONSET"
  iconutil -c icns "$ICONSET" -o "$ICNS"
  rm -rf "$ICONSET"
fi

APP=build/VidConvert.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp .build/release/VidConvert "$APP/Contents/MacOS/VidConvert"
cp Info.plist "$APP/Contents/Info.plist"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
cp ../Vendor/ffmpeg ../Vendor/ffprobe ../Vendor/gifsicle "$APP/Contents/Helpers/"

# M2 Finder Quick Actions, built without an Xcode project: a non-UI Action Extension
# is a plain executable whose entry point is Foundation's NSExtensionMain. ONE binary,
# NINE appexes — each Info.plist stamped with its preset so Finder shows one menu
# entry per format (mirroring the old Automator workflows).
# No -application-extension flag: the handler needs NSWorkspace for the app handoff.
EXT_BIN=build/VidConvertAction
xcrun swiftc Extension/ActionRequestHandler.swift \
  -o "$EXT_BIN" \
  -module-name VidConvertAction -parse-as-library -O \
  -target arm64-apple-macos14.0 \
  -framework AppKit \
  -Xlinker -e -Xlinker _NSExtensionMain

# menu label | engine preset id | bundle-id suffix (Preset.all in ConversionOptions.swift)
PRESET_ACTIONS=(
  "VidConvert: H.264|mp4-h264|h264"
  "VidConvert: H.264 ½|mp4-h264-half|h264-half"
  "VidConvert: H.265|mp4-h265|h265"
  "VidConvert: H.265 ½|mp4-h265-half|h265-half"
  "VidConvert: H.264 ⚡|mp4-h264-vt|h264-vt"
  "VidConvert: H.265 ⚡|mp4-h265-vt|h265-vt"
  "VidConvert: GIF ⅓|gif-small|gif"
  "VidConvert: GIF full|gif-full|gif-full"
  "VidConvert: AV1|mp4-av1|av1"
)
for entry in "${PRESET_ACTIONS[@]}"; do
  IFS='|' read -r NAME PRESET SUFFIX <<< "$entry"
  APPEX="$APP/Contents/PlugIns/VidConvertAction-$SUFFIX.appex"
  mkdir -p "$APPEX/Contents/MacOS"
  cp "$EXT_BIN" "$APPEX/Contents/MacOS/VidConvertAction"
  cp Extension/Info.plist "$APPEX/Contents/Info.plist"
  plutil -replace CFBundleIdentifier -string "local.vidconvert.action.$SUFFIX" "$APPEX/Contents/Info.plist"
  plutil -replace CFBundleDisplayName -string "$NAME" "$APPEX/Contents/Info.plist"
  plutil -replace VidConvertPresetID -string "$PRESET" "$APPEX/Contents/Info.plist"
done

# Inner-to-outer: helpers and appexes first (appexes sandboxed — extensions require it).
codesign --force -s - "$APP/Contents/Helpers/"*
codesign --force -s - --entitlements Extension/VidConvertAction.entitlements \
  "$APP/Contents/PlugIns/"*.appex
codesign --force -s - "$APP"
echo "Built $PWD/$APP"

if [ "$INSTALL" = 1 ]; then
  DEST=/Applications/VidConvert.app
  LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  osascript -e 'if application "VidConvert" is running then quit app "VidConvert"' >/dev/null 2>&1 || true
  sleep 1
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  # One registered copy only: retire the build-dir registration, register /Applications,
  # and elect the Quick Action so it shows without a System Settings visit.
  "$LSREGISTER" -u "$PWD/$APP" || true
  "$LSREGISTER" -f "$DEST"
  # pluginkit discovery lags behind lsregister — add each appex explicitly, then elect.
  for appex in "$DEST/Contents/PlugIns/"*.appex; do
    pluginkit -a "$appex" || true
  done
  sleep 1
  for entry in "${PRESET_ACTIONS[@]}"; do
    IFS='|' read -r NAME PRESET SUFFIX <<< "$entry"
    pluginkit -e use -i "local.vidconvert.action.$SUFFIX" || true
  done
  echo "Installed $DEST"
  echo "If the Quick Action doesn't appear in Finder, run: killall Finder"
else
  echo "Launch: open $PWD/$APP   (or install: ./build-app.sh --install)"
fi
