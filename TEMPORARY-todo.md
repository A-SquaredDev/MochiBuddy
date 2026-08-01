# TEMPORARY · consolidated to-do

> **This is a snapshot, not a living doc.** Written 2026-07-30 from a sweep of
> `mochi-requirements.md`, `submission-checklist.md`, `waiting-on-assets.md`, and
> `manual-test-plan.md`. It will drift the moment any of those change. **Delete it**
> once the TestFlight push is done rather than maintaining a sixth root doc; the four
> sources above are authoritative and each item below names its home.

**State at time of writing:** suite green, **755 passed / 0 failed / 1 skipped** (the
gated icon-export harness), iPhone 17 Pro · iOS 26.1. Code is feature-complete through
the v0.8 discovery batch except the editor ghost pill.

---

## 1. Blocking a TestFlight build

Three items. Nothing else stands between the current tree and internal testers.

- [ ] **Commit and push.** Branch `mochi-thriving-animation` has 3 unpushed commits;
      the tree also carries an uncommitted `RemoteTuning.swift` comment edit and the
      whole v0.8 doc reorg. Decide whether the branch merges to `main` first.
      **Verify:** `git rev-list --count origin/main..HEAD` prints `0` and `git status`
      is clean before archiving.
- [ ] **Archive and upload from Xcode** (Product → Archive → Distribute). Automatic
      signing already covers app + widget + App Group + time-sensitive entitlements.
      Version 1.0 (1) is fine for a first upload.
      **Verify:** Organizer lists the archive; ASC → TestFlight shows the build go from
      Processing to ready, with no Missing Compliance badge.
- [ ] **Add internal testers.** No Beta App Review, no privacy policy URL, no
      screenshots required for internal testing.

*Source: `submission-checklist.md` → Blocking.*

## 2. Console work that does NOT block a build

- [ ] **Publish the 10 discovery-batch Remote Config keys.** Shipped defaults apply
      until then, so behavior is unchanged and a build is safe without them.
      `suggest_weekday_min` 4 · `suggest_weekday_dates` 3 · `bh_row_min` 5 ·
      `bh_row_dates` 3 · `bh_second_wind_min` 5 · `bh_second_wind_dates` 3 ·
      `effort_weight_tiny` 1.0 · `effort_weight_small` 1.4 · `effort_weight_medium` 2.0 ·
      `effort_weight_large` 3.0
      **Verify:** run the suite (`consoleKeysMatch` pins all 84), then a DEBUG build
      logging `remote_tuning_audit all 84 keys remote-sourced`. Note the audit is one
      launch behind a publish, so a first-launch warning that heals is expected.

*Source: `mochi-requirements.md` → Implementation status → Outstanding external setup.*

## 3. Before external testers / App Review

- [ ] Paste the privacy URL into **ASC → App Information → Privacy Policy URL**. The
      pages are live on GitHub Pages already; only the ASC field is missing.
- [ ] **Subscription review screenshots** for `mochi_2999_1y` and `mochi_399_1m`.
- [ ] **App Store screenshots.**
- [ ] **LLC legal identity**, when the entity exists: name it in the privacy policy's
      contact section, swap in a business email on both legal pages, update the ASC
      seller/company name.
- [ ] If `mochibuddy.app` is purchased: add it as the Pages custom domain (same
      `/privacy/` and `/support/` paths), then update `MochiLinks.swift` and ASC.

*Source: `submission-checklist.md` → Later.*

## 4. Unbuilt product work

- [ ] **Editor ghost pill** — the last discovery-batch item. Design is fully locked
      (E1–E7); it is all view-and-VM work with no engine, model, or persistence change.
      Needs a design comp first. Open sub-questions: the exact dim treatment across all
      five flavors, whether tapping auto-opens the wheel or accepts quietly, and whether
      re-time should also lose its confirmed card.
      *Spec: `mochi-requirements.md` → The discovery batch → Editor layout. Build
      reference (code-line survey, gotchas):
      `ProjectDocs/build-notes/editor-layout-implementation-guide.md`.*
- [ ] **Waking-Mochi onboarding beat** — exploratory. Needs a comp, two poses that do
      not exist, and answers to the six open questions in the spec (returning-user
      gating, the write-once `adoptedOn` stamp site, art dependency, skippability,
      Reduce Motion / VoiceOver, scripted vs. live mood).
      *Spec: `mochi-requirements.md` → Onboarding → Exploring: the waking-Mochi
      adoption beat.*

## 5. Art and design deliverables

- [ ] **Resolve the contradiction first.** `waiting-on-assets.md` marks the widget
      static pose set as *"blocks shipping, per requirements"*, while
      `submission-checklist.md` treats the app as ready to upload with code-drawn poses
      and accepted placeholder icon art. Best read: the pose set blocks the **App
      Store**, not TestFlight. Decide explicitly rather than finding out at review.
