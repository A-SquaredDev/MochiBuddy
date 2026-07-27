//
//  DevSuggestionsInspector.swift
//  MochiBuddy
//
//  The suggested-times inspector (Personal Layer, Feature 5: Dev tool) -
//  lives inside the DevScheduler tab beside the observation and memories
//  inspectors. Pick any task from the live snapshot and see both
//  triggers' gate-by-gate story: per-scope evidence, the window-scan
//  winner, the unrounded peak vs the displayed proposal, the guardrail
//  or blocked reason, and the dismissal ledger's cadence state. The
//  tab's time-travel slider re-evaluates the pure engine at the shifted
//  "now" on cached inputs.
//
//  Compiled behind #if DEBUG - physically absent from release.
//

#if DEBUG

import SwiftUI

enum DevSuggestionsInspector {

    struct TaskOption: Equatable, Identifiable {
        let id: String
        let title: String
    }

    struct GateRow: Equatable, Identifiable {
        let id: String
        let name: String
        let detail: String
        let passed: Bool
    }

    struct TriggerModel: Equatable, Identifiable {
        let id: String
        let title: String
        let verdict: String
        let qualified: Bool
        let gates: [GateRow]
    }

    struct Model: Equatable {
        var taskOptions: [TaskOption] = []
        var pickedTaskId: String?
        var triggers: [TriggerModel] = []
        var ledgerLines: [String] = []
    }

    static func model(
        inputs: ObservationEngine.Inputs,
        tasks: [TaskItem],
        pickedTaskId: String?,
        bedtime: BedtimeWindow,
        isLapsed: Bool,
        ledgerState: SuggestionLedger.State,
        at now: Date,
        calendar: Calendar
    ) -> Model {
        var model = Model()
        model.taskOptions = tasks.map { TaskOption(id: $0.id, title: $0.title) }
        guard let task = tasks.first(where: { $0.id == pickedTaskId }) ?? tasks.first else {
            model.ledgerLines = ledgerLines(ledgerState)
            return model
        }
        model.pickedTaskId = task.id

        var shifted = inputs
        shifted.now = now
        let seriesIdentity: String? = task.repeatRule != nil || task.seriesId != nil
            ? (task.seriesId ?? task.id)
            : nil
        let context = SuggestionEngine.Context(
            series: seriesIdentity.map {
                ObservationEngine.suggestionDistribution(scope: .series($0), inputs: shifted)
            },
            list: task.listId.map {
                ObservationEngine.suggestionDistribution(scope: .list($0), inputs: shifted)
            },
            global: ObservationEngine.suggestionDistribution(scope: .global, inputs: shifted),
            bedtime: bedtime,
            isLapsed: isLapsed,
            today: CivilDay(of: now, in: calendar).dateString,
            nowMinute: minuteOfDay(now, calendar: calendar)
        )
        let snapshot = SuggestionEngine.TaskSnapshot(
            listId: task.listId,
            isRecurring: task.repeatRule != nil,
            hasTime: task.hasTime,
            scheduledMinute: task.hasTime
                ? task.dueAt.map { minuteOfDay($0, calendar: calendar) }
                : nil,
            dueDay: task.dueAt.map { CivilDay(of: $0, in: calendar).dateString },
            isAppleSource: false
        )

        model.triggers = SuggestionTrigger.allCases.map { trigger in
            let dismissKeyId = trigger == .newTime ? task.id : seriesIdentity
            let dismissedAt = dismissKeyId.flatMap {
                ledgerState.dismissed[SuggestionLedger.dismissKey(trigger, id: $0)]
            }
            let evaluation = trigger == .newTime
                ? SuggestionEngine.evaluateNewTime(task: snapshot, context: context, dismissedAt: dismissedAt)
                : SuggestionEngine.evaluateReTime(task: snapshot, context: context, dismissedAt: dismissedAt)
            let verdict: String
            if let proposal = evaluation.proposal {
                verdict = "\(proposal.tier.rawValue) scope · peak \(clock(proposal.peakMinute))"
                    + " · shows \(clock(proposal.displayedMinute))"
            } else if let blocked = evaluation.blocked {
                verdict = "blocked: \(blocked.rawValue)"
            } else {
                verdict = "preconditions not held"
            }
            return TriggerModel(
                id: trigger.rawValue,
                title: trigger.rawValue,
                verdict: verdict,
                qualified: evaluation.proposal != nil,
                gates: evaluation.gates.enumerated().map { index, gate in
                    GateRow(
                        id: "\(trigger.rawValue)-\(index)-\(gate.name)",
                        name: gate.name,
                        detail: "\(gate.achieved) (need \(gate.required))",
                        passed: gate.passed
                    )
                }
            )
        }
        model.ledgerLines = ledgerLines(ledgerState)
        return model
    }

