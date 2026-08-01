# Editor Layout Implementation Guide · Suggested-time presentation

> **Status: DESIGN LOCKED, NOT BUILT.** Decisions settled 2026-07-25 in a discovery session.
> No design comp yet.
> Fourth and final item in the post-Personal-Layer discovery batch. Batch order:
> 1. Best Hours (`best-hours-implementation-guide.md`) →
> 2. Suggestions (`suggestions-implementation-guide.md`) →
> 3. Effort (`effort-implementation-guide.md`) → **4. Editor layout.**
> (Calendar was the old item 4 and is now tabled: `calendar-decision-record.md`.)
>
> This item shrank during discovery. It was sequenced last as the container for
> Features 2 and 3, but Feature 2 settled on a task-row badge (no editor change)
> and Feature 3 settled on a zero-row-cost pill (Feature 3 D8). What remains is one
> question: how the editor presents a suggested time.

---

## 1. The reframe that shrank this feature

**"Suggestions" and "best hours" are not two surfaces. They are one distribution.**

The editor's suggested-time chip (shipped v0.7 Feature 5) has three scope tiers
(`SuggestionCopy.reason`). When a new task has no series or list history, the chip
falls to **global scope** and says *"You usually finish things in the evening."*
That line **is** best hours, made actionable. Best Hours the Stats card
(`best-hours-implementation-guide.md`) is the identical `CompletedTaskStat`
distribution drawn as a chart. Best Hours **D10 already forces the chart to reuse
the suggestion engine's ±90 window** so the card can never contradict the chip.

Consequence: **nothing about "best hours" needs an editor surface.** A mini-chart
or second hint in the editor would duplicate the chip and risk the two disagreeing.
The chart lives in Stats; the actionable form lives as the chip. This doc is only
about the chip.

---

## 2. What this batch actually changes in the editor

Only two things, and one is owned elsewhere:

1. The chip's copy pool gains a **weekday-scoped tier** (Feature 2A, owned by
   `suggestions-implementation-guide.md`) - same chip, a new provenance line such
   as *"on Tuesdays you usually finish in the evening."*
2. The **effort pill** lands trailing the Priority eyebrow row (Feature 3 D8, owned
   by `effort-implementation-guide.md`). No new block, no reordering.

Everything below is the one decision this doc owns: the shape of the new-time chip.

---

## 3. Decisions locked

| # | Decision | Rationale |
|---|---|---|
| E1 | **New-time suggestion renders as a GHOST inside the time pill**, not as a card below it. The suggested time shows dimmed with a clock glyph while the time is unset. | A new task has no row to badge, so all new-time discovery happens inside the editor. The shipped card disappears the moment the user opens the time wheel, so it is easy to miss. The ghost is visible the instant a date is set and sits exactly where the value will go. |
| E2 | **Re-time keeps the explanatory card** (`suggestionRow`, `TaskEditorView.swift:288-334`), unchanged. | A re-time proposal is a *different* time than the one already in the slot, so there is nothing empty to ghost into. The split is forced by the data, not a preference. |
| E3 | **One tap on the ghost accepts AND opens the wheel, seeded at the suggested minute.** | Fuses the shipped `.timeTapped` (open picker) and `.suggestionTapped` (set time) into one gesture. Gives accept (tap, then tap away), replace (tap, then spin), and no-time (the clear-time x at `:248-259`) with no hidden gesture. |
| E4 | **No time is ever committed without the user tapping the time field.** The ghost is a display state; `draft.hasTime` stays false until the tap. | Kills the false-acceptance risk that ruled out full prefill. The shipped outcome classifier (accepted / adjusted / matched-within-30 / dismissed / ignored, classified at save in `TaskEditorViewModel`) keeps working: never-tapped ghost = ignored, tapped = accepted, tapped-then-spun-past-30 = adjusted. |
| E5 | **The ghost carries a dismiss affordance** wired to `.suggestionDismissed`, occupying the slot the clear-time x uses (free while `!hasTime`). | Preserves the `SuggestionLedger` trigger-keyed dismissal and its 60-minute re-arm (`suggestions-implementation-guide.md` / Feature 5). Dismissing returns the pill to "Set time". |
| E6 | **In ghost mode the caption under the pill is the reason line only**, not the "Nori suggests 9:20 PM" label. | The time is already visible in the pill, so repeating it in the label is redundant. The muted one-liner (`SuggestionCopy.reason`, incl. the Feature 2A weekday variant) carries the provenance. |
| E7 | **For new-time, the solid pill IS the confirmed state; drop the confirmed card.** Re-time's confirmed behavior is unchanged for now. | After acceptance the accepted time shows solid in the pill, so the shipped quiet-confirmed card (`suggestionChipState` `.confirmed` case, `TaskEditorViewModel.swift:452-462`) is redundant for new-time. Leaving re-time alone keeps the change small. |

### Explicitly not built

