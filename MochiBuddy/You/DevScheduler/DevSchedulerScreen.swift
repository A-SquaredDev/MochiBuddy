//
//  DevSchedulerScreen.swift
//  MochiBuddy
//
//  The notification scheduler inspector (design doc: Dev tool) - makes
//  the predictive scheduler visible and the consistency invariant
//  falsifiable at a glance: the pending queue plotted over the live
//  mood(t) curve, slot accounting, taper/shh state, and a per-ping check
//  that the baked band still equals mood(fireTime) recomputed now.
//
//  Compiled behind #if DEBUG - physically absent from release. Not
//  localized, not to product a11y standard; it exists to validate.
//

#if DEBUG

import Charts
import SwiftUI

enum DevSchedulerBehavior {

    struct CurvePoint: Equatable, Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    struct PendingRow: Equatable, Identifiable {
        let id: String
        let kindLabel: String
        let fireAt: Date?
        let fireText: String
        /// Curve value at the fire time - where its dot sits on the chart.
        let yValue: Double?
        /// Mood pings only: does the baked band equal mood(fireAt) now?
        let invariantOK: Bool?
    }

    struct QuietWindow: Equatable, Identifiable {
        let start: Date
        let end: Date
        var id: Date { start }
    }

    struct UIState: UpdatableStruct, Equatable {
        var isLoading = true
        var moodText = ""
        var taperText = ""
        var shhText = ""
        var slotText = ""
        var invariantText = ""
        var invariantOK = true
        var curve: [CurvePoint] = []
        var pending: [PendingRow] = []
        var quietWindows: [QuietWindow] = []
        var horizonEnd = Date.distantFuture
        var timeTravelHours: Double = 0
        var timeTravelText = ""
    }

    enum ViewAction {
        case load
        case forceRelay
        case timeTravelChanged(Double)
    }
}

final class DevSchedulerViewModel: StateViewModel<
    DevSchedulerBehavior.UIState,
    DevSchedulerBehavior.ViewAction
