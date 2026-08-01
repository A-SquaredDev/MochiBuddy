# Calendar Access · Decision Record

> **Status: TABLED. Not built, not cancelled.** Decided 2026-07-25 in the
> post-Personal-Layer discovery session.
> This was Feature 4 of a five-item batch. The batch is now four items:
> 1. Best Hours (`best-hours-implementation-guide.md`) →
> 2. Suggestions (`suggestions-implementation-guide.md`) →
> 3. Effort (`effort-implementation-guide.md`) → 4. Editor layout.
>
> **Nothing in the other three forecloses this.** Reviving it is additive.
> Read §5 before reopening.
>
> **Naming warning.** "Feature 4" is overloaded in this repo. Throughout
> `mochi-requirements.md`, `feature2-implementation-guide.md` and
> `feature6-implementation-guide.md` it means the **shipped v0.7 Personal Layer
> Feature 4, Mochi's observations** (`Observations/`). Those references are live
> and correct. This document is about the *discovery batch's* item 4, which was
> the calendar and is now tabled; the batch's item 4 is henceforth Editor layout.
> Refer to this one as "the calendar layer", never by number.

---

## 1. What was proposed

EventKit calendar access so Mochi could take existing commitments into account
when suggesting a time. Explicitly **not** a scheduler: the original framing, in
the user's words, was *"It shouldn't be a scheduler, it should just apply a
suggested time."* Concretized during discovery as **the calendar is a mask, never
a source** - completion history proposes a time, the calendar may veto it and
shift to the nearest free edge, and the calendar never proposes on its own.

Visual form: state 1e of the Best Hours comp - a hatched overlay of recurring
commitments on the histogram, a "Calendar on" chip in the header, and the
per-weekday right-hand label switching from a typical time to "Free 10:30a" /
"All clear".

---

## 2. The objection that opened the question

Raised by the user: *"if we see they have an event from 6-9 we would suggest a
different time. But that time might be allotted for studying, which is also what
the task is."*

A calendar event does not mean **unavailable**. It means **spoken for**, and
sometimes what it is spoken for is the task itself. Avoiding it is then exactly
backwards.

**This objection has a clean fix, and the fix is worth keeping if the feature ever
returns:** history outranks the calendar, always. The calendar may only veto a
time the completion history is *neutral* about; it can never overrule an endorsed
peak. History is evidence of what the user actually did at that hour, a calendar
entry is evidence of what they intended, and when the two disagree the behavior
wins. Under that rule the 6-9pm study block is never treated as a conflict,
because 6-9pm is precisely where the history is strongest.

So the objection alone did not cut the feature. What cut it was §3.

---

## 3. Why it was cut: every use is redundant, too narrow, or ruled out

Four candidate uses. None survives.

| Use | Verdict |
|---|---|
| **Recurring commitments** (class blocks, standing meetings) - the exact scope state 1e proposed | **Redundant with completion history by construction.** A standing commitment is already a hole in the completion distribution: if the user has class every MWF morning, they have never completed a task then, so the distribution already avoids mornings without knowing why. The calendar supplies a *name* for the hole, not a fact. Explanatory value only; it changes no suggestion. |
| **One-off events** | **Genuinely unknowable from history, but structurally hard to reach.** The suggestion engine produces a *minute of day*, not a date (`SuggestionEngine.evaluateReTime`, `:106-156`, compares a scheduled minute against the weighted peak of `completedLocalMinute`). A one-off conflict exists only on a specific date, so the check can fire only after the user has already picked one, on dated tasks, on dates that happen to carry a non-recurring event. It is also the category where the §2 objection bites hardest, since a one-off is exactly the event whose purpose Mochi cannot infer. |
| **Cold start** (day one, no history) | **Violates the app's own doctrine.** This is the strongest case: on day one the calendar is the only signal that exists, and the suggestion engine's evidence floors keep it silent for weeks. But "your evening has no meeting in it" is not insight about the user, it is the absence of a meeting. Shipping it as a suggestion is the weak assertion that honest-silence was built to refuse, and it would be the one place in the app where Mochi speaks without evidence. |
| **Block finding** (Feature 3 says a task takes 2h; where are 2 free hours?) | **The one genuinely irreplaceable use, and the one explicitly ruled out.** Completion history knows when the user *finishes* things, never when they are *free*, so this is structurally unanswerable without a calendar. But finding a contiguous block is scheduling, and the founding constraint on this feature was that it must not be a scheduler. |

**The decisive line:** the calendar's only irreplaceable capability is the one the
feature was forbidden to have. Everything left over is redundant with history or
too narrow to justify the cost in §4.

---

## 4. Cost avoided

- A second EventKit permission (`NSCalendarsUsageDescription`) on top of the
  existing Reminders one, plus its denied and lapsed states.
- An onboarding screen, mirroring `Onboarding/AppleReminders/`.
- A foreground re-check for existing users who onboarded before it shipped.
- An App Store privacy disclosure for calendar data.
- A permanent third-party data dependency to keep fresh, and a new failure mode
  where a stale or partially-synced calendar produces a wrong suggestion.
- Chart work: the hatch layer, the header chip, and the free-time label variant.

---

## 5. If it is revived, start here

**The plumbing is already a solved problem.** `Permissions/RemindersGateway.swift`
is a working template for exactly this shape:

- a protocol with an access enum (`RemindersAccess`: `notDetermined` / `granted` /
  `denied`) and an async permission request;
- an **EventKit-free snapshot type** with a hard boundary, stated in the file
  header comment: *"EKReminder and EKCalendar never leave this file."* A calendar
  version returns something like `struct BusyBlock { start, end, isRecurring }`
  and nothing more;
- injected through `AppContainer`, so it is faked in tests;
- an onboarding screen (`Onboarding/AppleReminders/`) and a settings screen
  (`You/AppleReminders/`) already demonstrating the full lifecycle.

**Carry forward these two design conclusions**, both reached before the cut and
both still correct:

1. **History outranks the calendar, always** (§2). The calendar speaks only where
   history is silent.
2. **Recurring-only was the wrong scope** (§3). It is the redundant half. If the
   feature returns, one-offs are the half worth having.

**Two triggers should reopen this:**

- **Mochi starts suggesting a date, not only a time.** The one-off case becomes
  load-bearing the moment a suggestion has a date attached, because that is when a
  specific-day conflict is knowable and actionable.
- **Block finding is reconsidered.** If the product ever decides Mochi should place
  work rather than only time it, the calendar stops being optional and becomes
  mandatory. Feature 3's D11 already fixes a block length ("2h+" means exactly 120
  minutes), so the input side is ready.

---

## 6. The cheap substitute, if the explanatory value is missed

The only non-redundant thing the recurring layer offered was **naming** a hole the
history already knew about ("that gap is CHEM 201"). That does not need EventKit.
A user who wants Mochi to know they are in class 9-12 MWF can express it as a
recurring task or a quiet-hours setting typed once. Same named hole, no permission,
no sync dependency, no privacy disclosure.

---

## 7. Consequent changes to other docs

- `best-hours-implementation-guide.md`: the "Deferred to Feature 4" block now
  points here. **C2 (minimum hatch width) is void** while this is tabled - it
  existed only to keep a 30-minute hatch from rendering as a 5px smudge. State 1e
  of the comp stays in the design project as a record of the explored direction,
  and must not be built.
- `effort-implementation-guide.md`: **D11 stands unchanged.** "2h+" resolving to
  120 minutes is worth keeping regardless, since it bounds an otherwise unbounded
  bucket. Its stated calendar rationale is now forward-looking rather than
  immediate.
- All three guides: batch order updated from five items to four.