- No chart, sparkline, or "best hours" hint in the editor (see §1).
- No change to when the chip *qualifies* - that is the engine's job (Feature 5
  gates plus Feature 2A's fallback). This doc changes only how an already-offered
  new-time proposal is drawn.
- No "Details" disclosure to collapse Priority / List / Repeat / Notes. It was the
  original point of sequencing this last, but with Features 2 and 3 no longer adding
  rows, the seven-block sheet is not growing, and the app has no disclosure
  component to build on (only two hand-rolled ones in dev screens). Revisit only if
  a later feature actually adds an eighth always-visible block.

---

## 4. The gesture, precisely

State while a new-time proposal is offered and `draft.hasTime == false`:

```
  DATE                TIME
  ┌─────────┐        ┌───────────┐   x
  │ Jul 26  │        │ ◷ 9:20 PM │  (dim)   ← dismiss
  └─────────┘        └───────────┘
                       you usually finish things in the evening
```

- **Tap the pill** → `draft.hasTime = true` at `proposal.displayedMinute`,
  `activePicker = .time` seeded there, pill goes solid. (Extend `.suggestionTapped`
  to also open the picker, or route the ghost pill's tap through a combined intent.)
- **Spin the wheel** → replaces the minute; classifier records "adjusted" at save if
  the final minute is >30 from the displayed one, "matched" otherwise.
- **Tap the x** → `.suggestionDismissed`; ghost clears, pill reads "Set time".
- **Save without ever tapping** → no time set (date-only task); classifier records
  "ignored". The ghost committed nothing.

After acceptance the pill shows the solid time with the standard clear-time x
(`:248-259`), which now doubles as "remove the accepted suggestion".

---

## 5. What exists and is reused

| Rail | Where | Note |
|---|---|---|
| Time pill | `valuePill(icon:text:active:onTap:)` (`TaskEditorView.swift:245`, def `:345-367`) | gains a third visual state: ghost (dim text + clock glyph, `active:false` but non-empty) |
| Time wheel | inline `.wheel` DatePicker gated on `activePicker == .time` (`:261-273`) | seeded at `displayedMinute` instead of its current default when accepting a ghost |
| Suggestion state machine | `suggestionChipState()` (`TaskEditorViewModel.swift:443-476`), `offeredPreconditionsHold` (`:478-494`) | newTime precondition is already `dueAt != nil && !hasTime` (`:482-484`) - exactly the ghost's visibility condition. No gate change |
| Chip model | `TaskEditorBehavior.SuggestionChip` (`TaskEditorBehavior.swift:40-46`) | add a `kind` (newTime / reTime) or `isGhost` flag so the view routes newTime→ghost, reTime→card |
| Accept / dismiss intents | `.suggestionTapped` / `.suggestionDismissed` (`TaskEditorView.swift:293`, `:318`) | reused; `.suggestionTapped` extended to also open the picker (E3) |
| Reason copy incl. weekday tier | `SuggestionCopy.reason` (`SuggestionCopy.swift:38-62`) | the ghost caption; weekday variant arrives with Feature 2A |
| Outcome classifier | at save in `TaskEditorViewModel` (Feature 5) | unchanged; E4 keeps its inputs honest |
| Effort pill | Feature 3 D8, trailing the Priority eyebrow (`fieldBlock` variant) | adjacent block, no interaction with the chip |

**Must be built:** the ghost visual state on the time pill, the combined
accept-and-open gesture, the newTime/reTime routing flag on `SuggestionChip`, the
reason-only caption placement, the dismiss affordance in the ghost, and the
drop of the new-time confirmed card. All view-and-VM; no engine, model, or
persistence change.

---

## 6. Gotchas

- **iOS time formatting uses U+202F** (narrow no-break space) before AM/PM. The
  ghost renders `SuggestionCopy.timeText`; any test pins it with `\u{202F}`.
- **Editor-VM suggestion tests anchor to the real clock** (`liveDay`), not
  `Dates.now`, with due dates tomorrow so the lead-time guard cannot race. Carried
  from Feature 5.
- **The wheel's `.clipped()` at height 120** (`:270`) must still contain the seeded
  picker; seeding changes the value, not the frame.
- **Do not let the ghost animate as a layout jump.** The whenBlock already animates
  on `viewModel.suggestionChip` (`:282`); the ghost is a pill state change, so it
  should cross-fade in place, not push the pill down like the card did.

---

## 7. Open items

- [ ] Exact dim treatment for the ghost that reads as "suggested, not set" in all
      five flavors, and is distinguishable from the disabled/empty pill. Contrast
      check like Best Hours C7.
- [ ] Whether tapping the ghost should auto-open the wheel (E3 as written) or accept
      quietly and open only on a second tap. E3 favors auto-open for immediate
      adjustability; revisit if it feels busy in the hand.
- [ ] Whether re-time should also lose its confirmed card for symmetry (E7 leaves it
      for now).
- [ ] Design comp. None exists; the ghost pill and the reason caption want a pass in
      the Claude Design project alongside the Best Hours cards and the Feature 2
      row badge.
