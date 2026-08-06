# Release checklist — THE final list

Compiled 2026-08-02 from a complete audit: every root and archived doc, a full
sweep of all 304 Swift files for unfinished work, a release-configuration audit
of the project file / plists / entitlements / rules, and the git state.

**The boundary: when every box in sections 1–6 is checked, the build goes up for
submission. Nothing gets added to this list.** Section 7 is explicitly out of
scope for this release; touching it before submission is the side-tracking this
list exists to prevent.

State at compile time: main is 3 commits ahead of origin, tree clean. Code is
feature-complete; the August 1–2 work (fix-roadmap steps 1–8, notifications
review, 14-day yearly trial, trial-ending notices) is all landed and tested.
Suite status: see section 3.

---

## 1. Console / external — the real blockers

- [x] **Deploy `firestore.rules`.** Machine-verified 2026-08-02 via
      `firebase deploy --only firestore:rules`, which reported *"latest version
      of firestore.rules already up to date, skipping upload"* — the CLI
      compared the repo file against the live ruleset and found them identical.
      The Aug 2 `billingNotices` block (`firestore.rules:96`) is live and
      trial-ending notice writes are unblocked. The end-to-end confirmation is
      still the section-4 sandbox check that a `billingNotices` doc lands.
- [x] **Create the composite index:** `tasks` — `listId` ASC, `completedAt`
      DESC. Done 2026-08-02 via `firebase deploy --only firestore:indexes` and
      confirmed present by `firebase firestore:indexes` (which had returned an
      empty set beforehand, so this one really was outstanding). Activates
      ListDetail's scoped done query; large-collection index builds finish
      asynchronously and the code falls back safely in the meantime.

      Firestore is now repo-managed rather than console-manual: `firebase.json`,
      `.firebaserc` (project `mochinut-6ed95`), and `firestore.indexes.json`
      are checked in, so both facts are re-verifiable any time with
      `firebase firestore:indexes` and a rules deploy that no-ops when in sync.
- [x] **Publish the 10 discovery-batch Remote Config keys** (console → Remote
      Config): `suggest_weekday_min` 4 · `suggest_weekday_dates` 3 ·
      `bh_row_min` 5 · `bh_row_dates` 3 · `bh_second_wind_min` 5 ·
      `bh_second_wind_dates` 3 · `effort_weight_tiny` 1.0 ·
      `effort_weight_small` 1.4 · `effort_weight_medium` 2.0 ·
      `effort_weight_large` 3.0.
      Verified 2026-08-02: all 10 keys present in the console. Behavior was
      unchanged either way (shipped defaults match); this was only about the
      pin reading honestly at 84/84.
      **Remaining confirmation (free, folds into any DEBUG launch):** the console
      editor shows draft values, so if these were added but the change was never
      published, clients still fall back to defaults. A DEBUG launch logging
      `remote_tuning_audit all 84 keys remote-sourced` settles it (first launch
      after a publish may warn once, heals on the next). Do this during the
      section-4 sim pass, not as a separate errand.

## 2. Code — small hardening, one sitting

From the full-source sweep (zero TODO/FIXME anywhere; these are the only items):

- [x] **Gate `-mochiLocalMembership` behind `#if DEBUG`**
      (`AppContainer.swift:113`). Done 2026-08-02: the membership-store
      selection is `#if DEBUG`-gated and the whole `LocalMembershipStore`
      class now compiles out of Release (which also gates
      `-mochiSimulateRestorable`, checked inside it). `-mochiStartAtHome`,
      `-mochiStartLapsed`, and `-mochiStartTab` (TabCoordinator) gated in the
      same pass.
- [x] **Replace the `fatalError` in `ObservationEngine.swift:410`** with a safe
      return. Done 2026-08-02: the default branch now returns an empty
      no-evidence `ObservationCandidate` instead of trapping.
- [x] **Add a first-party `PrivacyInfo.xcprivacy`** (app + widget). Done
      2026-08-02: both bundles declare UserDefaults with CA92.1 (same-app) and
      1C8F.1 (App Group — the comfort buffer is shared with the widget), no
      tracking, no collected data types. Synchronized groups pick both files
      up as resources automatically.