- [ ] **Widget static pose set:** 6 mood idles + asleep + resting, exported per theme,
      every pose legible as a monochrome silhouette for the lock screen.
- [ ] **Mascot animation commission (Rive rig):** character rig, ~6 mood idle loops,
      reaction animations (pet, complete, fall-asleep, wake-up, treat), per-state
      ambient sound.
- [ ] **Groggy pose + adoption-happy beat** for the waking-Mochi sequence, plus a static
      equivalent for Reduce Motion.
- [ ] **Notification imagery** (expressive faces, intensity-capped) — gated on the pose
      commission.
- [ ] **Comps:** editor ghost pill, waking-Mochi sequence.
- [ ] **File cleanup:** delete the superseded food-metaphor states (1a–1c) from
      `Task Size Control.dc.html` in the Design project.

*Source: `waiting-on-assets.md`.*

## 6. Known open bugs

**All six fixed 2026-07-30** — investigated, confirmed real, fixed, and pinned by new
tests (suite: 768 passed / 0 failed / 1 expected skip). Details and test names live in
`mochi-requirements.md` → Implementation status → Known open bugs ("Fixed 2026-07-30").

- [x] Widget-drained completions: tap instant now queued and stamped into `completedAt`.
- [x] Drain/refresh race: drain memoized + awaited by Home's refresh; Home also
      refreshes on foreground.
- [x] Entitlement horizon: `MembershipStatus` carries `willRenew`; the cap only applies
      to a real cancellation.
- [x] Lapsed streak: zeroed on Home's first open after a genuinely missed day (vacation
      and membership-lapse freezes untouched).
- [x] `EKEventStoreChanged`: wired as `.remindersChange`; reminders list detail and
      Tasks re-fetch per appearance/foreground. (The mood-engine union of native +
      Apple tasks is still roadmap, not a bug.)
- [x] `AccentColor.colorset`: filled (ube light / sesame lavender dark).

*Source: `mochi-requirements.md` → Implementation status → Known open bugs and
follow-ups.*

## 7. Human QA — the largest untouched item

**No human has run the manual test plan.** The discovery batch shipped with unit
coverage only. 755 passing tests say the engines are correct; they say nothing about
layout, contrast, or feel. Highest-value passes:

- [ ] **Five-flavor contrast pass** on the Best Hours cards, especially the IN WINDOW
      value and any tinted text on the inner card surface outside Black Sesame.
- [ ] **320pt (SE-class) layout pass:** effort pill must not drop to its own row; Best
      Hours tiles must not wrap; legend stays on one line; a badged long-title row
      truncates without clipping.
- [ ] **The D1b judgment call:** with priority "Med" AND effort "Medium" on one row,
      does it read as two named questions or as a duplicate? This one genuinely needs
      eyes.
- [ ] **Re-time badge on device:** appears on Tasks and ListDetail, never on Home, never
      on a Reminders row; distinct from the due-state clock when both show.
- [ ] **Effort vs. mood:** one Large task versus three unrated tasks should lift Mochi
      comparably, with coins identical either way.
- [ ] **VoiceOver** across the new surfaces (histogram summary, Day by day rows, day
      pill, effort pill).
- [ ] Full top-to-bottom pass of the remaining 14 sections.

*Source: `manual-test-plan.md`.*

## 8. Roadmap items still open

- [ ] **#5 `linkWithCredential` collision** — understood, needs a handler spec: catch
      `credential-already-in-use` → `signInWithCredential` into the existing account
      (real history always wins) → optionally migrate this session's task → delete the
      orphaned anon user and its Firestore subtree. Also persist Apple's name/email on
      first authorization, since it is given exactly once.
- [ ] **#7 Analytics / instrumentation** — Firebase Analytics + Crashlytics +
      RevenueCat's subscription funnel. The must-have metric is the **daily mood-state
      distribution across users**, the single readout of whether the product philosophy
      is working.
- [ ] **#8 Small pile** — widget memory ceiling, localization (String Catalogs from day
      one, English-only v1), task-content privacy (never log titles).

*Source: `mochi-requirements.md` → Remaining agenda / roadmap.*

## 9. Product confirms that need real-world time

- [ ] **Effort Stats tile:** keep the time-based total ("~3h") or fall back to an
      effort-count subtitle ("mostly Small this month") if a rough hour total feels too
      clock-like beside a clockless picker?
- [ ] **Coin diminishing-returns curve** (open question #2, unresolved since v0.2). The
      `dailyCoinsEarned` / `dailyCoinsDate` fields are reserved for it; flat
      `coins_per_task` until decided.
- [ ] **Nothing surfaces effort in letters or observations yet** — deliberate, revisit
      once there is real data. "You took on three Large tasks this week" is the obvious
      future consumer.
