---
name: verify
description: Build, launch, and drive MochiBuddy in the iOS simulator to verify changes end-to-end.
---

# Verifying MochiBuddy in the simulator

## Build & install

```bash
xcodebuild -project MochiBuddy.xcodeproj -scheme MochiBuddy \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.1' build
# DerivedData app path (stable hash):
APP=~/Library/Developer/Xcode/DerivedData/MochiBuddy-bmjblmqnjzobxvcnavzmxfgqpbpj/Build/Products/Debug-iphonesimulator/MochiBuddy.app
xcrun simctl boot <UDID>   # iPhone 17 Pro: 5A321FA4-38D8-4092-AEEC-386D1A0A1457
open -a Simulator
xcrun simctl install <UDID> "$APP"
xcrun simctl terminate <UDID> com.aaronmckain.MochiBuddy 2>/dev/null
xcrun simctl launch <UDID> com.aaronmckain.MochiBuddy -mochiLocalMembership -mochiStartAtHome
```

- **Bundle id is `com.aaronmckain.MochiBuddy`** (not com.mochibuddy.app).
- Launch args: `-mochiStartAtHome` (skip onboarding), `-mochiStartTab you|tasks`,
  `-mochiLocalMembership` (UserDefaults membership stub).
- App talks to live Firebase — data persists across relaunches. Clean up any
  test tasks/lists you create (editor → Delete task; Manage lists → trash).
- A system "Apple Account Verification" alert may cover the app on launch —
  AX press does NOT reach it; dismiss with a coordinate click (cliclick) on
  "Not Now" using the Simulator window bounds.
- **Alternate app icons flake in the simulator**: roughly one alternate-icon
  set succeeds per boot — after that, `setAlternateIconName` fails with
  NSPOSIXErrorDomain 35 (EAGAIN) from LSIconAlertManager (icon-change alert
  token leaks; the alert never presents in the sim). Resets to the primary
  icon (nil) usually still work. `simctl shutdown` + `boot` clears it, and
  the app's launch realign (ThemeStore init) fixes a stale icon on next
  launch. Failures log as "Icon sync to '…' failed" (NSLog from
  AppContainer). Device behavior is expected to be fine — the alert
  actually presents there.

## Driving the UI (AppleScript AX)

`entire contents of window 1` works, but **`role of b` errors — read
`value of attribute "AXRole"` / `"AXDescription"` instead**. Reusable presser:

```applescript
-- press.scpt <AXRole> <description ("" = first of role)>
tell application "System Events" to tell process "Simulator"
  set frontmost to true
  set els to entire contents of window 1
  repeat with i from 1 to count of els
    try
      set b to item i of els
      if (value of attribute "AXRole" of b) is targetRole and ¬
         (targetDesc is "" or (value of attribute "AXDescription" of b) is targetDesc) then
        perform action "AXPress" of b
        return "pressed"
      end if
    end try
  end repeat
end tell
```

- Tab bar items are `AXRadioButton` ("Home"/"Tasks"/"You"); seg tabs and most
  controls are `AXButton` with their accessibilityLabel as description; task
  rows press via their title `AXStaticText`.
- Text entry: AXPress the `AXTextField`, then `keystroke "…"` (System Events).
  Keystrokes can truncate if followed too quickly by another action — sleep ≥1s.
  Hardware-keyboard autocorrect DOES fire ("Buuy milk" → "But milk").
- Screenshots: `xcrun simctl io <UDID> screenshot out.png`.
- Scrolling: AX can't press off-screen rows ("not found") — drag-scroll with
  cliclick (this install's cliclick has no `sd`/`su`; use press-drag):
  `cliclick dd:1238,700 dm:1238,600 dm:1238,450 dm:1238,250 du:1238,250`.
- Screenshot px → screen coords for cliclick: with the window at
  {1038, 35, 403x867}, screen ≈ (1038 + px_x/3.0, 13 + px_y/2.9) — derived
  empirically; re-derive the y offset from a known-good click if the window
  moves. Segmented pickers are easier via AX (`AXRadioButton` with the
  segment title, e.g. "24h") than coordinates.
- Chart scrubbing (`chartXSelection`): press-and-hold ~0.5s, then drag in
  small steps (`dd`, sleep, several `dm` with ~0.15s sleeps). Selection
  clears on release, so screenshot BEFORE `du`. Fast synthetic drags are
  swallowed.
- The `press.scpt` "not found" result still exits 0 — `||` fallbacks never
  run; check the printed output instead.

## Flows worth driving

- Home: quick-add type+return (field must clear), plus button (opens editor
  prefilled), toggle row (moves Today ↔ Done today, coins ±10).
- Tasks: 4 segments; Done tab banner X = "Dismiss" (per-day persistence in
  UserDefaults key `mochi.doneCelebrationDismissedDay`).
- Lists: rows push ListDetail; Manage lists create is optimistic.
- Editor: new task auto-focuses title; editing must NOT raise the keyboard.
- Reminders surfaces need a profile with `importedReminderListIds` + granted
  EventKit access — otherwise covered by unit tests only.

## Tests

Same xcodebuild command with `test`. Full suite ≈ 4–6 min.

## Membership / defaults manipulation (learned 2026-07-25)

- `simctl spawn <udid> defaults write com.aaronmckain.MochiBuddy …` writes the
  SIM-GLOBAL domain, NOT the app sandbox — the app never sees it. The app's
  real prefs live at
  `$(xcrun simctl get_app_container <udid> com.aaronmckain.MochiBuddy data)/Library/Preferences/com.aaronmckain.MochiBuddy.plist`.
  Edit with PlistBuddy while the app is TERMINATED (a running process caches
  UserDefaults and flushes over external edits on exit). Back the plist up
  first and restore after — it holds the tester's live membership state.
- PlistBuddy date Set: format `"%a %b %d %H:%M:%S %Y"` works
  (`Set :membership.expiresAt Sat Jul 25 17:55:52 2026`); slash formats
  silently parse wrong. Always `Print` to confirm.
- Foreground-lapse test recipe: set `membership.expiresAt` ~2 min ahead,
  launch with `-mochiLocalMembership` (Splash → home), background via the
  Simulator toolbar "Home" AXButton, wait past expiry, `simctl launch`
  again (same PID = foreground, not relaunch) → the scenePhase hook must
  route to Welcome Back.
- Software keyboard may be hidden (hardware kb mode) — toggle with ⌘K
  before screenshotting keyboard-related layouts.
- iOS 26 renders `ToolbarItemGroup(placement: .keyboard)` as a floating
  circular button above the keyboard, not a full-width accessory bar.
- SwiftUI: `.ignoresSafeArea(.keyboard)` on a child inside a sheet's
  NavigationStack does NOT exempt it from the sheet's keyboard avoidance —
  the pinned-footer ZStack recipe floats mid-sheet. Hide the footer on
  focus instead (TaskEditorView pattern).
- Multiple sim windows: `window 1` in AppleScript is the frontmost device;
  enumerate `windows` by name when two devices are booted, or cliclick
  with that window's bounds.
