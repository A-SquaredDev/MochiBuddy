# Effort Implementation Guide · Effort size

> **Status: DEV READY, comp approved.** All decisions settled 2026-07-25/26. The
> EFFORT pill/menu comp was built and signed off 2026-07-26 (one file-cleanup step
> pending, see §10). No open design questions remain.
> **Not blocked on anything.** D8 places the control without touching the editor's
> block count, so this ships independently of the editor rework.
> Third item in the post-Personal-Layer discovery batch. Batch order:
> 1. Best Hours (`best-hours-implementation-guide.md`) →
> 2. Suggestions (`suggestions-implementation-guide.md`) → **3. Effort** →
> 4. Editor layout.
> (Calendar was the old item 4 and is now tabled: `calendar-decision-record.md`.)

---

## 1. Scope in one paragraph

An **optional effort rating** on a task, labeled "Effort" and chosen from four
magnitude levels (**Tiny · Small · Medium · Large**) rather than a difficulty or
points scale, and without ever showing the user a clock time. Each level maps
internally to a nominal duration, which weights `MoodEngine` momentum so that one big
task lifts Mochi about as much as several small ones, and gives Stats a genuinely new
number that a completion count cannot express. **The coin economy stays flat.**

The feature stands entirely on its own. It was originally also justified as the
input a calendar layer would need for block finding; that layer is now tabled
(`calendar-decision-record.md`), which removes a dependency without removing any
reason to build this.

**Note on framing.** The path here was iterative: difficulty scale → duration
(answerable, calendar-usable) → hide the clock, show qualitative labels → a food
metaphor that tested as unclear ("what am I estimating?") → the final "Effort" label
with Tiny/Small/Medium/Large. The end state satisfies every pressure: the stored
value is nominal minutes (D6, momentum curve unchanged, §4), the visible control
names its dimension ("Effort") and shows no clock (D1), and the abstract scale is
disambiguated from Priority by an explicit label and a distinct shape (D1b).

---

## 2. The problem, stated precisely

`MoodEngine` already weights `TaskPriority` at 1 / 1.5 / 2 (`weight(_:)`,
`MoodEngine.swift:80-86`), but applies it **only to overdue incomplete tasks**
(`:53`), i.e. only on the stress side. On the credit side, momentum is an
unweighted count:

```
momentum = momentumMax * (1 - exp(-completionsLast24h / momentumSaturation))
           momentumMax = 42, momentumSaturation = 2.5   (MoodEngine.swift:26-27)
```

`completionsLast24h` is a raw `Int` (`MoodEngine.swift:38`), fed from
`HomeViewModel.swift:321`. Consequently:

| Today | Momentum earned |
|---|---|
| One task of any size | 33% of max |
| Three trivial tasks | 70% of max |

That gap is the entire feature.

---

## 3. Decisions locked