    private static func ledgerLines(_ state: SuggestionLedger.State) -> [String] {
        var lines: [String] = []
        lines.append(state.dismissed.isEmpty
            ? "dismissed: none"
            : "dismissed: " + state.dismissed.sorted { $0.key < $1.key }
                .map { "\($0.key)@\(clock($0.value))" }.joined(separator: " · "))
        lines.append(state.acceptances.isEmpty
            ? "acceptances: none"
            : "acceptances: " + state.acceptances
                .map { "\($0.trigger)/\($0.tier)@\(clock($0.minute))\($0.retentionReported ? " reported" : "")" }
                .joined(separator: " · "))
        return lines
    }

    private static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    private static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

struct DevSuggestionsSection: View {

    let model: DevSuggestionsInspector.Model
    let onPickTask: (String) -> Void

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        MochiCard(padding: EdgeInsets(top: 12, leading: 15, bottom: 12, trailing: 15)) {
            VStack(alignment: .leading, spacing: 8) {
                MochiEyebrow(text: "Suggested times")
                Text("Feature 5: both editor triggers evaluated for the picked task at the time-travel cursor - scope gates on raw day-capped counts, window scan, unrounded peak vs the friendly-rounded proposal, guardrails. A 'weekday fallback' row marks the due-weekday retry after a runner-up silence, with its own lower floors. Cadence from the dismissal ledger.")
                    .font(MochiFont.body(9.5, weight: .bold))
                    .foregroundStyle(theme.muted)

                if model.taskOptions.isEmpty {
                    Text("No incomplete tasks in the snapshot.")
                        .font(MochiFont.body(11, weight: .bold))
                        .foregroundStyle(theme.muted)
                } else {
                    Menu {
                        ForEach(model.taskOptions) { option in
                            Button(option.title) { onPickTask(option.id) }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(model.taskOptions.first { $0.id == model.pickedTaskId }?.title ?? "Pick a task")
                                .font(MochiFont.body(11.5, weight: .heavy))
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(theme.primaryText)
                    }
                }

                ForEach(model.triggers) { trigger in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(trigger.qualified ? Color.green : theme.muted.opacity(0.4))
                                .frame(width: 7, height: 7)
                            Text(trigger.title)
                                .font(MochiFont.body(11, weight: .heavy))
                            Text(trigger.verdict)
                                .font(MochiFont.body(10, weight: .bold))
                                .foregroundStyle(theme.muted)
                        }
                        ForEach(trigger.gates) { gate in
                            HStack(spacing: 6) {
                                Image(systemName: gate.passed ? "checkmark" : "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(gate.passed ? theme.primary : theme.danger)
                                Text("\(gate.name): \(gate.detail)")
                                    .font(MochiFont.body(9.5, weight: .bold))
                                    .foregroundStyle(theme.muted)
                            }
                            .padding(.leading, 13)
                        }
                    }
                }

                MochiEyebrow(text: "Suggestion ledger (cadence only)")
                    .padding(.top, 4)
                ForEach(model.ledgerLines, id: \.self) { line in
                    Text(line)
                        .font(MochiFont.body(9.5, weight: .bold))
                        .foregroundStyle(theme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#endif
