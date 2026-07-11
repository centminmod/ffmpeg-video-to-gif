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

## Findings (2026-07-12, macOS 15.7)

- **Enablement:** confirmed — ConvertActionExt appeared in System Settings ▸ Extensions ▸
  Finder **disabled by default**; after enabling it shows under Finder ▸ right-click ▸
  Quick Actions. The PRD's onboarding step stands.
- **⚠️ Editor-role hazard (verified the hard way):** the Xcode template ships
  `NSExtensionServiceRoleType = NSExtensionServiceRoleTypeEditor`. Editor role makes
  Finder move the selected originals into a hidden `NSItemReplacementDirectory` staging
  folder (`<volume>/.TemporaryItems/folders.<uid>/TemporaryItems/NSIRD_Finder_*`)
  expecting replacements back; completing with empty `returningItems` strands them there —
  the files "disappear" from their folder (recoverable by moving them back, but a
  sandboxed/TCC-restricted process cannot; Finder or a Full-Disk-Access terminal can).
  **The real app MUST use `NSExtensionServiceRoleTypeViewer`** (a converter creates new
  files, never edits inputs) **and return `context.inputItems` unchanged.** Both applied
  here and in this folder's `ActionRequestHandler.swift`/generated Info.plist.
- **Attachment types:** Finder registers attachments under the file's CONTENT type
  (`public.mpeg-4`), NOT `public.file-url` — a `.fileURL` conformance filter matches
  nothing ("received 0 URL(s)"). Ask each provider for its own
  `registeredTypeIdentifiers` and use `loadInPlaceFileRepresentation` — verified to
  deliver real in-place paths (`[inPlace=true]`) even on an external volume, from
  inside the sandboxed (`plugin` profile) extension process.
- **Multi-select:** a 3-file selection = **ONE invocation**, 1 `NSExtensionItem` with
  3 attachments. (The earlier one-staging-dir-per-file observation was the Editor-role
  replacement machinery, not separate invocations.)
- **Stale-extension gotcha:** after replacing the appex on disk, Finder can keep
  serving a cached instance whose clicks do nothing (zero log activity). Fix:
  `killall Finder` + `pluginkit -e use -i <id>`.

## VERDICT — Vehicle A (non-UI Action Extension) is the M2 vehicle

Everything the PRD needs is confirmed: fires from Finder ▸ Quick Actions, one
invocation per multi-select, real in-place file paths under sandbox, one-time
System Settings enablement (onboarding step). Vehicle B (App Intents/Shortcuts)
was not needed — it requires MORE user assembly (create shortcut + tick "Use as
Quick Action") and offers no advantage for this use case; its code stays here only
as a fallback reference.