| # | Decision | Rationale |
|---|---|---|
| D1 | **The control is labeled "Effort" and offers four magnitude labels: Tiny / Small / Medium / Large. No clock times in the picker.** | Settled after three comp iterations. Two earlier framings failed a real legibility test: explicit durations felt like a rigid timebox (user rejected), and a food metaphor (Nibble/Snack/Meal/Feast) read as "a random quirky thing" because it hid the dimension being estimated. "Effort" names that dimension outright ("how much effort is this"), which is the question the user could actually answer. See D1b for why the Priority-collision risk this reintroduces is acceptable now. |
| D1a | **Each label maps to a nominal duration; the stored value is minutes (`estimatedMinutes: Int?`).** Tiny 15 · Small 30 · Medium 60 · Large 120. | Momentum and the Stats total operate on minutes, so storing minutes keeps D6 a one-line stat mapping and keeps the math independent of label wording. Only four values are ever written, so minutes→label for display is an exact lookup. The minutes are an internal nominal, never shown to the user (D1). |
| D1b | **The abstract scale is acceptable next to Priority ONLY because two guards hold: (1) an explicit "EFFORT" eyebrow label beside "PRIORITY", and (2) a different control shape (a pill + menu, never a second chip ladder).** | An UNLABELED difficulty scale was the original rejection reason, not abstraction itself. Labeled and differently-shaped, the two read as two named questions. Watch item: "Med" (priority) and "Medium" (effort) can both appear on the row; tolerable under different labels and shapes, revisit if it reads as a duplicate. |
| D2 | **Optional. Empty by default.** | Users who ignore it pay nothing. `TaskDraft` gets `= nil` inline, joining `hasTime`/`priority`/`seriesId` as the only defaulted fields (`TaskItem.swift:119-130`). |
| D3 | **Weights by level: unset 1.0 · Tiny 1.0 · Small 1.4 · Medium 2.0 · Large 3.0.** All Remote Config tunable. | See §4. Derived from the stated intent that one big task should be worth about three small ones. |
| D4 | **Unset is never penalized.** An unsized task keeps exactly today's weight (1.0). | Otherwise labeling a task "Tiny" costs momentum versus leaving it blank, and nobody would honestly size a small task. Note this makes unset and Tiny identical in weight, which is intended: sizing a small task is a no-op on mood, so honesty is free. |
| D5 | **Affects momentum and Stats. Coins stay flat.** | Coins buy treats; a currency with a self-declared multiplier is the most gameable surface in the app. `RewardsStore` already rejected this in a comment (`:5-6`, "priority scaling would invite mislabeling"). |
| D6 | **`CompletedTaskStat.estimatedMinutes: Int?` is a READ-path change only.** One line in the mapping at `TaskRepository.swift:381-392`, exactly like `rescheduleCount: data["rescheduleCount"] as? Int` at `:389`. | `CompletedTaskStat` is never written. It is constructed only inside `completedTaskStats(since:userId:source:)` (`:356-394`) straight off the task document. Once the field exists on the task doc, the stat gets it for free. **No write-path change, no migration, no backfill.** |
| D7 | **Do NOT touch `ComfortBufferStore`.** | Completions never touch the buffer today (`MochiShared/ComfortBufferStore.swift:50`, pets and treats only). Keep that boundary. |
| D8 | **The control shares the Priority row under its own "EFFORT" eyebrow. No eighth block.** A compact pill, right-aligned, opening a short menu of the four levels plus Clear. Unset reads "Set effort" in the muted style. | See §6. Two labeled controls on one row (D1b). This is what unblocks the feature from Feature 5. |
| D8a | **The pill lives in exactly one place, by Priority. It is NOT echoed in the Time block.** | An undated task still deserves a size and has no Time block to echo into, so one home is the only consistent rule. A second surface would duplicate the control and raise which-is-authoritative. |
| D9 | **Duration is credit-side only. Priority keeps the stress side.** An overdue 2h task accrues no more stress than an overdue 15m one. | Two weights on two axes stay legible. Stacking duration onto stress compounds with `weight(priority)` at `MoodEngine.swift:53` and makes a bad day tank twice over. |
| D10 | **The "crushed it yesterday" check stays UNWEIGHTED.** | `MemoriesService.crushedYesterday` (`:228-233`) and `NotificationScheduling.swift:132-136` both threshold at 5 (`NotificationCopy.swift:154`). That is a count of *things done*. Weighted, two long tasks would trigger "you crushed it yesterday", which is plainly false. See §5. |
| D11 | **"2h+" resolves to exactly 120 minutes for any consumer that needs a number. The weight still caps at 3.0.** | Weight and length are two uses of one field and need not share a ceiling. Bounds an otherwise unbounded bucket without adding a fifth. Written originally for the calendar layer's block finding; that layer is tabled (`calendar-decision-record.md`) but the decision is kept, since an unbounded top bucket is a latent problem for any future consumer. |
| D12 | **Recurring completions ARE included in the effort total.** | Deliberately opposite to Best Hours D2, which excludes them so a standing chore cannot own the peak. A daily 30-minute workout is real time spent, and a total that omits it is wrong. Different question, different filter. |

### Explicitly not built

Difficulty as a separate axis. A task can be hard but quick (a difficult phone
call) and size misses that, which is a real cost accepted knowingly. Revisit only if
size proves insufficient in use.

---

## 4. Why 3.0 for the top bucket

Feeding a weighted sum into the **existing** curve, with no change to
`momentumSaturation` or `momentumMax`:

| Scenario | Weighted sum | Momentum |
|---|---|---|
| Three Tiny tasks | 3.0 | 70% of max |
| One Large task | 3.0 | 70% of max |
| One Medium task | 2.0 | 55% of max |
| One unsized task | 1.0 | 33% of max (unchanged from today) |

One long task and three short ones land on exactly the same momentum, which is the
stated goal.

**Gaming is self-limiting and unrewarded.** Inflating durations buys no coins (D5),
and the only effect is a happier pet, which defeats the purpose of having one.
The user is the only audience for the lie.

Worth noting that this safety is a consequence of the calendar layer being tabled.
A block-finding consumer would have given inflation a real cost, and also a real
bite: it would have started reserving time the user did not need. Cheap to keep
honest is better than expensive to punish.

---

## 5. Momentum is a data type, not an expression

The single largest ripple in the feature, and the one most likely to be
underestimated.

`MoodEngine.baseline` takes `completionsLast24h: Int` (`MoodEngine.swift:38`).
The forecast does not pass a count. It passes an array of **timestamps**,
`MoodSnapshot.completionTimes: [Date]` (`MoodForecast.swift:28`), deliberately, per
its own comment: *"Timestamps, not a count, so momentum ages out mid-forecast."*
`MoodForecast.completionCount(at:snapshot:)` (`:222-226`) counts the ones inside
the 24h window at each simulated instant.

