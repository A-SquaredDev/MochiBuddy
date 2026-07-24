//
//  DevObservationInspector.swift
//  MochiBuddy
//
//  The observation inspector (Personal Layer, Feature 4: Dev tool) -
//  lives inside the DevScheduler tab. Every ObservationCandidate with
//  gate-by-gate evidence (achieved vs required), the deterministic-replay
//  timeline (incumbent / passing / fail-streak per day, so flapping is
//  VISIBLE), ledger cadence state, and the tab's time-travel slider
//  re-evaluates the pure engine at the shifted "now" on cached inputs.
//
//  Compiled behind #if DEBUG - physically absent from release. Same
//  rationale as the scheduler inspector, which found a real bug on first
//  open.
//

#if DEBUG

import SwiftUI

enum DevObservationInspector {

    struct GateRow: Equatable, Identifiable {
        let name: String
        let achieved: String
        let required: String
        let passed: Bool
        var id: String { name }
    }

    struct Row: Equatable, Identifiable {
        let id: String
        let kindLabel: String
        let conclusionText: String
        /// Today's snapshot passes every gate (candidate view).
        let passesToday: Bool
        /// The production-facing outcome (replayed incumbent / event).
        let qualifiedText: String
        let gates: [GateRow]
        /// Compact last-six-weeks strip: one glyph per day.
        let timelineStrip: String?
        let timelineLegend: String?
    }

    struct Model: Equatable {
        var rows: [Row] = []
        var ledgerLines: [String] = []
        var evaluatedAtText = ""
    }

    // MARK: - Building

    static func model(
        from snapshot: ObservationEngine.Snapshot,
        ledgerState: ObservationLedger.State,
        at now: Date
    ) -> Model {
        var model = Model()
        model.evaluatedAtText = now.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute())

        let qualifiedByKind = Dictionary(
            uniqueKeysWithValues: snapshot.qualified.map { ($0.kind, $0) }
        )
        let timelinesByKind = Dictionary(
            uniqueKeysWithValues: snapshot.timelines.map { ($0.kind, $0) }
        )

        model.rows = snapshot.candidates.map { candidate in
            let qualified = qualifiedByKind[candidate.kind]
            let timeline = timelinesByKind[candidate.kind]
            let qualifiedText: String = if let qualified {
                "\(conclusionText(qualified.conclusion)) · since \(qualified.stableSince)"
            } else if timeline != nil {
                "no incumbent"
            } else {
                "not qualified"
            }
            return Row(
                id: candidate.kind.rawValue,
                kindLabel: label(for: candidate.kind),
                conclusionText: candidate.conclusion.map(conclusionText) ?? "no data",
                passesToday: candidate.passesAllGates,
                qualifiedText: qualifiedText,
                gates: candidate.gates.map {
                    GateRow(name: $0.name, achieved: $0.achieved, required: $0.required, passed: $0.passed)
                },
                timelineStrip: timeline.map { strip(for: $0) },
                timelineLegend: timeline == nil ? nil : "█ passing+incumbent · ▲ passing challenger · ▽ incumbent holding on fail · · silent"
            )
        }

