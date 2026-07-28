# TestFlight submission checklist

Status as of July 27, 2026. Code is feature-complete (v0.7 Personal Layer
shipped, full suite green). Every item now carries a **Verify** block with
concrete steps to confirm it, since most of the external setup has been done
from the console side. Items marked done on July 27 were reported complete;
run their Verify steps once to confirm, then they need nothing further.
Companion doc: the "Outstanding external setup" section in
`mochi-requirements.md`.

## Code side

- [x] **`ITSAppUsesNonExemptEncryption` = `NO`** in `MochiBuddy/Info.plist`.
  Done July 27.
  **Verify:** the key is at the top of `MochiBuddy/Info.plist` with value
  `<false/>`. After the next upload, the build in App Store Connect ->
  TestFlight should show no yellow "Missing Compliance" badge and needs no
  manual export questionnaire.

## Blocking: before a build reaches internal testers

- [x] **Deploy `firestore.rules`.** Done: verified July 27 by diffing the
  console's live rules against the repo's `firestore.rules`; byte-for-byte
  identical, moments block included. All Firebase console work is now
  complete.
  **Verify (in app, optional belt-and-suspenders):** create a moment in the
  Journal tab, force-quit, and relaunch; the moment persists with no
  "Missing or insufficient permissions" in the Xcode console.

- [x] **App record in App Store Connect** for `com.aaronmckain.MochiBuddy`.
  Reported done July 27.
  **Verify:** appstoreconnect.apple.com -> Apps shows MochiBuddy; open App
  Information and confirm the Bundle ID reads exactly
  `com.aaronmckain.MochiBuddy`. An exact match is required or the Xcode
  upload will not attach to this record.

- [x] **Paid Apps agreement + banking/tax in App Store Connect.** Reported
  done July 27.
  **Verify:** ASC -> Business (Agreements, Tax, and Banking) -> the Paid
  Apps agreement row shows status **Active**. Functional proof: real
  localized prices load on the paywall in a TestFlight build.

- [x] **The two subscriptions in ASC** (`mochi_2999_1y`, `mochi_399_1m`).
  Reported done July 27.
  **Verify (ASC):** MochiBuddy -> Monetization -> Subscriptions; both
  product IDs are listed inside a subscription group with status "Ready to
  Submit" (not "Missing Metadata").
  **Verify (in app):** run a debug build and check the RevenueCat SDK log
  output for the offerings fetch; it should list both product IDs with
  prices returned from the App Store, not an "offerings empty" or products
  warning.

- [x] **Push main to origin.** Done July 27: all 42 commits pushed
  (`6b34afd..6184919`), verified `git rev-list --count origin/main..main`
  prints `0`. Note the July 27 working-tree edits (Info.plist encryption
  key, this checklist) still need a commit + push before archiving.
  **Verify:** `git rev-list --count origin/main..main` prints `0` and
  `git status` is clean before archiving.

- [ ] **Archive and upload from Xcode** (Product -> Archive -> Distribute).
  Automatic signing already handles app + widget + App Group +
  time-sensitive entitlements on device. Version 1.0 (1) is fine for a
  first upload.
  **Verify:** Xcode -> Window -> Organizer lists the archive; ASC ->
  TestFlight -> iOS shows the build move from "Processing" to ready
  (usually under an hour), with no Missing Compliance badge.

- [ ] **Add internal testers in TestFlight.** Internal testing needs no
  Beta App Review, no privacy policy URL, no screenshots.
  **Verify:** ASC -> TestFlight -> Internal Testing group lists the
  testers, each showing Invited and then Installed once they accept; the
  TestFlight app on their device shows MochiBuddy with the uploaded build
  number.

## Soon after: correctness during testing

- [x] **RevenueCat: App Store Connect API key uploaded.** Reported done
  July 27.
  **Verify:** RevenueCat dashboard -> project settings -> the App Store
  app's configuration shows the API key present with no warning banner. A
  stronger functional check: dashboard -> Product catalog -> Import
  products succeeds and pulls both subscriptions from ASC, which only works
  with a valid key.

