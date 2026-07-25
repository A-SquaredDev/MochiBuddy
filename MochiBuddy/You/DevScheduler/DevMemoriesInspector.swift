//
//  DevMemoriesInspector.swift
//  MochiBuddy
//
//  The anniversaries + memory-callbacks inspector (Personal Layer,
//  Feature 2: Dev tool) - lives inside the DevScheduler tab beside the
//  observation inspector. Today's milestone (or the next one coming),
//  the register at the time-travel cursor, every callback type's
//  evaluation with its blocked reason, and the callback ledger's
//  cadence state. The tab's time-travel slider re-evaluates the pure
//  miner at the shifted "now" on cached inputs.
//
//  Compiled behind #if DEBUG - physically absent from release.
//

#if DEBUG

import SwiftUI

enum DevMemoriesInspector {

    /// Everything the inspector evaluates over - fetched once per
    /// rebuild by MemoriesService, then re-evaluated synchronously as
    /// the slider moves.
    struct Inputs {
        var miner: CallbackMinerInputs
        var ledgerState: CallbackLedger.State
    }

    struct Row: Equatable, Identifiable {
        let id: String
        let label: String
        let detail: String
        let qualified: Bool
    }

    struct Model: Equatable {
        var anniversaryText = ""
        var registerText = ""
        var rows: [Row] = []
        var ledgerLines: [String] = []
    }

    static func model(
        inputs: Inputs,
        register: RundownEmotionalRegister,
        at now: Date,
        calendar: Calendar
    ) -> Model {
        var model = Model()
        let today = CivilDay(of: now, in: calendar)

        if let milestone = AnniversaryCalendar.milestone(
            adoptedOn: inputs.miner.adoptedOn, on: today
        ) {
            model.anniversaryText = "TODAY: \(milestone.id)"
        } else if let next = AnniversaryCalendar.nextMilestone(
            adoptedOn: inputs.miner.adoptedOn, onOrAfter: today
        ) {
            model.anniversaryText = "next: \(next.id)"
        } else {
            model.anniversaryText = "no adoptedOn, no milestones"
        }

        let claimed = PersonalLayerPlanner.streakClaims(
            day: today,
            streakCount: inputs.miner.streakCount,
            lastActiveDay: inputs.miner.lastActiveDay
        )
        model.registerText = "register: \(register.rawValue)"
            + (claimed ? " · streak claims today" : "")

        model.rows = CallbackFactMiner.evaluate(inputs.miner, on: today).map { evaluation in
            let detail: String
            if let fact = evaluation.fact {
                detail = "\(fact.factId) · source \(fact.sourceDay.dateString)"
                    + (inputs.ledgerState.consumedFactIds.contains(fact.factId) ? " · TOLD" : "")
            } else {
                detail = "blocked: \(evaluation.blocked?.rawValue ?? "unknown")"
            }
            return Row(
                id: evaluation.type.rawValue,
                label: evaluation.type.rawValue,
                detail: detail,
                qualified: evaluation.fact != nil
            )
        }

        let state = inputs.ledgerState
        model.ledgerLines = [
            "told facts: \(state.toldFacts.count) · types: \(state.toldTypes.keys.sorted().joined(separator: ","))",
            "scheduled: " + (state.scheduled.isEmpty
                ? "none"
                : state.scheduled.sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }.joined(separator: " · ")),
            "week \(today.weekKey): \(state.callbackCount(inWeekOf: today))/\(CallbackConstants.weeklyCap) callbacks"
                + " · gap \(state.nearestCallbackGap(to: today).map(String.init) ?? "-")d"
                + " (min \(CallbackConstants.minGapDays))",
            "banners shown: \(state.bannerShown.count)",
        ]
        return model
    }
}

struct DevMemoriesSection: View {

    let model: DevMemoriesInspector.Model

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        MochiCard(padding: EdgeInsets(top: 12, leading: 15, bottom: 12, trailing: 15)) {
            VStack(alignment: .leading, spacing: 8) {
                MochiEyebrow(text: "Anniversaries · callbacks")
                Text("Feature 2: milestone date math, the baseline register at the cursor, and each callback type's mining verdict. Cadence and told-once state come from the callback ledger. Time travel above re-evaluates everything.")
                    .font(MochiFont.body(9.5, weight: .bold))
                    .foregroundStyle(theme.muted)

                Text(model.anniversaryText)
                    .font(MochiFont.body(11, weight: .bold))
                Text(model.registerText)
                    .font(MochiFont.body(11, weight: .bold))
                    .foregroundStyle(theme.muted)

                ForEach(model.rows) { row in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(row.qualified ? Color.green : theme.muted.opacity(0.4))
                            .frame(width: 7, height: 7)
                            .padding(.top, 3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.label)
                                .font(MochiFont.body(11, weight: .bold))
                            Text(row.detail)
                                .font(MochiFont.body(9.5, weight: .bold))
                                .foregroundStyle(theme.muted)
                        }
                    }
                }

                MochiEyebrow(text: "Callback ledger (cadence only)")
                    .padding(.top, 4)
                ForEach(model.ledgerLines, id: \.self) { line in
                    Text(line)
                        .font(MochiFont.body(9.5, weight: .bold))
                        .foregroundStyle(theme.muted)
                }
            }
        }
    }
}

#endif