        model.ledgerLines = ledgerLines(ledgerState)
        return model
    }

    /// One glyph per day, oldest first, last 42 days of the replay.
    private static func strip(for timeline: ObservationReplayTimeline) -> String {
        String(timeline.days.suffix(42).map { day -> Character in
            if let passing = day.passing {
                return passing == day.incumbent ? "█" : "▲"
            }
            return day.incumbent != nil ? "▽" : "·"
        })
    }

    private static func ledgerLines(_ state: ObservationLedger.State) -> [String] {
        var lines: [String] = []
        lines.append("algorithm v\(state.algorithmVersion) · schema v\(state.schemaVersion)")
        lines.append(state.rundownWeek.isEmpty
            ? "rundown cap: unused"
            : "rundown cap: \(state.rundownCount)/\(ObservationConstants.rundownWeeklyCap) in \(state.rundownWeek)")
        if state.lastSurfaced.isEmpty {
            lines.append("nothing surfaced yet")
        } else {
            for (key, day) in state.lastSurfaced.sorted(by: { $0.key < $1.key }) {
                lines.append("surfaced \(key) · \(day)")
            }
        }
        if !state.surfacedReturnEvents.isEmpty {
            lines.append("return events told: \(state.surfacedReturnEvents.count)")
        }
        return lines
    }

    static func label(for kind: ObservationKind) -> String {
        switch kind {
        case .weekday: "weekday"
        case .timeOfDay: "time of day"
        case .momentum: "momentum"
        case .listReturn: "list return"
        case .comeback: "comeback"
        }
    }

    static func conclusionText(_ conclusion: ObservationConclusion) -> String {
        switch conclusion {
        case .weekday(let weekday):
            ObservationCopy.weekdayNames.indices.contains(weekday) && weekday >= 1
                ? ObservationCopy.weekdayNames[weekday]
                : "weekday \(weekday)"
        case .band(let band): band.rawValue
        case .momentumRising: "rising"
        case .listReturn(let listId): "list \(listId)"
        case .comeback: "fast catch-up"
        }
    }
}

// MARK: - View

struct DevObservationSection: View {

    let model: DevObservationInspector.Model
    @Binding var expandedRowId: String?

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        MochiCard(padding: EdgeInsets(top: 12, leading: 15, bottom: 12, trailing: 15)) {
            VStack(alignment: .leading, spacing: 8) {
                MochiEyebrow(text: "Observations · \(model.evaluatedAtText)")
                Text("Candidates with gate-by-gate evidence. Qualified means the deterministic replay's incumbent (traits), a compose-time pass (momentum), or a live event (list return). Time travel above re-evaluates everything.")
                    .font(MochiFont.body(9.5, weight: .bold))
                    .foregroundStyle(theme.muted)

                ForEach(model.rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            expandedRowId = expandedRowId == row.id ? nil : row.id
                        } label: {
                            rowLabel(row)
                        }
                        .buttonStyle(.plain)
                        if expandedRowId == row.id {
                            rowDetail(row)
                        }
                    }
                }

                MochiEyebrow(text: "Ledger (cadence only)")
                    .padding(.top, 4)
                ForEach(model.ledgerLines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.ink)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rowLabel(_ row: DevObservationInspector.Row) -> some View {
        HStack(spacing: 8) {
            Text(row.kindLabel)
                .font(MochiFont.body(9.5, weight: .heavy))
                .foregroundStyle(theme.primaryInk)
                .padding(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                .background(theme.primary.opacity(0.85), in: Capsule())
            Text(row.conclusionText)
                .font(MochiFont.body(11, weight: .bold))
                .foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: row.passesToday ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(row.passesToday ? theme.primary : theme.muted)
            Image(systemName: expandedRowId == row.id ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(theme.muted)
        }
        .contentShape(Rectangle())
    }

    private func rowDetail(_ row: DevObservationInspector.Row) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            detailLine("qualified", row.qualifiedText)
            ForEach(row.gates) { gate in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: gate.passed ? "checkmark.circle" : "xmark.circle")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(gate.passed ? theme.primary : theme.danger)
                    Text(gate.name)
                        .font(MochiFont.body(9.5, weight: .heavy))
                        .foregroundStyle(theme.muted)
                        .frame(width: 100, alignment: .leading)
                    Text("\(gate.achieved) (needs \(gate.required))")
                        .font(MochiFont.body(10, weight: .bold))
                        .foregroundStyle(theme.ink)
                }
            }
            if let strip = row.timelineStrip {
                detailLine("last 6 wks", strip)
                if let legend = row.timelineLegend {
                    Text(legend)
                        .font(MochiFont.body(8.5, weight: .bold))
                        .foregroundStyle(theme.muted)
                }
            }
        }
        .padding(EdgeInsets(top: 4, leading: 10, bottom: 6, trailing: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface2, in: RoundedRectangle(cornerRadius: 10))
    }

    private func detailLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(MochiFont.body(9.5, weight: .heavy))
                .foregroundStyle(theme.muted)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.ink)
        }
    }
}

#endif