Weighting momentum therefore means **`completionTimes` carries a weight per entry**,
not just a date. That array is constructed or threaded at:

| Site | File |
|---|---|
| Snapshot construction | `AppContainer.swift:188` |
| Request type + three build sites | `NotificationOrchestrator.swift:90`, `:164`, `:226`, `:248` |
| Planner parameter | `NotificationScheduling.swift:66` |
| Memories service parameter | `MemoriesService.swift:85`, `:125` |
| Direct baseline callers | `HomeViewModel.swift:434`, `VacationReentryService.swift:155` |
| Tests | `MoodForecastTests`, `NotificationPlannerTests`, `NotificationDeliveryTests`, `MemoriesServiceTests`, `LetterCompositionServiceTests`, `WidgetStateTests`, `MoodEngineTests`, `VacationReentryTests` |

### The consumer that must NOT inherit the weight

Two call sites read `completionTimes` for a **count**, not for momentum:

- `MemoriesService.crushedYesterday` (`:228-233`)
- `NotificationScheduling.swift:132-136`

Both compare against `NotificationCopy.crushedYesterdayThreshold = 5`
(`NotificationCopy.swift:154`, RC key `notif_crushed_yesterday_threshold`,
`RemoteTuning.swift:191`). These stay on the raw count. Weighting them would let
two long tasks announce "you crushed it yesterday". Per D10.

**Implementation note:** keeping the weight as a *sidecar* on the entry rather than
replacing the date means the count sites keep working with `.count` unchanged, and
only the momentum path calls `.reduce(0) { $0 + $1.weight }`. That is the smaller
and safer diff.

---

## 6. Where the control lives (D8)

The editor's fields stack (`TaskEditorView.swift:128-171`) has seven always-visible
blocks: Title, Date, Time, Priority, List, Repeat, Notes. D2's whole point is that
this must not become eight.

**Why a chip row does not fit beside Priority.** `choiceRow` lays chips out in a
`FlowLayout` (`:399`) and each chip carries 14pt horizontal padding per side
(`:359`). Priority's three chips run roughly 195pt; four duration chips run roughly
245pt. A 320pt screen leaves about 280pt of content width, so two chip groups side
by side would simply wrap, producing the eighth row by another route.

**The shape that works:** the row carries TWO eyebrow labels, "PRIORITY" on the left
over its three chips and "EFFORT" on the right over a single `valuePill` (`:345-367`,
the existing recipe used by the date and time pills). Tapping the pill opens a short
menu of the four levels plus Clear. The pill shape (not a chip ladder) is what keeps
it from reading as a second priority scale (D1b).

```
  PRIORITY                 EFFORT
  ┌──────┬──────┬──────┐   ┌──────────┐
  │ Low  │ Med  │ High │   │ Medium ⌄ │     unset: │ Set effort ⌄ │
  └──────┴──────┴──────┘   └──────────┘
```

The pill shows the chosen level (longest is "Medium", ~72pt), cannot wrap, and adds
no vertical height. `fieldBlock` (`:338-343`) takes a label and content; this needs a
variant that also accepts a trailing labeled accessory, or the row becomes an
`HStack` of two `fieldBlock`s.

---

## 7. The Stats surface

Existing tiles establish the house voice precisely (`StatsViewModel.tiles`,
`:178-209`): a bare numeral as the value, a short noun-phrase title, a lowercase
unit or scope as the subtitle. The word "Total" appears nowhere in user-facing copy
anywhere in the app.

**The honesty problem:** existing tasks have no duration and the field is optional
forever, so any sum is a floor, never a total.

**The solution is the subtitle, not a hidden floor.** The "Days together" tile
already sets the precedent of scoping a number with provenance in its subtitle
(`:199-204`, `"since \(shortDate(adopted))"`). Applied here:

```
   ~3h
   Effort
   12 of 34 rated
```

- **Value = the summed nominal per-level minutes, rounded to the nearest 30 min,
  shown as approximate** ("~3h", "~2h 30m"). Rounding is deliberate: the levels are
  coarse and their minutes are nominal (D1a), so a to-the-minute "3h 20m" would be
  false precision. This is the one number a completion count cannot express, the
  feature's original promise (§1).
- **This is an output aggregate, not an input timebox**, so it does not violate the
  no-clock-in-the-picker rule (D1). The user only ever picks Tiny/Small/Medium/Large;
  Stats rolls the nominal minutes up into a rough total.
