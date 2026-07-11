#!/bin/zsh
# S4 data gathering: what does the current (Homebrew) toolchain look like, and how far
# is it from something vendorable? Read-only — changes nothing.
set -euo pipefail

for tool in ffmpeg ffprobe gifsicle; do
  BIN=$(command -v "$tool") || { echo "== $tool: NOT FOUND"; continue; }
  echo "== $tool: $BIN"
  echo "   arch: $(lipo -archs "$BIN" 2>/dev/null || file -b "$BIN")"
  DEPS=$(otool -L "$BIN" | tail -n +2)
  echo "   dylibs: $(echo "$DEPS" | grep -c .) total, $(echo "$DEPS" | grep -c '/opt/homebrew' || true) from /opt/homebrew"
done

echo "== ffmpeg version"
ffmpeg -hide_banner -version | head -3

echo "== encoders of interest"
ffmpeg -hide_banner -encoders 2>/dev/null | grep -E 'libx264|libx265|libsvtav1|libaom|videotoolbox' || echo "   (none matched)"

echo "== verdict"
echo "   A Homebrew binary with /opt/homebrew dylib deps cannot be vendored as-is;"
echo "   see README options A/B. Zero /opt/homebrew deps would mean it's already static."
