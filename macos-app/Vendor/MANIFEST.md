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

## Pinned binaries

SHA-256 of the **zip** = publisher's published checksum (verified on download);
SHA-256 of the **binary** = the extracted, ad-hoc re-signed executable sitting here.

| File | Version | Source URL (exact, not redirect) | SHA-256 (zip / binary) | Date |
|------|---------|----------------------------------|------------------------|------|
| ffmpeg | 8.1.2 (build 1783011502) | https://ffmpeg.martin-riedl.de/download/macos/arm64/1783011502_8.1.2/ffmpeg.zip | zip `ef1aa60006c7b77ce170c1608c08d8e4ba1c30c5746f2ac986ded932d0ac2c3c` / bin `15d322a0576f050a22ed70490848f2590f13981a2eb00d5264f03a1a1357a758` | 2026-07-12 |
| ffprobe | 8.1.2 (build 1783011502) | https://ffmpeg.martin-riedl.de/download/macos/arm64/1783011502_8.1.2/ffprobe.zip | zip `c39787f4af7a3932502d2d48db6f6feaaa836b48a73ef78c32cc3285df61dfaf` / bin `206bfcf4ec2f4c94d552bd52bdda377cf3ecd7c1cef63f05db72c75731991889` | 2026-07-12 |
| gifsicle | 1.96 | copied from `/opt/homebrew/bin/gifsicle` | bin `9bb32495a20b9abb77e6be5f23db751aec59782b32d77cf13de5054b3caf46b7` | 2026-07-12 |

Checklist results (2026-07-12): zips matched publisher SHA-256; `lipo -archs` → arm64
both; `otool -L` → system frameworks/dylibs only; libx264 + libx265 + libsvtav1 all
present; ad-hoc signed + quarantine stripped; **acceptance gate green — 31/31 engine
tests incl. 7 integration tests via `CONVERTER_TOOLS_DIR=$PWD/Vendor … swift test`**.

## Post-download checklist

1. `shasum -a 256 <file>` matches the publisher's checksum → record above.
2. `lipo -archs ffmpeg` → arm64; `otool -L ffmpeg | wc -l` → libSystem-ish only.
3. `./ffmpeg -encoders | grep -E 'libx264|libx265|libsvtav1'` → all three present.
4. Ad-hoc sign: `codesign --force -s - ffmpeg ffprobe gifsicle`
   (Gatekeeper quarantine: `xattr -d com.apple.quarantine <file>` after verifying).
5. `CONVERTER_TOOLS_DIR=<this dir> DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
   swift test` in Packages/ConverterEngine — the integration suite is the acceptance gate
   (`Tools.fromEnvironment()` honors the override).