- **Coverage lives in the subtitle** ("12 of 34 rated"), so the number cannot
  mislead and no arbitrary coverage gate is needed. Show `"–"` only when **zero**
  tasks in the range carry an effort, matching `onTimeText` (`StatsViewModel.swift:233-241`).
- **Open confirm:** if a rough hour total still feels too clock-like beside a
  clockless picker, the fallback is an effort-count subtitle ("mostly Small this
  month"). Kept as time for now since the total is the promised new number.

Placement: the existing 2-column `LazyVGrid` (`StatsView.swift:35-39`), no new card.

---

## 8. What must be built

| Layer | Change |
|---|---|
| Model | `TaskItem.estimatedMinutes: Int?` (`TaskItem.swift:98-117`), `TaskDraft` equivalent defaulting `nil` (`:119-130`). Plus an `EffortLevel` enum (`tiny/small/medium/large`) with `minutes: Int` and `label: String`, and `init?(minutes:)` for the exact reverse lookup used by the pill and Stats |
| Persistence | Firestore `estimatedMinutes` field, decode in `taskItem(id:data:)` (`TaskRepository.swift:301-316`), write in `addTask` / `updateTask`. Store minutes, not the enum (D1a) |
| Stats read | One line in `completedTaskStats` (`TaskRepository.swift:381-392`). That is the whole of D6 |
| Widget | **Nothing.** `WidgetCompletionDrain.swift:47-49` re-fetches the full `TaskItem` before completing, so the queue payload never needs the field. See §9 |
| Mood | Weighted momentum sum plus the `completionTimes` type change. See §5 |
| Recurring | Spawned occurrences inherit the duration the way they inherit `seriesId` (`TaskCompletionStore.swift:89-115`) |
| Editor | Accessory-capable `fieldBlock` variant plus the size pill and its "How big?" menu (§6) |
| Stats | One tile (§7) |
| Tuning | `effort_weight_tiny` = 1.0 / `_small` = 1.4 / `_medium` = 2.0 / `_large` = 3.0, as `number(...)` keys added to `numberKeys` for the startup audit (`RemoteTuning.swift:168-170`, `:274-276`, `:347`). The level→minute mapping stays code-fixed (part of `EffortLevel`); only the weights are tunable. **Adds 4 to the pin.** Batch tally: Effort +4, Best Hours +4, Suggestions +2 = **74 → 84.** |
| Tests | `MoodEngineTests` weighted-momentum cases; a regression test that `crushedYesterday` stays count-based (D10); editor-VM draft round-trip. The `Dates.now` vs real-clock anchoring gotcha applies |

---

## 9. Why the widget needs no work

`CompleteTaskIntent` queues only `taskId` plus a `CompletionLocalContext`
(`MochiShared/WidgetState.swift:156-159`). It never carries task fields. But the
drain re-reads the document before completing:

```swift
guard let task = (try? await taskRepository.task(id: pending.taskId, userId: userId)) ?? nil,
      !task.completed
else { continue }
```
`WidgetCompletionDrain.swift:47-49`

So the full `TaskItem`, duration included, is in hand at drain time. No queue
schema change, no legacy-decode concern, no `schemaVersion` bump.

**Unrelated bug found in passing, not in scope:** a widget-drained completion writes
`completedAt = Timestamp(date: .now)` at *drain* time (`TaskRepository.swift:261`)
while its `completedLocal*` fields reflect *tap* time (`:264-267`). A tap made more
than 24h before the drain still counts inside the momentum window
(`HomeViewModel.swift:320-321`), and the two fields disagree about which day it
was. Also `RootView.swift:32` and `HomeView.swift:61` are not sequenced, so a
`refresh()` can win the race and read a pre-drain count.

---

## 10. Settled copy and remaining polish

**Settled this session:**
- Control labeled **"EFFORT"**; levels **Tiny / Small / Medium / Large** (D1).
- Unset pill **"Set effort"**; menu lists the four levels plus **Clear** (D8).
- Stats tile title **"Effort"**, value **"~3h"** rounded to the nearest 30 min,
  subtitle **"N of M rated"** (§7).
- Pill lives only by Priority under its own eyebrow, not echoed in the Time block
  (D8a).

**Remaining (not blocking dev):**
- [x] Design comp for the EFFORT pill and menu on the Priority row. Built and
      approved 2026-07-26 (`Task Size Control.dc.html`, states 2a unset / 2b set /
      2c menu). Two labeled controls, distinct shapes, no clock text. **File cleanup
      pending:** the superseded food-metaphor section (states 1a-1c) must be deleted
      so the file carries only the EFFORT version.
- [ ] Confirm the Stats total stays time-based vs an effort-count (§7 open confirm).
- [ ] Nothing surfaces effort in letters or observations yet. Deliberate; revisit
      once there is real data. (A "you took on three Large tasks this week" letter
      beat is the obvious future consumer.)
