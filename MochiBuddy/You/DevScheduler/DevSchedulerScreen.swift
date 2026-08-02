//
//  DevSchedulerScreen.swift
//  MochiBuddy
//
//  The notification scheduler inspector (design doc: Dev tool) - makes
//  the predictive scheduler visible and the consistency invariant
//  falsifiable at a glance: the pending queue plotted over the live
//  mood(t) curve, slot accounting, taper/shh state, horizon end + why,
//  entitlement state, a scrubbable forecast, per-notification detail on
//  tap, and a per-ping check that the baked band still equals
//  mood(fireTime) recomputed now.
//
//  The chart is pinned to the full requested horizon. Where the
//  entitlement cap truncates the plannable window the cap is drawn as a
//  labeled rule, the unplannable remainder is shaded, and the forecast
//  continues as a dashed preview so a short curve is legible as "capped",
//  never as "broken".
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
        /// One-line class explanation for the expanded detail.
        let kindBlurb: String
        let fireAt: Date?
        let fireText: String
        let relativeText: String
        /// Curve value at the fire time - where its dot sits on the chart.
        let yValue: Double?
        /// Mood pings only: does the baked band equal mood(fireAt) now?
        let invariantOK: Bool?
        /// Mood pings only: the band baked into the id at scheduling time.
        let bakedBandText: String?
        /// Mood pings only: mood(fireAt) recomputed from the fresh snapshot.
        let recomputedBandText: String?
        /// Promises only: the linked task, resolved from the snapshot.
        let taskTitle: String?
        /// Fires after the entitlement-capped horizon (promises may;
        /// mood pings never should).
        let pastHorizon: Bool
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
        var horizonText = ""
        var horizonCapped = false
        var entitlementText = ""
        var invariantText = ""
        var invariantOK = true
        var curve: [CurvePoint] = []
        /// Forecast past the entitlement cap - preview only, nothing is
        /// ever scheduled in this region.
        var ghostCurve: [CurvePoint] = []
        var pending: [PendingRow] = []
        var quietWindows: [QuietWindow] = []
        var chartStart = Date.distantPast
        /// Entitlement-capped end of the plannable window.
        var horizonEnd = Date.distantFuture
        /// The full requested horizon (horizonDays out), uncapped.
        var requestedEnd = Date.distantFuture
        var rangeHours = 168
        var expandedRowId: String? = nil
        var scrubDate: Date? = nil
        var scrubValue: Double? = nil
        var scrubText = ""
        var timeTravelHours: Double = 0
        var timeTravelText = ""
        var observations = DevObservationInspector.Model()
        var expandedObservationId: String? = nil
        var memories = DevMemoriesInspector.Model()
        var suggestions = DevSuggestionsInspector.Model()
        var suggestionTaskId: String? = nil
        /// Feature 3 force-compose result line, DEBUG pipeline check.
        var letterComposeText = ""

        /// Right edge of the visible chart window.
        var displayEnd: Date {
            min(chartStart.addingTimeInterval(TimeInterval(rangeHours) * 3600), requestedEnd)
        }
    }

    enum ViewAction {
        case load
        case forceRelay
        case timeTravelChanged(Double)
        case rangeChanged(Int)
        case rowTapped(String)
        case observationRowTapped(String?)
        case suggestionTaskPicked(String)
        case composeLetterNow
        case scrubbed(Date?)
        /// Local dev store only: restart the 14-day trial so the horizon
        /// uncaps without re-onboarding.
        case restartTrial
    }
}

final class DevSchedulerViewModel: StateViewModel<
    DevSchedulerBehavior.UIState,
    DevSchedulerBehavior.ViewAction
