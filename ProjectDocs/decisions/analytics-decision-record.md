# Analytics decision record

Decided 2026-08-02 (Aaron), closing the "Decide Firebase Analytics intent" item in
`release-checklist.md` section 2.

## Decision for v1.0: no analytics collection, enforced in config

MochiBuddy 1.0 ships with **zero analytics collection**. The Firebase Analytics SDK
remains linked (it rides along with the Firebase distribution) but is disabled at
both layers that matter:

- `GoogleService-Info.plist` → `IS_ANALYTICS_ENABLED` = `false` (was already set).
- `MochiBuddy/Info.plist` → `FIREBASE_ANALYTICS_COLLECTION_ENABLED` = `false`
  (added with this decision). This is the key Firebase actually honors at runtime;
  it guarantees no automatic event collection and no device-identifier harvesting
  even though the SDK is in the binary.

### What this means for the ASC privacy nutrition label (section 6)

The label does NOT become "no data collected" overall: the app still collects
account identifiers (Firebase Auth email/Apple/Google sign-in) and user content
(tasks, lists, letters, moments synced to Firestore), linked to identity, for app
functionality. What this decision guarantees is that the label needs **no rows with
an "Analytics" purpose** and no third-party-analytics disclosures: no Product
Interaction, Usage Data, or Diagnostics collected for analytics, and no tracking
(`NSPrivacyTracking` is `false` in both privacy manifests).

## Intent for later (roadmap #7, explicitly out of scope for v1.0)

Preference recorded 2026-08-02: **PostHog** is the intended analytics stack when
roadmap #7 comes up, with Firebase Analytics as the fallback only if PostHog proves
unworkable (for example SDK size, iOS support, or pricing at scale). Rationale:
PostHog is product-analytics first (funnels, retention, feature flags, session
context) and self-hostable, and keeping analytics out of the Google stack keeps the
nutrition label and consent story simpler to reason about.

When that work starts, the checklist for whichever SDK wins:

1. Add the SDK and an opt-in/consent posture decision (analytics do not have to be
   opt-out just because Apple allows it).
2. Update both `PrivacyInfo.xcprivacy` files and the ASC nutrition label in the
   same change; they must stay consistent.
3. Revisit `FIREBASE_ANALYTICS_COLLECTION_ENABLED` only if Firebase Analytics is
   the winner; otherwise it stays `false` forever.
4. Crashlytics is a separate call bundled into roadmap #7; deciding PostHog for
   product analytics does not decide crash reporting.
