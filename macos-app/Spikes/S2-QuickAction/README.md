# S2 — Finder Quick Action vehicle spike

**Question (PRD §4/§7):** on macOS 15, which vehicle actually shows up under Finder ▸
right-click ▸ Quick Actions for video files — a non-UI **Action Extension**, or an
**App Intent** exposed via Shortcuts? The panel review disagreed; prototype both.

This spike needs real Xcode targets (extensions can't be built with CLT alone). The Swift
sources here are ready to paste; the project itself is created in Xcode (~15 min).

Xcode is installed but not selected — launch it directly (`open /Applications/Xcode.app`)
or run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` once.

## Setup

1. Xcode ▸ New Project ▸ macOS ▸ App — name `QuickActionSpike`, SwiftUI, no tests.
   Signing: "Sign to Run Locally" (Phase 1 posture; no team needed).
2. **Vehicle A:** File ▸ New ▸ Target ▸ macOS ▸ **Action Extension**, name
   `ConvertActionExt`, *Action type: No User Interface*. Replace the generated handler
   with [ActionRequestHandler.swift](ActionRequestHandler.swift). In the extension's
   Info.plist set `NSExtensionActivationRule` (under `NSExtensionAttributes`) to the
   string `TRUEPREDICATE` for the spike (any file type; tighten to a movie-UTI
   predicate later).
3. **Vehicle B:** add [ConvertVideoIntent.swift](ConvertVideoIntent.swift) to the *app*
   target (it includes an `AppShortcutsProvider`).
4. Build & run once so LaunchServices registers app + extension.

## What to record (fills the PRD §7 risk row)

- System Settings ▸ General ▸ Login Items & Extensions ▸ Finder/Actions: does
  `ConvertActionExt` appear, and is it **enabled by default or off**? (PRD expects off —
  confirms the onboarding step.)
- Finder ▸ right-click a `.mov` ▸ Quick Actions: does Vehicle A appear? Does it receive
  the file (check Console.app for the `QuickActionSpike received` log line)?
- Shortcuts.app: create a shortcut from `Convert Video (Spike)`, tick "Use as Quick
  Action" ▸ Finder. Does it appear in the same menu? How many clicks of user assembly
  did that take vs Vehicle A?
- Multi-select: right-click 3 files at once — does each vehicle get all 3 in one
  invocation or 3 separate invocations?

**Decision rule:** prefer the vehicle that (a) receives multi-file selections in one
invocation and (b) needs the least user assembly. Expected winner is Vehicle A with a
one-time enable step, but that's exactly what the spike verifies.
