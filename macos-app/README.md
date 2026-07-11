# macos-app — VidConvert (working name)

SwiftUI macOS app replacing the Automator Quick Actions with drag-and-drop video
conversion. Engine and presets are ports of [`vid2gif_func.sh`](../vid2gif_func.sh)
(which stays untouched — it is the canonical spec the app is tested against).

Plan/PRD: [PRD-macos-converter-app.md](../PRD-macos-converter-app.md) — decisions locked:
engine = bundled ffmpeg (Option B), UI = SwiftUI (Plan A), Phase 1 = personal use
(arm64-only, sandbox off, ad-hoc signing).

## Current milestone: M0a — platform spike week

| # | Spike | Question it answers | Runs with | Status |
|---|-------|--------------------|-----------|--------|
| S1 | [Spikes/S1-DropTarget](Spikes/S1-DropTarget) | Does `.dropDestination(for: URL.self)` handle real Finder drags (multi-file, folders, promised files), or do we need the `onDrop`/NSItemProvider fallback? | `swift run` (CLT is enough) | ☐ |
| S2 | [Spikes/S2-QuickAction](Spikes/S2-QuickAction) | Which vehicle actually surfaces in Finder ▸ Quick Actions on macOS 15: non-UI Action Extension or App Intents/Shortcuts? | Xcode (see toolchain note) | ☐ |
| S3 | [Spikes/S3-Sandbox](Spikes/S3-Sandbox) | Under App Sandbox: does a spawned child inherit security-scoped file access, and can we write next to the source? (Phase 2 question — Phase 1 ships sandbox-off regardless) | `./run.sh` (CLT is enough) | ☐ |
| S4 | [Spikes/S4-BuildDecision](Spikes/S4-BuildDecision) | Which ffmpeg/ffprobe/gifsicle binaries do we vendor (arch slice, static-vs-build)? | `./probe-ffmpeg.sh` | ☐ |

Exit criteria feed M0b (the `ConverterEngine` package + golden-parity tests): S1 picks the
drop implementation, S2 picks the Finder vehicle for M2, S3 decides sandbox-on feasibility
for Phase 2, S4 pins the vendored binaries.

## Toolchain note

This Mac has full **Xcode 26.2** at `/Applications/Xcode.app`, but `xcode-select` points at
the Command Line Tools, so `xcodebuild` fails by default. S1/S3/S4 don't care. For S2 either:

- one-off: prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, or
- permanent: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`

## Layout (grows in M0b)

```
macos-app/
  Spikes/            # M0a throwaway prototypes — findings graduate into the PRD + engine
  Packages/          # (M0b) ConverterEngine SPM package
  VidConvert/        # (M1) the SwiftUI app target
  Vendor/            # (M0b) pinned ffmpeg / ffprobe / gifsicle binaries
```
