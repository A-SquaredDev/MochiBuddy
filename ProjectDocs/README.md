# ProjectDocs · archive

Working docs that have been superseded. **Everything durable in here was folded into
`mochi-requirements.md` in v0.8 (July 30 2026).** These files are kept for the long-form
reasoning, the code-line references, and the per-item human test checklists, none of
which belong in the master spec.

Nothing in this folder is a living document. If a fact here disagrees with
`mochi-requirements.md`, the requirements doc wins.

## Where things live now

| Looking for | Read |
|---|---|
| Any current spec, decision, or implementation status | `mochi-requirements.md` |
| The Journal tab in depth | `Mochi-journal.md` |
| Human QA pass | `manual-test-plan.md` |
| TestFlight / App Review gating | `submission-checklist.md` |
| Art and design deliverables still outstanding | `waiting-on-assets.md` |
| Code architecture (MVVM, routing, data/domain layers) | `MochiBuddy/DesignDocs/` |

## build-notes/

The per-feature implementation guides. Each carries a scope statement, a
what-exists-vs-what-must-be-built survey against real code lines, the locked decisions
with their rationale, as-built deltas written after the build, and a human test
checklist. The decisions and deltas are in the requirements doc; the code surveys and
test checklists are only here.

| File | Feature | State |
|---|---|---|
| `feature2-implementation-guide.md` | Personal Layer 2 · Anniversaries & memory callbacks | Built July 24 2026 |
| `feature5-implementation-guide.md` | Personal Layer 5 · Suggested times | Built July 25 2026 |
| `feature6-implementation-guide.md` | Personal Layer 6 · Journal tab | Built July 25 2026 |
| `best-hours-implementation-guide.md` | Discovery batch 1 · Best Hours + Day by day | Built July 27 2026 |
| `suggestions-implementation-guide.md` | Discovery batch 2 · Weekday fallback, row badge, push counting | Built July 27 2026 |
| `effort-implementation-guide.md` | Discovery batch 3 · Effort size | Built July 27 2026 |
| `editor-layout-implementation-guide.md` | Discovery batch 4 · Suggested-time ghost pill | **Design locked, NOT built** |

Personal Layer Features 1, 4, and 3 never had standalone guides; their specs and
as-built notes were always in the requirements doc.

**The editor-layout guide is the one file here that still describes unbuilt work.** Its
decisions are mirrored in *The discovery batch → Editor layout*, but the code-line
survey and gotchas in the guide are the practical build reference when that item is
picked up.

## decisions/

| File | Subject |
|---|---|
| `calendar-decision-record.md` | EventKit calendar access: proposed, examined, **tabled** July 25 2026. Not cancelled. Summarized in *The discovery batch → Calendar access*; the full four-use analysis, the cost breakdown, and the revival playbook are here. |

## design/

| File | Subject |
|---|---|
| `design-comp-prompts.md` | The prompts used to generate the discovery-batch comps in the Claude Design project. All three comps were built and approved July 26 2026; kept as a record of how they were asked for. |