- [x] **App Store server notification URL** from RevenueCat pasted into ASC.
  Done July 27: both Production and Sandbox URLs set to the RevenueCat
  incoming-webhook URL (screenshot confirmed).
  **Verify (functional):** after a sandbox purchase, the RevenueCat
  customer's event history shows renewal events arriving on their own
  (sandbox monthly renews every few minutes), which proves ASC is calling
  the URL.

- [x] **Firebase Authentication: Google provider enabled.** Reported done
  July 27.
  **Verify:** Firebase console -> Authentication -> Sign-in method shows
  Google as Enabled. In app: complete a Google sign-in, then console ->
  Authentication -> Users shows the account with the Google provider icon.

- [x] **Purchase testing on a physical device** with a Sandbox Apple
  Account. Reported done July 27.
  **Verify:** the durable evidence is in RevenueCat: dashboard -> Customers
  shows the sandbox user with the entitlement active and a purchase in its
  event history. On the device, Settings -> Developer -> Sandbox Apple
  Account (or Settings -> App Store on older iOS) shows the sandbox account
  signed in, and the app's premium features are unlocked.

## Later: external testers / App Review

- [ ] **Legal URLs are placeholders** (`You/MochiLinks.swift`): privacy
  policy points at `https://mochibuddy.app/privacy`, which does not resolve
  yet; EULA uses Apple's standard agreement (fine to keep). External-tester
  Beta App Review needs a real privacy policy URL.
  **Verify (when done):** both URLs in `MochiLinks.swift` open in Safari on
  a device that is not signed in anywhere, and the ASC App Information
  privacy policy field contains the same URL.

- [ ] **Subscription review screenshots** for both products in ASC.
  **Verify:** each subscription's page in ASC shows an uploaded review
  screenshot and the product status is "Ready to Submit" with no yellow
  "Missing Metadata" flag.

- [x] **RevenueCat customer deletion on account delete.** Confirmed done
  July 27 (server-side; the deletion lives outside this repo, since the
  client flow erases Firestore and Auth but cannot hold the secret key).
  This is a privacy-completeness step (the account-deletion flow should
  erase all personal data the app holds), NOT a purchase revocation. The
  subscription itself belongs to the Apple ID, so deleting the RevenueCat
  customer neither cancels billing nor blocks a later restore: if the user
  returns, Restore Purchases reads the Apple receipt on device and
  RevenueCat re-attaches the entitlement to the new app user id.
  **Verify (when done):** create a throwaway account, sign in once so
  RevenueCat registers the customer, delete the account in the app, then
  search RevenueCat -> Customers for that app user ID; it should be gone
  (or show as deleted).

- [x] **Themed launch screen.** Done July 27: `UILaunchScreen` dict in
  `MochiBuddy/Info.plist` points `UIColorName` at the new `LaunchBackground`
  color set (light `#FAF5F1` warm neutral blending the four light flavors,
  dark `#211E2A` Black Sesame bg); `INFOPLIST_KEY_UILaunchScreen_Generation`
  removed from both app configs so the plist dict is the only source.
  Verified in the simulator: dark cold launch shows the plum background
  flowing seamlessly into the splash. Light variant follows the system
  appearance (a static launch screen cannot know the chosen flavor).
  **Verify on device:** delete the app, reinstall, cold launch; iOS caches
  launch screens aggressively, so restart the device if it looks stale.

## Already done

- [x] Remote Config: all 74 keys published and confirmed remote-sourced
  (July 25, via the DEBUG `remote_tuning_audit` log).
- [x] `firestore.rules` for adoptedOn write-once, letters, activityWeeks
  (deployed July 24; only the moments block awaits the redeploy above).
- [x] RevenueCat client wiring, Apple + Google Sign-In client wiring,
  widgets, notifications, Personal Layer Features 1 through 6.
- [x] App icon: current art accepted for TestFlight (decided July 27, no
  replacement needed).
