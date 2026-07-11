# Vendor/ — pinned binaries (S4 decision)

Phase 1 posture: **arm64-only static binaries**, ad-hoc signed, vendored here and
copied into the app bundle's `Contents/Helpers/` at build time. Never committed to
git (see .gitignore) — this manifest pins exactly what to fetch instead.

## Decision (M0a S4, finalized during M0b)

| Tool | Source | Why |
|------|--------|-----|
| ffmpeg, ffprobe | **martin-riedl.de build server** — `https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip` (and `…/ffprobe.zip`) | Static arm64, release channel, SHA-256 published per build, **open-source build pipeline** (the Phase 2 GPL corresponding-source trail); includes libx264/libx265/libsvtav1 (verify per download) |
| gifsicle | copy of Homebrew binary | Already effectively static — sole dylib is `/usr/lib/libSystem` (S4 probe, 2026-07-12) |

Fallback source: osxexperts.net (static arm64, SHA-256 given, but no published build
scripts). evermeet.cx is Intel-only — not usable.

## Fill in when downloaded (one row per pinned binary)

| File | Version | Source URL (exact, not redirect) | SHA-256 | Date |
|------|---------|----------------------------------|---------|------|
| ffmpeg | | | | |
| ffprobe | | | | |
| gifsicle | | (from /opt/homebrew, version `gifsicle --version`) | | |

## Post-download checklist

1. `shasum -a 256 <file>` matches the publisher's checksum → record above.
2. `lipo -archs ffmpeg` → arm64; `otool -L ffmpeg | wc -l` → libSystem-ish only.
3. `./ffmpeg -encoders | grep -E 'libx264|libx265|libsvtav1'` → all three present.
4. Ad-hoc sign: `codesign --force -s - ffmpeg ffprobe gifsicle`
   (Gatekeeper quarantine: `xattr -d com.apple.quarantine <file>` after verifying).
5. `swift test` in Packages/ConverterEngine with `Tools.bundled`-style paths pointed
   here — the integration suite is the acceptance gate.
