#!/bin/zsh
# Build, ad-hoc sign (sandboxed), and launch the S3 spike.
#   ./run.sh                          — T1 + T2 only
#   ./run.sh /path/to/static/ffprobe  — also bundle a helper for T3
#     (must be a STATIC ffprobe — Homebrew's can't load /opt/homebrew dylibs in-sandbox)
set -euo pipefail
cd "$(dirname "$0")"

APP=SandboxSpike.app
# A still-running instance makes `open` re-activate it instead of launching
# fresh (the file panel only shows at launch) — kill it first.
killall SandboxSpike 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -o "$APP/Contents/MacOS/SandboxSpike" main.swift

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>local.spike.sandbox</string>
	<key>CFBundleName</key>
	<string>SandboxSpike</string>
	<key>CFBundleExecutable</key>
	<string>SandboxSpike</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
</dict>
</plist>
EOF

if [ $# -ge 1 ]; then
  mkdir -p "$APP/Contents/Helpers"
  cp "$1" "$APP/Contents/Helpers/ffprobe"
  codesign --force -s - --entitlements inherit.entitlements "$APP/Contents/Helpers/ffprobe"
fi

codesign --force -s - --entitlements app.entitlements "$APP"
open "$APP"
echo "launched — results appear in the app window (and in Console.app under SandboxSpike)"
