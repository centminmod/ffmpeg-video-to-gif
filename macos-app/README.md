# macos-app — VidConvert (working name)

SwiftUI macOS app replacing the Automator Quick Actions with drag-and-drop video
conversion. Engine and presets are ports of [`vid2gif_func.sh`](../vid2gif_func.sh)
(which stays untouched — it is the canonical spec the app is tested against).

Plan/PRD: [PRD-macos-converter-app.md](../PRD-macos-converter-app.md) — decisions locked:
engine = bundled ffmpeg (Option B), UI = SwiftUI (Plan A), Phase 1 = personal use
(arm64-only, sandbox off, ad-hoc signing).

**Status:** M0a spikes ✅ · M0b engine ✅ · M1 app ✅ (in daily-driver trial) · M2 Finder
Quick Action ✅ built (right-click test pending) · next: M3 nice-to-haves. Launch the app
with `open VidConvert/build/VidConvert.app` (rebuild first via `./VidConvert/build-app.sh`
if sources changed).

## M2 — Finder Quick Action ("Convert with VidConvert")

Non-UI Action Extension per the S2 verdict, hand-built by `build-app.sh` with `swiftc`
(entry point `_NSExtensionMain` — no Xcode project needed) into
`VidConvert.app/Contents/PlugIns/VidConvertAction.appex`. Sources in
[VidConvert/Extension/](VidConvert/Extension/). How it works:

- Viewer role + returns `context.inputItems` (S2's Editor-role hazard), collects
  in-place URLs via `loadInPlaceFileRepresentation`.
- Hands the URLs to VidConvert.app with `NSWorkspace.open(_:withApplicationAt:)` —
  the app queues them via `application(_:open:)` with the currently selected preset,
  exactly like a drop. (The PRD's app-group *bookmark* handoff is only needed once the
  app itself is sandboxed — deferred to Phase 2.)
- Activation rule shows the menu item only for selections containing movie/video UTIs;
  bare-UTI containers (mkv/webm without a claiming app) won't activate it — drag-and-drop
  still accepts them.
- Enablement: registered + elected via `pluginkit -e use -i local.vidconvert.action`
  (otherwise System Settings ▸ Login Items & Extensions ▸ Finder). If the menu item
  doesn't appear after a rebuild, Finder cached the old appex: `killall Finder`.

## M0a — platform spike week (complete)

| # | Spike | Question it answers | Runs with | Status |
|---|-------|--------------------|-----------|--------|
| S1 | [Spikes/S1-DropTarget](Spikes/S1-DropTarget) | Does `.dropDestination(for: URL.self)` handle real Finder drags (multi-file, folders, promised files), or do we need the `onDrop`/NSItemProvider fallback? | `swift run` (CLT is enough) | 🟡 single/multi-file Finder drops PASS on both zones (2026-07-12); folder + Photos promised-file drags untested |
| S2 | [Spikes/S2-QuickAction](Spikes/S2-QuickAction) | Which vehicle actually surfaces in Finder ▸ Quick Actions on macOS 15: non-UI Action Extension or App Intents/Shortcuts? | Xcode (see toolchain note) | ✅ **Action Extension wins** — see README verdict + Editor-role hazard |
| S3 | [Spikes/S3-Sandbox](Spikes/S3-Sandbox) | Under App Sandbox: does a spawned child inherit security-scoped file access, and can we write next to the source? (Phase 2 question — Phase 1 ships sandbox-off regardless) | `./run.sh` (CLT is enough) | ✅ T1 PASS (child inherits scoped read — sandbox-on viable for Phase 2); T2 FAIL as predicted (no sibling writes → fallback output folder when sandboxed) |
| S4 | [Spikes/S4-BuildDecision](Spikes/S4-BuildDecision) | Which ffmpeg/ffprobe/gifsicle binaries do we vendor (arch slice, static-vs-build)? | `./probe-ffmpeg.sh` | ✅ **martin-riedl.de static arm64 release builds** (open-source build pipeline = GPL trail); gifsicle from brew as-is — see [Vendor/MANIFEST.md](../Vendor/MANIFEST.md) |

Exit criteria feed M0b (the `ConverterEngine` package + golden-parity tests): S1 picks the
drop implementation (→ `.dropDestination`, fallback not needed so far), S2 picks the Finder
vehicle for M2 (→ Action Extension, Viewer role), S3 decides sandbox-on feasibility for
Phase 2 (→ viable), S4 pins the vendored binaries (→ static arm64 from martin-riedl.de,
pinned with checksums in [Vendor/MANIFEST.md](Vendor/MANIFEST.md)).

## Toolchain note

This Mac has full **Xcode 26.2** at `/Applications/Xcode.app`, but `xcode-select` points at
the Command Line Tools, so `xcodebuild` fails by default. S1/S3/S4 don't care. For S2 either:

- one-off: prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, or
- permanent: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`

## Layout (grows in M0b)

```
macos-app/
  Spikes/            # M0a throwaway prototypes — findings graduate into the PRD + engine
  Packages/ConverterEngine/   # (M0b ✅) UI-agnostic engine: command builder with the
                              # B1–B10 fixes, ffprobe JSON probe, -progress parser,
                              # process runner, job orchestration. 31 tests incl. 7
                              # end-to-end integration tests against real ffmpeg.
                              # Run: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
                              # (CLT alone lacks XCTest)
  VidConvert/        # (M1 ✅) the SwiftUI app: drop zone (dropDestination per S1),
                     # preset chips (Preset.all), serial queue driven by ConversionJob,
                     # per-item progress/cancel, reveal-in-Finder, failure rows with
                     # stderr tail, confirm-on-quit while converting.
                     # Extension/ (M2 ✅): the Finder Quick Action appex — see above.
                     # Build the .app (bundles Vendor/ into Contents/Helpers + the
                     # appex into Contents/PlugIns, ad-hoc signs):
                     # ./VidConvert/build-app.sh  →  open VidConvert/build/VidConvert.app
                     # Dev loop: swift run (falls back to Homebrew tools, or set
                     # CONVERTER_TOOLS_DIR=…/Vendor)
  Vendor/            # (✅ pinned 2026-07-12) ffmpeg/ffprobe 8.1.2 static arm64 from
                     # martin-riedl.de + brew gifsicle 1.96 — checksums & acceptance
                     # results in Vendor/MANIFEST.md; binaries stay out of git
```