- [x] **Decide Firebase Analytics intent.** Decided 2026-08-02: v1.0 ships
      zero analytics collection; `FIREBASE_ANALYTICS_COLLECTION_ENABLED = NO`
      added to `MochiBuddy/Info.plist`. Future intent recorded as PostHog
      first, Firebase fallback (roadmap #7). Full record and nutrition-label
      implications: `ProjectDocs/decisions/analytics-decision-record.md`.
- [x] **Confirm `IPHONEOS_DEPLOYMENT_TARGET = 26.1` is deliberate.** Confirmed
      yes by Aaron 2026-08-02: iOS 26 required, iPhone-only accepted.
- [x] **Unify the widget display name.** Done 2026-08-02: unified on
      "MochiBuddy" — widget target `CFBundleDisplayName` and the widget's
      `configurationDisplayName` both changed from "Mochi" to match the home
      screen.
- [x] **Build a DEBUG-only suggestion fixture seeder.** Done 2026-08-02, suite
      green after (855/0/1). `DevFixtureSeeder.swift` + `DevFixturesSection.swift`
      in `You/DevScheduler/`: seeds 18 evening completions across 6 days on a
      "Seeded fixtures" list (new-time chip) and a 9:00 daily series completed
      ~19:00 across 8 days with one live occurrence due tomorrow (re-time chip
      + badge), both sized to clear every engine gate with margin. Delete
      button removes exactly the seeded docs; re-seeding without deleting is
      blocked. The card's "How to use" sheet carries the full walkthrough the
      section-4 pass follows. Not yet driven in the sim; section 4's pass is
      its first live run.
- [x] *(Optional, same sitting)* Delete dead `PlaceholderArt.swift` (zero call
      sites) and the three stale comments that contradict shipped code
      (`MembershipStore.swift:8`, `JournalBehavior.swift:37`,
      `TreatCatalog.swift:11`). Done 2026-08-02; also scrubbed the
      `PlaceholderArtIcon` mention in `TreatArt.swift`'s header.

## 3. Green suite — the gate on section 2

- [x] **Full suite passes** after the section-2 edits on iPhone 17 Pro /
      iOS 26.1. Verified 2026-08-02 post-edits: **855 passed / 0 failed /
      1 expected skip**, matching the audit baseline exactly. A Release-
      configuration build was also compiled the same day to prove the new
      `#if DEBUG` else-branches (RevenueCat-only membership, dev args
      compiled out) build clean.

## 4. Human QA — the largest genuinely untouched item

No human has run `manual-test-plan.md`. The 800+ unit tests prove the engines;
they say nothing about layout, contrast, or feel. Run on a physical device
(TestFlight build once it exists — items here can overlap section 5).

- [ ] Full top-to-bottom pass of `manual-test-plan.md` (16 sections).
- [ ] The flagged high-value passes within it: five-flavor contrast on Best
      Hours cards · 320pt/SE layout (effort pill, tiles, legend, long titles) ·
      the D1b priority-vs-effort readability call · re-time badge placement ·
      effort-vs-mood feel (one Large ≈ three unrated) · VoiceOver on the new
      surfaces.
- [ ] **Suggested times — prove it fires end-to-end** (added 2026-08-02; the
      engine is unit-tested but the chip has never been observed live, and the
      2026-07-25 sim session could only confirm honest *silence* on thin data).
      Using the section-2 fixture seeder, in a DEBUG build:
      1. Seed the new-time fixture → open a new task in that list → the chip
         appears with time + reason. Cross-check the DevScheduler suggestions
         inspector: every gate (evidence, dates, peak share, runner-up margin)
         reads as passing for the same task.
      2. Accept → the time fills; hand-editing afterwards still works; save.
      3. Reopen a new task → dismiss the chip → confirm it stays gone for that
         trigger, and the re-arm rule (needs a ≥60-min different suggestion).
      4. Seed the re-time fixture → the `clock.arrow.circlepath` badge shows on
         that series' row in Tasks and ListDetail (never Home, never Reminders)
         → opening the editor shows the re-time card with due-time consent copy
         → accepting moves the series' due time going forward.
      5. Negative checks: no chip while lapsed (`-mochiStartLapsed`), no chip
         inside bedtime or under 30-min lead for a today-due task.
      6. Delete the fixtures; confirm the inspector returns to silence.
- [ ] **Trial-ending notices live check** (new since the plan was written):
      sandbox-purchase the yearly trial on device, confirm the 24h/3h notices
      appear in the pending queue (DEBUG inspector) and a `billingNotices` doc
      lands in Firestore.
- [ ] **Eyeball the app icon's light + tinted renderings** on device. Only the
      sesame-dark layer ships; iOS auto-derives the rest, and nobody has looked.
- [ ] Cold-launch screen check on device after a delete + reinstall (iOS caches
      launch screens; restart the device if it looks stale).

## 5. Ship it — archive, TestFlight, testers

- [ ] **Commit the section-2 work, push everything.**
      **Verify:** `git rev-list --count origin/main..main` prints 0 and
      `git status` is clean.
- [ ] **Archive and upload** (Xcode → Product → Archive → Distribute).
      Version 1.0 (1) is right for the first upload; any re-upload bumps build
      to 2 on app AND widget together (they must match).
      **Verify:** build reaches TestFlight "Ready," no Missing Compliance badge.
- [ ] **Add internal testers** in TestFlight (no review, no screenshots needed).
- [ ] **Run the July-27 verify blocks once** — the external setup was reported
      done but never verified: ASC app record bundle ID exact-match · Paid Apps
      agreement "Active" · both subscriptions "Ready to Submit" · RevenueCat
      API key present / product import works · server-notification URL firing
      (sandbox renewal events appear in RevenueCat) · Google provider enabled ·
      sandbox purchase unlocks premium. Each has step-by-step Verify
      instructions in `submission-checklist.md`.

## 6. App Store submission — the last mile

- [ ] **Paste the privacy URL** into ASC → App Information → Privacy Policy URL
      (`https://a-squareddev.github.io/MochiBuddy/privacy/` — already live).
- [ ] **App Store screenshots** (the one real asset still owed).
- [ ] **Subscription review screenshots** for `mochi_2999_1y` and `mochi_399_1m`.
- [ ] **Privacy nutrition label** in ASC, consistent with the Analytics decision
      in section 2.
- [ ] **Listing metadata:** name, subtitle, description, keywords, support URL
      (`.../support/`), category, age rating.
- [ ] **Decide the widget-pose question — explicitly.** `waiting-on-assets.md`
      says the commissioned widget pose set "blocks shipping"; the submission
      checklist ships code-drawn poses. The code-drawn poses are real art and
      pass review. Recommended: ship v1 with code-drawn poses and move the
      commission to section 7. Check this box when the decision is written down,
      whichever way it goes.
- [ ] **Submit for review.**

## 7. Explicitly NOT in this release

Recorded so nothing here sneaks back onto the list. All tracked in their source
docs for after v1.0 ships:

### v1.1 queue (first up after submission)

- [ ] **Editor ghost pill** — the last discovery-batch item, promoted here
      2026-08-02 as the first post-release todo. Design locked (E1–E7, spec in
      `mochi-requirements.md` → The discovery batch → Editor layout; build
      reference `ProjectDocs/build-notes/editor-layout-implementation-guide.md`).
      All view-and-VM work, no engine/model/persistence change. Before building:
      (1) design comp, with the dim treatment checked across all five flavors so
      a ghosted time stays distinguishable from an empty pill; (2) decide
      whether tapping auto-opens the wheel or accepts quietly; (3) decide
      whether re-time also loses its confirmed card.

- [ ] **Re-time discoverability — surface it above the row** (your idea,
      2026-08-02). Today a suggested time change for a recurring task announces
      itself only as the `clock.arrow.circlepath` badge on that series' row
      (`TodoItemRow.swift:149`), inside Tasks or ListDetail. If you aren't
      already looking at the list, nothing tells you Mochi has an idea. Proposal:
      an unread-style dot on the Tasks tab item (`MainTabView.swift`) that
      clears once the row has been seen, with the existing row badge as the
      second step of the trail. Open questions before building: does the dot
      clear on viewing the row or on acting on the card (accept/dismiss) · does
      it cover new-time chips too or re-time only · does it survive relaunch
      (needs a "seen" flag persisted next to the suggestion trigger) · does it
      risk reading as a notification-count badge, which Mochi otherwise never
      uses. Deliberately v1.1: the row badge already ships and works, so this is
      polish on discovery, not a missing feature.

### The rest of the parking lot

- Waking-Mochi onboarding beat (exploratory, needs comp + two poses)
- Rive mascot rig, commissioned widget pose set, notification imagery, sounds
- Analytics/Crashlytics (roadmap #7) · anon-account sweeper (deferred by you,
  roadmap step 9) · `linkWithCredential` polish beyond what step 3 shipped
- Localization, widget memory-ceiling work (roadmap #8)
- LLC legal identity + mochibuddy.app custom domain (post-formation/purchase)
- Splash "Try again" offline retry path (Phase 5 decision) · anniversary
  backfill · snapshot listeners · coin diminishing-returns curve · Effort tile
  phrasing confirm
- Known-and-accepted notification edges: timezone change while dead (#4,
  inherent to local notifications), DEBUG-only invariant cosmetic (#7),
  `lastFloorDay` dead state (#8)

## Doc hygiene (non-blocking, anytime)

- [ ] Delete `TEMPORARY-todo.md` — this file supersedes it (it asked for
      deletion itself once the push was underway).
- [ ] Fold-then-archive `done-tab-implementation-guide.md`,
      `mochi-notifications.md`, `firestore-caching-investigation.md`,
      `mochi-fix-roadmap.md` per the ProjectDocs convention; update the
      requirements changelog past v0.8 (the Aug 1–2 work isn't in it), and
      reconcile the stale "Outstanding external setup" checkboxes in
      `mochi-requirements.md` with `submission-checklist.md`.
- [ ] Delete this file's sections 1–6 victory lap: when everything above is
      checked, archive this doc too.