> {

    private let orchestrator: NotificationOrchestrator
    private let scheduler: NotificationScheduling

    private var context: NotificationOrchestrator.RelayContext?

    init(orchestrator: NotificationOrchestrator, scheduler: NotificationScheduling) {
        self.orchestrator = orchestrator
        self.scheduler = scheduler
        super.init(initialState: DevSchedulerBehavior.UIState())
    }

    override func triggerAsync(_ action: DevSchedulerBehavior.ViewAction) async {
        switch action {
        case .load:
            await rebuild()

        case .forceRelay:
            await orchestrator.relayNow(.appForeground)
            await rebuild()

        case .timeTravelChanged(let hours):
            state.timeTravelHours = hours
            rebuildTimeTravel()
        }
    }

    private func rebuild() async {
        defer { state.isLoading = false }
        let now = Date.now
        guard let context = await orchestrator.makeContext(now: now) else { return }
        self.context = context
        let snapshot = context.snapshot

        let horizon = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        let end = MoodForecast.horizonEnd(requested: horizon, snapshot: snapshot)
        let samples = MoodForecast.curve(until: horizon, snapshot: snapshot, resolution: 30 * 60)
        let pending = await scheduler.pendingRequests()

        var next = uiState
        let value = MoodForecast.displayed(at: now, snapshot: snapshot)
        let band = MoodBand(value: value)
        next.moodText = String(format: "%.1f · %@", value, label(for: band))

        let taper = orchestrator.currentTaperState()
        let floorDays = taper.consecutiveFloorDays(before: now)
        next.taperText = taper.firstFloorDay == nil
            ? "no floor stretch"
            : "floor day \(floorDays + 1)"
        next.shhText = orchestrator.shhUntil(now: now)
            .map { "until \($0.formatted(date: .omitted, time: .shortened))" } ?? "off"

        next.curve = samples.map { .init(date: $0.date, value: $0.value) }
        next.horizonEnd = end
        next.quietWindows = Self.quietWindows(
            bedtime: context.bedtime, from: now, until: end
        )

        var counts: [String: Int] = [:]
        var rows: [DevSchedulerBehavior.PendingRow] = []
        var violations = 0
        var moodPings = 0
        for item in pending.sorted(by: { ($0.nextFireDate ?? .distantFuture) < ($1.nextFireDate ?? .distantFuture) }) {
            let kind = Self.kindLabel(for: item.id)
            counts[kind, default: 0] += 1

            var invariantOK: Bool?
            var fireAt = item.nextFireDate
            if let baked = NotificationID.parseMood(item.id) {
                moodPings += 1
                fireAt = fireAt ?? baked.fireAt
                let recomputed = MoodForecast.band(at: baked.fireAt, snapshot: snapshot)
                invariantOK = recomputed == baked.band
                if invariantOK == false { violations += 1 }
            }
            rows.append(.init(
                id: item.id,
                kindLabel: kind,
                fireAt: fireAt,
                fireText: fireAt.map {
                    $0.formatted(.dateTime.weekday(.abbreviated).hour().minute())
                } ?? "-",
                yValue: fireAt.map { fire in
                    fire <= end
                        ? MoodForecast.displayed(at: fire, snapshot: snapshot)
                        : 50
                },
                invariantOK: invariantOK
            ))
        }
        next.pending = rows
        next.slotText = "\(pending.count) / \(NotificationPlanner.Constants.slotCap) · "
            + ["promise", "mood", "rundown", "backstop"]
                .compactMap { key in counts[key].map { "\($0) \(key)" } }
                .joined(separator: " · ")
        next.invariantOK = violations == 0
        next.invariantText = moodPings == 0
            ? "no mood pings pending"
            : violations == 0
                ? "all \(moodPings) mood pings match mood(t)"
                : "\(violations) INVARIANT VIOLATION\(violations == 1 ? "" : "S")"
        setUIState(next)
        rebuildTimeTravel()
    }

    private func rebuildTimeTravel() {
        guard let snapshot = context?.snapshot else { return }
        let t = Date.now.addingTimeInterval(uiState.timeTravelHours * 3600)
        let value = MoodForecast.displayed(at: t, snapshot: snapshot)
        state.timeTravelText = String(
            format: "+%.0fh · %@ · %.1f · %@",
            uiState.timeTravelHours,
            t.formatted(.dateTime.weekday(.abbreviated).hour().minute()),
            value,
            label(for: MoodBand(value: value))
        )
    }

    private static func kindLabel(for id: String) -> String {
        if id.hasPrefix(NotificationID.duePrefix) { return "promise" }
        if id.hasPrefix(NotificationID.moodPrefix) { return "mood" }
        if id.hasPrefix(NotificationID.rundownPrefix) { return "rundown" }
        if id == NotificationID.backstop { return "backstop" }
        return "other"
    }

    private func label(for band: MoodBand) -> String {
        switch band {
        case .verySad: "very sad"
        case .anxious: "anxious"
        case .uneasy: "uneasy"
        case .content: "content"
        case .happy: "happy"
        case .ecstatic: "ecstatic"
        }
    }

    private static func quietWindows(
        bedtime: BedtimeWindow,
        from start: Date,
        until end: Date,
        calendar: Calendar = .current
    ) -> [DevSchedulerBehavior.QuietWindow] {
        guard bedtime.startMinutes != bedtime.endMinutes else { return [] }
        var windows: [DevSchedulerBehavior.QuietWindow] = []
        var day = calendar.startOfDay(for: start)
        while day < end {
            if let windowStart = calendar.date(byAdding: .minute, value: bedtime.startMinutes, to: day) {
                let span = bedtime.startMinutes < bedtime.endMinutes
                    ? bedtime.endMinutes - bedtime.startMinutes
                    : 24 * 60 - bedtime.startMinutes + bedtime.endMinutes
                let windowEnd = windowStart.addingTimeInterval(TimeInterval(span * 60))
                if windowEnd > start, windowStart < end {
                    windows.append(.init(start: max(windowStart, start), end: min(windowEnd, end)))
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return windows
    }
}

struct DevSchedulerView: View {
    @State var viewModel: StateViewModel<
        DevSchedulerBehavior.UIState,
        DevSchedulerBehavior.ViewAction
    >
    let router: any YouRouting

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ScreenTopBar(title: "Scheduler", subtitle: "DEBUG · forecast vs pending queue") {
                    Button("Re-lay") { viewModel.trigger(.forceRelay) }
                        .font(MochiFont.body(12, weight: .heavy))
                        .foregroundStyle(theme.primaryText)
                }

                if viewModel.isLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    header
                    chart
                    timeTravel
                    pendingList
                }
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 24, trailing: 18))
        }
        .background(theme.bg)
        .onLoad { viewModel.trigger(.load) }
    }

    private var header: some View {
        MochiCard(padding: EdgeInsets(top: 12, leading: 15, bottom: 12, trailing: 15)) {
            VStack(alignment: .leading, spacing: 5) {
                statLine("mood(now)", viewModel.moodText)
                statLine("slots", viewModel.slotText)
                statLine("taper", viewModel.taperText)
                statLine("shh", viewModel.shhText)
                HStack(spacing: 6) {
                    Image(systemName: viewModel.invariantOK ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(viewModel.invariantOK ? theme.primary : theme.danger)
                    Text(viewModel.invariantText)
                        .font(MochiFont.body(11.5, weight: .heavy))
                        .foregroundStyle(viewModel.invariantOK ? theme.ink : theme.danger)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(MochiFont.body(10.5, weight: .heavy))
                .foregroundStyle(theme.muted)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(MochiFont.body(11.5, weight: .bold))
                .foregroundStyle(theme.ink)
        }
    }

    private var chart: some View {
        MochiCard(padding: EdgeInsets(top: 14, leading: 12, bottom: 12, trailing: 12)) {
            Chart {
                ForEach(viewModel.quietWindows) { window in
                    RectangleMark(
                        xStart: .value("start", window.start),
                        xEnd: .value("end", window.end)
                    )
                    .foregroundStyle(theme.muted.opacity(0.08))
                }
                ForEach([15.0, 35, 50, 70, 88], id: \.self) { boundary in
                    RuleMark(y: .value("band", boundary))
                        .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(theme.line)
                }
                ForEach(viewModel.curve) { point in
                    LineMark(x: .value("t", point.date), y: .value("mood", point.value))
                        .foregroundStyle(theme.primary)
                        .interpolationMethod(.monotone)
                }
                ForEach(viewModel.pending) { row in
                    if let fireAt = row.fireAt, let y = row.yValue, fireAt < viewModel.horizonEnd {
                        PointMark(x: .value("t", fireAt), y: .value("mood", y))
                            .foregroundStyle(by: .value("class", row.kindLabel))
                            .symbol(by: .value("class", row.kindLabel))
                    }
                }
            }
            .chartYScale(domain: 0...100)
            .frame(height: 240)
        }
    }

    private var timeTravel: some View {
        MochiCard(padding: EdgeInsets(top: 12, leading: 15, bottom: 12, trailing: 15)) {
            VStack(alignment: .leading, spacing: 6) {
                MochiEyebrow(text: "Time travel (preview only)")
                Text(viewModel.timeTravelText)
                    .font(MochiFont.body(11.5, weight: .heavy))
                    .foregroundStyle(theme.ink)
                Slider(
                    value: viewModel.collectBinding(
                        for: \.timeTravelHours, action: { .timeTravelChanged($0) }
                    ),
                    in: 0...168, step: 1
                )
                .tint(theme.primary)
            }
        }
    }

    private var pendingList: some View {
        MochiCard(padding: EdgeInsets(top: 12, leading: 15, bottom: 12, trailing: 15)) {
            VStack(alignment: .leading, spacing: 7) {
                MochiEyebrow(text: "Pending · \(viewModel.pending.count)")
                ForEach(viewModel.pending) { row in
                    HStack(spacing: 8) {
                        Text(row.kindLabel)
                            .font(MochiFont.body(9.5, weight: .heavy))
                            .foregroundStyle(theme.primaryInk)
                            .padding(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                            .background(theme.primary.opacity(0.85), in: Capsule())
                        Text(row.id)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(theme.ink)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.fireText)
                            .font(MochiFont.body(10, weight: .bold))
                            .foregroundStyle(theme.muted)
                        if let invariantOK = row.invariantOK {
                            Image(systemName: invariantOK ? "checkmark.circle" : "xmark.octagon.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(invariantOK ? theme.primary : theme.danger)
                        }
                    }
                }
                if viewModel.pending.isEmpty {
                    Text("Nothing pending. Force a re-lay or add tasks.")
                        .font(MochiFont.body(11, weight: .bold))
                        .foregroundStyle(theme.muted)
                }
            }
        }
    }
}

#endif
