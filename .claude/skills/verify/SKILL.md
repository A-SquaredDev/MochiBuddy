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
