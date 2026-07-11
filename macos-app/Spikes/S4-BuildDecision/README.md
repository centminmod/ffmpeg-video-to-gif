# S4 — vendored-binary decision (arch slice + build-vs-prebuilt)

**Question (PRD §7):** which exact ffmpeg/ffprobe/gifsicle binaries go in `Vendor/` for
M0b? Phase 1 posture: **arm64-only**, ad-hoc signed, sandbox off.

Run [probe-ffmpeg.sh](probe-ffmpeg.sh) to capture the current Homebrew baseline
(version, arch, dylib count, encoder availability) — paste its output below.

## Options

| | Option | Phase 1 fit | Phase 2 (share/sell) fit |
|---|--------|-------------|--------------------------|
| A | **Pin a known static arm64 build** (e.g. osxexperts.net, martin-riedl.de) | Fastest — download, checksum-pin, drop in `Vendor/` | Weak: GPL corresponding-source means *their* exact scripts/flags; must be re-verified or replaced |
| B | **Scripted build from source** (pinned ffmpeg tag + x264/x265/svt-av1, `--pkg-config-flags=--static`) | ~1–2 h one-time; fully reproducible | Strong: the build script *is* the corresponding-source story |
| C | Re-link Homebrew bottles (`install_name_tool` dylib rewriting) | Fragile (dozens of dylibs, per-upgrade breakage) | Poor | 

**Recommendation:** **A for Phase 1** (unblocks M0b this week; record URL + SHA-256 in
`Vendor/MANIFEST.md`), and write the **B build script during M4** if Phase 2 ever
happens. gifsicle is trivial either way (tiny, few deps — a static build is one
`./configure && make` or vendor Homebrew's after checking `otool -L`).

## Exit criteria (fill in, then update PRD §7 "Still open")

- [ ] probe output pasted below
- [ ] chosen source for static arm64 ffmpeg + ffprobe (URL + SHA-256)
- [ ] confirmed encoders present: `libx264`, `libx265`, `libsvtav1` (AV1 optional per PRD)
- [ ] confirmed `ffprobe` JSON output works: `ffprobe -v error -print_format json -show_format -show_streams <file>`
- [ ] gifsicle plan (static build vs vendored brew binary)

## Probe output (2026-07-12)

```
ffmpeg  /opt/homebrew/bin/ffmpeg   arm64  35 dylibs (17 from /opt/homebrew)
ffprobe /opt/homebrew/bin/ffprobe  arm64  35 dylibs (17 from /opt/homebrew)
gifsicle /opt/homebrew/bin/gifsicle arm64  1 dylib (0 from /opt/homebrew)
ffmpeg 8.1 (--enable-shared --enable-gpl): libx264 ✓ libx265 ✓ libsvtav1 ✓
                                           h264/hevc/prores_videotoolbox ✓
```

Findings:
- **gifsicle is already vendorable as-is** — its only dylib is `/usr/lib/libSystem`.
  Copy the brew binary into `Vendor/`, done.
- ffmpeg/ffprobe confirm the expected shape: shared Homebrew builds, 17 brew dylib deps
  each → Option A (pinned static arm64 build) or B (scripted build) required.
- All three target encoders (x264, x265, svt-av1) plus VideoToolbox exist in brew's
  build — useful as the golden-parity *reference* encoder while `Vendor/` is decided.
