# TestFlight submission checklist

Status as of July 25, 2026. Code is feature-complete (v0.7 Personal Layer
shipped, full suite green); everything below is the path from here to
testers, ordered by when it blocks. Companion doc: the "Outstanding
external setup" section in `mochi-requirements.md`.

## Code side (one item)

- [ ] **Add `ITSAppUsesNonExemptEncryption` = `NO`** to `MochiBuddy/Info.plist`.
  The app uses only standard HTTPS, which is exempt. Without the key every
  uploaded build sits in "Missing Compliance" until the export questionnaire
  is answered by hand in App Store Connect.

## Blocking: before a build reaches internal testers

- [ ] **Deploy `firestore.rules`** (console → Firestore → Rules, or
  `firebase deploy --only firestore:rules`). The Feature 6 moments block is
  in the repo but not deployed; until then Journal moment creates are
  server-rejected (cache holds, synthesis keeps the Journal non-empty).
  This is the last remaining Firebase console item.
- [ ] **Create the app record in App Store Connect** for
  `com.aaronmckain.MochiBuddy` (name, primary language, SKU).
- [ ] **Paid Apps agreement + banking/tax in App Store Connect.** Without it
  the subscription products cannot load in TestFlight builds; the paywall
  shows hardcoded fallback prices and purchases fail.
- [ ] **Create the two subscriptions in ASC** (`mochi_2999_1y`,
  `mochi_399_1m`) in a subscription group, at least to "Ready to Submit",
  so TestFlight builds can fetch them.
- [ ] **Push main to origin** (the branch runs well ahead of the remote;
  archive from a pushed commit).
- [ ] **Archive and upload from Xcode** (Product → Archive → Distribute).
  Automatic signing already handles app + widget + App Group +
  time-sensitive entitlements on device. Version 1.0 (1) is fine for a
  first upload.
- [ ] **Add internal testers in TestFlight.** Internal testing needs no
  Beta App Review, no privacy policy URL, no screenshots.

## Soon after: correctness during testing

- [ ] **RevenueCat: upload the App Store Connect API key** (RevenueCat
  dashboard → project settings).
- [ ] **App Store server notification URL** from RevenueCat pasted into ASC
  so renewal/cancellation events reach RevenueCat.
- [ ] **Firebase Authentication: enable the Google provider** (console →
  Authentication → Sign-in method). Google Sign-In is fully wired
  client-side and fails until then.
- [ ] **Purchase testing on a physical device** with a Sandbox Apple
  Account (simulator StoreKit is unreliable without a StoreKit config
  file).

## Later: external testers / App Review

- [ ] **Legal URLs are placeholders** (`You/MochiLinks.swift`): privacy
  policy and support point at mochibuddy.app, which does not exist yet;
  EULA uses Apple's standard agreement. External-tester Beta App Review
  needs a real privacy policy URL.
- [ ] **Subscription review screenshots** for both products in ASC.
- [ ] **RevenueCat customer deletion on account delete** needs a server or
  Cloud Function holding the secret key; the client flow erases Firestore
  and Auth but cannot delete the RevenueCat customer.
- [ ] **Real app icon art + themed launch screen.** Current icons are
  placeholder exports from `MochiPetView`; the launch screen is the
  auto-generated blank one. Both acceptable for TestFlight.

## Already done

- [x] Remote Config: all 74 keys published and confirmed remote-sourced
  (July 25, via the DEBUG `remote_tuning_audit` log).
- [x] `firestore.rules` for adoptedOn write-once, letters, activityWeeks
  (deployed July 24; only the moments block awaits the redeploy above).
- [x] RevenueCat client wiring, Apple + Google Sign-In client wiring,
  widgets, notifications, Personal Layer Features 1 through 6.
