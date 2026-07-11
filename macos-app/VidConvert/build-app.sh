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

codesign --force -s - "$APP/Contents/Helpers/"* "$APP"
echo "Built $PWD/$APP"
echo "Launch: open $PWD/$APP"