> {

    private let orchestrator: NotificationOrchestrator
    private let scheduler: NotificationScheduling
    private let membershipStore: MembershipStore
    private let membershipSession: MembershipSession
    private let observationService: ObservationService?
    private let observationLedger: ObservationLedger?
    private let letterService: LetterCompositionService?
    private let memoriesService: MemoriesService?
    private let suggestionLedger: SuggestionLedger?

    private var context: NotificationOrchestrator.RelayContext?
    /// Cached once per rebuild; the engine is pure, so time travel just
    /// re-evaluates these at a shifted "now".
    private var observationInputs: ObservationEngine.Inputs?
    private var memoriesInputs: DevMemoriesInspector.Inputs?

    init(
        orchestrator: NotificationOrchestrator,
        scheduler: NotificationScheduling,
        membershipStore: MembershipStore,
        membershipSession: MembershipSession,
        observationService: ObservationService? = nil,
        observationLedger: ObservationLedger? = nil,
        letterService: LetterCompositionService? = nil,
        memoriesService: MemoriesService? = nil,
        suggestionLedger: SuggestionLedger? = nil
    ) {
        self.orchestrator = orchestrator
        self.scheduler = scheduler
        self.membershipStore = membershipStore
        self.membershipSession = membershipSession
        self.observationService = observationService
        self.observationLedger = observationLedger
        self.letterService = letterService
        self.memoriesService = memoriesService
        self.suggestionLedger = suggestionLedger
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

        case .rangeChanged(let hours):
            state.rangeHours = hours
            state.scrubDate = nil
            state.scrubValue = nil
            state.scrubText = ""
            // Resample so short windows get genuinely finer curve steps,
            // not a zoomed-in view of the 30-minute samples.
            await rebuild()

        case .rowTapped(let id):
            state.expandedRowId = uiState.expandedRowId == id ? nil : id

        case .observationRowTapped(let id):
            state.expandedObservationId = id

        case .suggestionTaskPicked(let id):
            state.suggestionTaskId = id
            rebuildTimeTravel()

        case .composeLetterNow:
            guard let letterService else { return }
            state.letterComposeText = "composing..."
            state.letterComposeText = await letterService.debugForceCompose()
            await rebuild()

        case .scrubbed(let date):
            rebuildScrub(at: date)

        case .restartTrial:
            try? await membershipStore.startTrial(plan: .yearly)
            membershipSession.status = await membershipStore.currentStatus()
            await orchestrator.relayNow(.entitlementChange)
            await rebuild()
        }
    }

    private static let fireFormat = Date.FormatStyle.dateTime
        .weekday(.abbreviated).hour().minute()

    private func rebuild() async {
        defer { state.isLoading = false }
        let now = Date.now
        guard let context = await orchestrator.makeContext(now: now) else { return }
        self.context = context
        let snapshot = context.snapshot

        let horizonDays = NotificationOrchestrator.Constants.horizonDays
        let requestedEnd = Calendar.current.date(byAdding: .day, value: horizonDays, to: now) ?? now
        let end = MoodForecast.horizonEnd(requested: requestedEnd, snapshot: snapshot)
        // The chart clips to the visible window, so only sample that far;
        // the resolution follows the range to keep the point count sane.
        let visibleEnd = min(
            requestedEnd,
            now.addingTimeInterval(TimeInterval(uiState.rangeHours) * 3600)
        )
        let samples = MoodForecast.curve(
            until: visibleEnd,
            snapshot: snapshot,
            resolution: Self.curveResolution(rangeHours: uiState.rangeHours)
        )
        let pending = await scheduler.pendingRequests()

        var next = uiState
        let value = MoodForecast.displayed(at: now, snapshot: snapshot)
        let band = MoodBand(value: value)
        next.moodText = String(format: "%.1f · %@", value, Self.label(for: band))

        let taper = orchestrator.currentTaperState()
        let floorDays = taper.consecutiveFloorDays(before: now)
        next.taperText = taper.firstFloorDay == nil
            ? "no floor stretch"
            : "floor day \(floorDays + 1)"
        next.shhText = orchestrator.shhUntil(now: now)
            .map { "until \($0.formatted(date: .omitted, time: .shortened))" } ?? "off"

        next.chartStart = now
        next.horizonEnd = end
        next.requestedEnd = requestedEnd
        // An active trial always truncates by the time elapsed since it
        // started (now+7d vs trialStart+7d) - only flag a cap someone can
        // actually see on the chart.
        next.horizonCapped = requestedEnd.timeIntervalSince(end) > 3600
        next.horizonText = next.horizonCapped
            ? "\(Self.dateText(end, now: now)) · capped by entitlement expiry (full \(horizonDays)d)"
            : "\(Self.dateText(end, now: now)) · full \(horizonDays)d"
        next.entitlementText = Self.entitlementText(for: membershipSession.status, now: now)
        if membershipSession.isLapsed {
            // The planner's lapsed gate (which counts notSubscribed) drops
            // these entirely - make that visible so a dev build without a
            // sandbox purchase never reads as "notifications are broken".
            next.entitlementText += " · PLANNER DROPS rundown/mood/letter while lapsed"
        }

        next.curve = samples.map { .init(date: $0.date, value: $0.value) }
        next.ghostCurve = Self.ghostCurve(
            from: end, until: requestedEnd, snapshot: snapshot
        )
        next.quietWindows = Self.quietWindows(
            bedtime: context.bedtime, from: now, until: requestedEnd
        )

        var counts: [String: Int] = [:]
        var rows: [DevSchedulerBehavior.PendingRow] = []
        var violations = 0
        var moodPings = 0
        for item in pending.sorted(by: { ($0.nextFireDate ?? .distantFuture) < ($1.nextFireDate ?? .distantFuture) }) {
            let kind = Self.kindLabel(for: item.id)
            counts[kind, default: 0] += 1

            var invariantOK: Bool?
            var bakedBandText: String?
            var recomputedBandText: String?
            var taskTitle: String?
            var fireAt = item.nextFireDate
            if let baked = NotificationID.parseMood(item.id) {
                moodPings += 1
                fireAt = fireAt ?? baked.fireAt
                let recomputed = MoodForecast.band(at: baked.fireAt, snapshot: snapshot)
                invariantOK = recomputed == baked.band
                bakedBandText = Self.label(for: baked.band)
                recomputedBandText = Self.label(for: recomputed)
                if invariantOK == false { violations += 1 }
            } else if item.id.hasPrefix(NotificationID.duePrefix) {
                let taskId = String(item.id.dropFirst(NotificationID.duePrefix.count))
                taskTitle = snapshot.tasks.first { $0.id == taskId }?.title
            }
            rows.append(.init(
                id: item.id,
                kindLabel: kind,
                kindBlurb: Self.kindBlurb(for: kind),
                fireAt: fireAt,
                fireText: fireAt.map { $0.formatted(Self.fireFormat) } ?? "-",
                relativeText: fireAt.map { Self.relative($0.timeIntervalSince(now)) } ?? "",
                yValue: fireAt.flatMap { fire in
                    fire <= requestedEnd
                        ? MoodForecast.displayed(at: fire, snapshot: snapshot)
                        : nil
                },
                invariantOK: invariantOK,
                bakedBandText: bakedBandText,
                recomputedBandText: recomputedBandText,
                taskTitle: taskTitle,
                pastHorizon: fireAt.map { $0 > end } ?? false
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
                ? "all \(moodPings) mood pings match the live forecast"
                : "\(violations) INVARIANT VIOLATION\(violations == 1 ? "" : "S")"
        setUIState(next)
        observationInputs = await observationService?.engineInputs(now: now)
        memoriesInputs = await memoriesService?.inspectorInputs(now: now)
        rebuildTimeTravel()
    }

    /// Re-evaluate the pure observation engine at a (possibly time-
    /// traveled) instant on the cached inputs.
    private func rebuildObservations(at now: Date) {
        guard var inputs = observationInputs,
              let ledger = observationLedger,
              let userId = observationService?.currentUserId
        else { return }
        inputs.now = now
        state.observations = DevObservationInspector.model(
            from: ObservationEngine.evaluate(inputs),
            ledgerState: ledger.state(userId: userId),
            at: now
        )
    }

    /// Re-evaluate the pure suggestion engine for the picked task at a
    /// (possibly time-traveled) instant on the cached inputs.
    private func rebuildSuggestions(at now: Date) {
        guard let inputs = observationInputs,
              let context,
              let ledger = suggestionLedger,
              let userId = observationService?.currentUserId
        else { return }
        state.suggestions = DevSuggestionsInspector.model(
            inputs: inputs,
            tasks: context.snapshot.tasks,
            pickedTaskId: uiState.suggestionTaskId,
            bedtime: context.bedtime,
            isLapsed: membershipSession.isLapsed,
            ledgerState: ledger.state(userId: userId),
            at: now,
            calendar: .current
        )
    }

    private func rebuildTimeTravel() {
        guard let snapshot = context?.snapshot else { return }
        let t = Date.now.addingTimeInterval(uiState.timeTravelHours * 3600)
        rebuildObservations(at: t)
        rebuildSuggestions(at: t)
        if let memoriesInputs {
            state.memories = DevMemoriesInspector.model(
                inputs: memoriesInputs,
                register: RundownEmotionalRegister.evaluate(
                    fireAt: t, snapshot: snapshot,
                    taper: orchestrator.currentTaperState(),
                    calendar: .current
                ),
                at: t,
                calendar: .current
            )
        }
        let value = MoodForecast.displayed(at: t, snapshot: snapshot)
        var text = String(
            format: "+%.0fh · %@ · %.1f · %@",
            uiState.timeTravelHours,
            t.formatted(Self.fireFormat),
            value,
            Self.label(for: MoodBand(value: value))
        )
        if t > uiState.horizonEnd {
            text += " · past horizon, nothing is scheduled here"
        }
        state.timeTravelText = text
    }

    private func rebuildScrub(at date: Date?) {
        state.scrubDate = date
        guard let date, let snapshot = context?.snapshot else {
            state.scrubValue = nil
            state.scrubText = ""
            return
        }
        let value = MoodForecast.displayed(at: date, snapshot: snapshot)
        state.scrubValue = value
        var text = String(
            format: "%@ · %.1f · %@",
            date.formatted(Self.fireFormat),
            value,
            Self.label(for: MoodBand(value: value))
        )
        if date > uiState.horizonEnd {
            text += " · past horizon (preview)"
        }
        state.scrubText = text
    }

    /// Granularity follows the window: 12h reads at 5-minute steps while
    /// 7d stays coarse enough to keep the chart light.
    private static func curveResolution(rangeHours: Int) -> TimeInterval {
        switch rangeHours {
        case ...12: 5 * 60
        case ...24: 10 * 60
        default: 30 * 60
        }
    }

    /// Forecast preview past the entitlement cap. Anchored at the cap so
    /// the dashed line continues exactly where the solid one ends.
    private static func ghostCurve(
        from cappedEnd: Date,
        until requestedEnd: Date,
        snapshot: MoodSnapshot
    ) -> [DevSchedulerBehavior.CurvePoint] {
        guard cappedEnd < requestedEnd else { return [] }
        var points: [DevSchedulerBehavior.CurvePoint] = []
        var t = cappedEnd
        while t < requestedEnd {
            points.append(.init(date: t, value: MoodForecast.displayed(at: t, snapshot: snapshot)))
            t = t.addingTimeInterval(30 * 60)
        }
        points.append(.init(
            date: requestedEnd,
            value: MoodForecast.displayed(at: requestedEnd, snapshot: snapshot)
        ))
        return points
    }

    private static func entitlementText(for status: MembershipStatus, now: Date) -> String {
        switch status {
        case .notSubscribed:
            "not subscribed"
        case .trial(let endsAt, let willRenew):
            "trial · ends \(dateText(endsAt, now: now))\(willRenew ? "" : " · will not renew")"
        case .active(let plan, let renewsAt, let willRenew):
            (renewsAt.map { "active \(plan.rawValue) · renews \(dateText($0, now: now))" }
                ?? "active \(plan.rawValue) · no known expiry")
                + (willRenew ? "" : " · will not renew")
        case .billingGrace(let plan, let renewsAt, let willRenew):
            (renewsAt.map { "billing grace \(plan.rawValue) · renews \(dateText($0, now: now))" }
                ?? "billing grace \(plan.rawValue)")
                + (willRenew ? "" : " · will not renew")
        case .lapsed:
            "lapsed"
        }
    }

    /// Weekday + time is only unambiguous while the weekday can't repeat
    /// (under 6 days out); anything further needs the calendar date.
    private static func dateText(_ date: Date, now: Date) -> String {
        date.timeIntervalSince(now) < 6 * 24 * 3600
            ? date.formatted(fireFormat)
            : date.formatted(.dateTime.year().month(.abbreviated).day())
    }

    private static func kindLabel(for id: String) -> String {
        if id.hasPrefix(NotificationID.duePrefix) { return "promise" }
        if id.hasPrefix(NotificationID.moodPrefix) { return "mood" }
        if id.hasPrefix(NotificationID.rundownPrefix) { return "rundown" }
        if id.hasPrefix(NotificationID.letterPrefix) { return "letter" }
        if id == NotificationID.backstop { return "backstop" }
        return "other"
    }

    private static func kindBlurb(for kind: String) -> String {
        switch kind {
        case "promise": "exact due-time reminder for a task, never mood-driven"
        case "mood": "predicted off the forecast curve, band baked into the id"
        case "rundown": "morning briefing at wake time"
        case "backstop": "repeating weekly safety net for dormant users"
        case "letter": "Sunday letter invitation, laid only for a non-dormant period"
        default: "unrecognized id"
        }
    }

    private static func label(for band: MoodBand) -> String {
        switch band {
        case .verySad: "very sad"
        case .anxious: "anxious"
        case .uneasy: "uneasy"
        case .content: "content"
        case .happy: "happy"
        case .ecstatic: "ecstatic"
        }
    }

    private static func relative(_ interval: TimeInterval) -> String {
        guard interval >= 0 else { return "past due" }
        let minutes = Int(interval / 60)
        if minutes < 60 { return "in \(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "in \(hours)h \(minutes % 60)m" }
        return "in \(hours / 24)d \(hours % 24)h"
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
            // Wall-clock anchors, matching the planner and the bedtime
            // contains check - startOfDay + minutes drifts an hour on
            // DST transition days and the inspector would lie.
            if let windowStart = calendar.date(
                bySettingHour: bedtime.startMinutes / 60,
                minute: bedtime.startMinutes % 60,
                second: 0, of: day
            ) {
                let endDay = bedtime.startMinutes < bedtime.endMinutes
                    ? day
                    : calendar.date(byAdding: .day, value: 1, to: day) ?? day
                let windowEnd = calendar.date(
                    bySettingHour: bedtime.endMinutes / 60,
                    minute: bedtime.endMinutes % 60,
                    second: 0, of: endDay
                ) ?? windowStart
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

/// Today's Firestore call tally (NetworkCallMeter): the what-does-a-day-
/// cost number the caching layer is judged against. Day-keyed, so the
/// midnight reset is structural.
private struct DevNetworkMeterSection: View {
    @Environment(\.mochiTheme) private var theme
    @State private var snapshot = NetworkCallMeter.shared.snapshot()

    var body: some View {
        MochiCard(padding: EdgeInsets(top: 12, leading: 15, bottom: 12, trailing: 15)) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Firestore calls today")
                        .font(MochiFont.body(11, weight: .heavy))
                        .foregroundStyle(theme.muted)
                    Text("\(snapshot.total) total · \(snapshot.reads) read docs · \(snapshot.writes) writes")
                        .font(MochiFont.display(15, weight: .semibold))
                        .foregroundStyle(theme.ink)
                    Text("Reads are billed documents (matches the console) · resets at midnight · batches count once · SDK traffic not counted")
                        .font(MochiFont.body(9.5, weight: .bold))
                        .foregroundStyle(theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 8) {
                    Button("Refresh") {
                        snapshot = NetworkCallMeter.shared.snapshot()
                    }
                    Button("Zero") {
                        NetworkCallMeter.shared.reset()
                        snapshot = NetworkCallMeter.shared.snapshot()
                    }
                }
                .font(MochiFont.body(11, weight: .heavy))
                .foregroundStyle(theme.primaryText)
            }
        }
        .onAppear { snapshot = NetworkCallMeter.shared.snapshot() }
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
                ScreenTopBar(
                    title: "Scheduler",
                    subtitle: "DEBUG · forecast vs pending queue",
                    onBack: { router.navigateBack() }
                ) {
                    Button("Re-lay") { viewModel.trigger(.forceRelay) }
                        .font(MochiFont.body(12, weight: .heavy))
                        .foregroundStyle(theme.primaryText)
                }

                DevNetworkMeterSection()

                if viewModel.isLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    header
                    chart
                    timeTravel
                    DevObservationSection(
                        model: viewModel.observations,
                        expandedRowId: viewModel.collectBinding(
                            for: \.expandedObservationId,
                            action: { .observationRowTapped($0) }
                        )
                    )
                    DevMemoriesSection(model: viewModel.memories)
                    DevSuggestionsSection(
                        model: viewModel.suggestions,
                        onPickTask: { viewModel.trigger(.suggestionTaskPicked($0)) }
                    )
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
                statLine("horizon", viewModel.horizonText, warn: viewModel.horizonCapped)
                statLine("entitlement", viewModel.entitlementText)
                HStack(spacing: 6) {
                    Image(systemName: viewModel.invariantOK ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(viewModel.invariantOK ? theme.primary : theme.danger)
                    Text(viewModel.invariantText)
                        .font(MochiFont.body(11.5, weight: .heavy))
                        .foregroundStyle(viewModel.invariantOK ? theme.ink : theme.danger)
                }
                .padding(.top, 2)
                Text("Checks that each pending mood ping's predicted band (baked into its id) still equals mood(t) recomputed from the current snapshot. Tap a pending row below for the per-ping comparison.")
                    .font(MochiFont.body(9.5, weight: .bold))
                    .foregroundStyle(theme.muted)
                if viewModel.horizonCapped {
                    Button("Restart local 14-day trial to uncap the horizon") {
                        viewModel.trigger(.restartTrial)
                    }
                    .font(MochiFont.body(11, weight: .heavy))
                    .foregroundStyle(theme.primaryText)
                    .padding(.top, 4)
                }
                Button("Compose last week's letter now (ignores gates)") {
                    viewModel.trigger(.composeLetterNow)
                }
                .font(MochiFont.body(11, weight: .heavy))
                .foregroundStyle(theme.primaryText)
                .padding(.top, 4)
                if !viewModel.letterComposeText.isEmpty {
                    Text(viewModel.letterComposeText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statLine(_ label: String, _ value: String, warn: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(MochiFont.body(10.5, weight: .heavy))
                .foregroundStyle(theme.muted)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(MochiFont.body(11.5, weight: .bold))
                .foregroundStyle(warn ? theme.warn : theme.ink)
        }
    }

    private var chart: some View {
        MochiCard(padding: EdgeInsets(top: 14, leading: 12, bottom: 12, trailing: 12)) {
            VStack(alignment: .leading, spacing: 8) {
                Chart {
                    ForEach(viewModel.quietWindows) { window in
                        if window.start < viewModel.displayEnd {
                            RectangleMark(
                                xStart: .value("start", window.start),
                                xEnd: .value("end", min(window.end, viewModel.displayEnd))
                            )
                            .foregroundStyle(theme.muted.opacity(0.08))
                        }
                    }
                    ForEach([15.0, 35, 50, 70, 88], id: \.self) { boundary in
                        RuleMark(y: .value("band", boundary))
                            .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            .foregroundStyle(theme.line)
                    }
                    if viewModel.horizonCapped, viewModel.horizonEnd < viewModel.displayEnd {
                        RectangleMark(
                            xStart: .value("cap", viewModel.horizonEnd),
                            xEnd: .value("end", viewModel.displayEnd)
                        )
                        .foregroundStyle(theme.warn.opacity(0.05))
                        RuleMark(x: .value("cap", viewModel.horizonEnd))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(theme.warn)
                            .annotation(position: .topTrailing, spacing: 2) {
                                Text("entitlement cap")
                                    .font(MochiFont.body(8.5, weight: .heavy))
                                    .foregroundStyle(theme.warn)
                            }
                    }
                    ForEach(viewModel.curve) { point in
                        LineMark(
                            x: .value("t", point.date),
                            y: .value("mood", point.value),
                            series: .value("series", "forecast")
                        )
                        .foregroundStyle(theme.primary)
                        .interpolationMethod(.monotone)
                    }
                    ForEach(viewModel.ghostCurve) { point in
                        LineMark(
                            x: .value("t", point.date),
                            y: .value("mood", point.value),
                            series: .value("series", "preview")
                        )
                        .foregroundStyle(theme.primary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .interpolationMethod(.monotone)
                    }
                    ForEach(viewModel.pending) { row in
                        if let fireAt = row.fireAt, let y = row.yValue, fireAt <= viewModel.displayEnd {
                            PointMark(x: .value("t", fireAt), y: .value("mood", y))
                                .foregroundStyle(by: .value("class", row.kindLabel))
                                .symbol(by: .value("class", row.kindLabel))
                                .opacity(row.pastHorizon ? 0.45 : 1)
                        }
                    }
                    if let scrubDate = viewModel.scrubDate,
                       let scrubValue = viewModel.scrubValue,
                       scrubDate >= viewModel.chartStart, scrubDate <= viewModel.displayEnd {
                        RuleMark(x: .value("scrub", scrubDate))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .foregroundStyle(theme.muted.opacity(0.6))
                        PointMark(x: .value("scrub", scrubDate), y: .value("mood", scrubValue))
                            .foregroundStyle(theme.ink)
                            .symbolSize(36)
                    }
                }
                .chartXScale(domain: viewModel.chartStart...viewModel.displayEnd)
                .chartYScale(domain: 0...100)
                .chartPlotStyle { $0.clipped() }
                .chartXSelection(value: viewModel.collectBinding(
                    for: \.scrubDate, action: { .scrubbed($0) }
                ))
                .frame(height: 240)

                Text(viewModel.scrubText.isEmpty
                     ? "Touch and drag the chart to read the forecast at any time."
                     : viewModel.scrubText)
                    .font(MochiFont.body(10.5, weight: viewModel.scrubText.isEmpty ? .bold : .heavy))
                    .foregroundStyle(viewModel.scrubText.isEmpty ? theme.muted : theme.ink)

                Picker("range", selection: viewModel.collectBinding(
                    for: \.rangeHours, action: { .rangeChanged($0) }
                )) {
                    Text("12h").tag(12)
                    Text("24h").tag(24)
                    Text("3d").tag(72)
                    Text("7d").tag(168)
                }
                .pickerStyle(.segmented)
            }
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
                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            viewModel.trigger(.rowTapped(row.id))
                        } label: {
                            pendingRowLabel(row)
                        }
                        .buttonStyle(.plain)
                        if viewModel.expandedRowId == row.id {
                            pendingRowDetail(row)
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

    private func pendingRowLabel(_ row: DevSchedulerBehavior.PendingRow) -> some View {
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
                .foregroundStyle(row.pastHorizon ? theme.warn : theme.muted)
            if let invariantOK = row.invariantOK {
                Image(systemName: invariantOK ? "checkmark.circle" : "xmark.octagon.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(invariantOK ? theme.primary : theme.danger)
            }
            Image(systemName: viewModel.expandedRowId == row.id ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(theme.muted)
        }
        .contentShape(Rectangle())
    }

    private func pendingRowDetail(_ row: DevSchedulerBehavior.PendingRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            detailLine("class", "\(row.kindLabel) · \(row.kindBlurb)")
            detailLine("fires", row.relativeText.isEmpty
                ? row.fireText
                : "\(row.fireText) · \(row.relativeText)")
            if let title = row.taskTitle {
                detailLine("task", title)
            }
            if let baked = row.bakedBandText, let recomputed = row.recomputedBandText {
                detailLine(
                    "invariant",
                    row.invariantOK == true
                        ? "baked \(baked) = recomputed \(recomputed)"
                        : "baked \(baked) BUT recomputed \(recomputed)"
                )
            }
            if row.pastHorizon {
                detailLine("horizon", row.kindLabel == "promise"
                    ? "past the entitlement cap; promises are exempt and still fire"
                    : "past the entitlement cap")
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
                .font(MochiFont.body(10, weight: .bold))
                .foregroundStyle(theme.ink)
        }
    }
}

#endif
