//
//  HomeView.swift
//  MochiBuddy
//
//  Home - pet + mood react to task completion and petting. Mood shows a
//  face + qualitative label with the two-layer meter, never a raw number.
//

import SwiftUI

struct HomeView: View {
    @State var viewModel: StateViewModel<
        HomeBehavior.UIState,
        HomeBehavior.ViewAction
    >
    let router: HomeRouter

    @Environment(\.mochiTheme) private var theme
    @Environment(\.openURL) private var openURL
    @FocusState private var quickAddFocused: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                if viewModel.isLoading {
                    loadingSkeleton
                } else {
                    header
                    if viewModel.showLetterEnvelope {
                        letterEnvelope
                    }
                    if let celebration = viewModel.celebrationText {
                        celebrationBanner(celebration)
                    }
                    if viewModel.showBillingBanner {
                        billingBanner
                    }
                    if let banner = viewModel.vacationBanner {
                        vacationBanner(banner)
                    }
                    if viewModel.showVacationCheckIn {
                        vacationCheckIn
                    }
                    petStage
                    if !viewModel.isLapsed {
                        quickAdd
                    }
                    todaySection
                    doneTodaySection
                    weekSection
                }
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 24, trailing: 18))
            .animation(MochiMotion.soft, value: viewModel.isLoading)
        }
        // ignoresSafeArea so the bg reaches under the keyboard - a plain
        // background stops at the keyboard safe area and the strip behind
        // its rounded top corners falls through to black.
        .background(theme.bg.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .onAppear { viewModel.trigger(.refresh) }
        .sheet(isPresented: viewModel.collectBinding(for: \.showTreats, action: .dismissTreats)) {
            TreatShopSheet(viewModel: viewModel)
        }
        .sheet(
            item: viewModel.collectBinding(for: \.editingTask, action: { _ in .editorDismissed })
        ) { editing in
            router.taskEditor(task: editing.task, draftTitle: editing.draftTitle)
        }
        .sheet(isPresented: viewModel.collectBinding(for: \.showTriage, action: .triageLater)) {
            triageSheet
        }
    }

    /// The quiet envelope: an unread letter waits, never a badge-red
    /// demand. Tapping routes into the Journal's letter view.
    private var letterEnvelope: some View {
        Button {
            viewModel.trigger(.letterEnvelopeTapped)
        } label: {
            MochiCard(padding: EdgeInsets(top: 11, leading: 15, bottom: 11, trailing: 15)) {
                HStack(spacing: 10) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.primary)
                    Text(viewModel.letterEnvelopeText)
                        .font(MochiFont.body(12.5, weight: .heavy))
                        .foregroundStyle(theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.muted)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(viewModel.letterEnvelopeText). Unread. Opens the letter.")
    }

    // MARK: - Loading skeleton

    /// Mirrors the real layout bone-for-bone so content crossfades into
    /// place; Mochi snoozes and mumbles status lines while Firestore loads.
    private var loadingSkeleton: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonBone(width: 118, height: 13)
                    SkeletonBone(width: 150, height: 9)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SkeletonBone(width: 58, height: 28, radius: 14)
                SkeletonBone(width: 46, height: 28, radius: 14)
            }
            MochiCard(padding: EdgeInsets(top: 14, leading: 15, bottom: 16, trailing: 15)) {
                VStack(spacing: 0) {
                    SkeletonBone(height: 9, radius: 4.5)
                    VStack(spacing: 4) {
                        MochiPetView(mood: .sleeping, size: 128, bobbing: true, petName: viewModel.mochiName)
                        Text("\(viewModel.mochiName) is snoozing")
                            .font(MochiFont.display(14, weight: .semibold))
                            .foregroundStyle(theme.ink)
                        MochiLoadingPhrase()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    HStack(spacing: 8) {
                        SkeletonBone(height: 38, radius: 19)
                        SkeletonBone(height: 38, radius: 19)
                    }
                    .padding(.top, 10)
                }
            }
            SkeletonBone(height: 40, radius: MochiRadius.md)
            VStack(spacing: 7) {
                HStack {
                    SkeletonBone(width: 96, height: 12)
                    Spacer()
                    SkeletonBone(width: 38, height: 9)
                }
                .padding(.horizontal, 2)
                SkeletonTodoRow(titleWidth: 160, metaWidth: 96)
                SkeletonTodoRow(titleWidth: 118, metaWidth: 72)
                SkeletonTodoRow(titleWidth: 182, metaWidth: 108)
            }
        }
        .mochiShimmer()
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your day. \(viewModel.mochiName) is snoozing.")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.greeting)
                    .font(MochiFont.display(17, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Text(viewModel.subGreeting)
                    .font(MochiFont.body(11.5, weight: .bold))
                    .foregroundStyle(theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Lapsed: the balance is frozen and retained, not spent or
            // shown - the pill returns intact on resubscribe.
            if !viewModel.isLapsed {
                Button {
                    viewModel.trigger(.treatsTapped)
                } label: {
                    CoinPill(coins: viewModel.coins)
                }
                .buttonStyle(SquishButtonStyle())
                .accessibilityHint("Opens the treat shop")
            }
            StreakBadge(days: viewModel.streakDays)
        }
    }

    /// billing_grace: fully entitled, gentle nudge - never a lockout.
    private var billingBanner: some View {
        Button {
            openURL(MochiLinks.manageSubscriptions)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "creditcard")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Your payment method needs a refresh")
                        .font(MochiFont.body(12, weight: .heavy))
                        .foregroundStyle(theme.ink)
                    Text("\(viewModel.mochiName) is not going anywhere. Tap to update it.")
                        .font(MochiFont.body(11, weight: .bold))
                        .foregroundStyle(theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.muted)
            }
            .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            .background(theme.surface, in: RoundedRectangle(cornerRadius: MochiRadius.md))
            .overlay(RoundedRectangle(cornerRadius: MochiRadius.md).stroke(theme.line, lineWidth: 1.5))
        }
        .buttonStyle(SquishButtonStyle())
    }

    // MARK: - Celebration

    /// Sparse streak milestones (7 / 30 / then every 50) - the upside
    /// must hit as hard as the downside, wherever the completion landed.
    private func celebrationBanner(_ text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.primaryText)
            Text(text)
                .font(MochiFont.body(12, weight: .heavy))
                .foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                viewModel.trigger(.dismissCelebration)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(theme.muted)
            }
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .background(theme.surface, in: RoundedRectangle(cornerRadius: MochiRadius.md))
        .overlay(RoundedRectangle(cornerRadius: MochiRadius.md).stroke(theme.line, lineWidth: 1.5))
    }

    // MARK: - Vacation

    private func vacationBanner(_ text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "beach.umbrella.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.primaryText)
            Text(text)
                .font(MochiFont.body(12, weight: .heavy))
                .foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("End now") {
                viewModel.trigger(.endVacationTapped)
            }
            .font(MochiFont.body(11.5, weight: .heavy))
            .foregroundStyle(theme.primaryText)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .background(theme.surface, in: RoundedRectangle(cornerRadius: MochiRadius.md))
        .overlay(RoundedRectangle(cornerRadius: MochiRadius.md).stroke(theme.line, lineWidth: 1.5))
    }

    /// Open-ended, two weeks in: never a push, purely opportunistic here.
    private var vacationCheckIn: some View {
        MochiCard(padding: EdgeInsets(top: 12, leading: 15, bottom: 12, trailing: 15)) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Still away? \(viewModel.mochiName) is happy to keep resting.")
                    .font(MochiFont.body(12, weight: .heavy))
                    .foregroundStyle(theme.ink)
                HStack(spacing: 8) {
                    MochiButton(title: "Keep resting", variant: .ghost, size: .md) {
                        viewModel.trigger(.vacationKeepResting)
                    }
                    MochiButton(title: "Welcome me back", variant: .primary, size: .md) {
                        viewModel.trigger(.vacationWelcomeBack)
                    }
                }
            }
        }
    }

    private var triageSheet: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    MochiPetView(mood: .content, size: 96)
                    Text("Welcome back!")
                        .font(MochiFont.display(17, weight: .semibold))
                        .foregroundStyle(theme.ink)
                    Text("Here's what came due while you were away. Let's sort it fast.")
                        .font(MochiFont.body(12, weight: .bold))
                        .foregroundStyle(theme.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 18)

                MochiCard(padding: EdgeInsets(top: 6, leading: 15, bottom: 6, trailing: 15)) {
                    VStack(spacing: 0) {
                        ForEach(viewModel.triageItems) { item in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(MochiFont.body(12.5, weight: .heavy))
                                        .foregroundStyle(theme.ink)
                                        .lineLimit(1)
                                    Text(item.meta)
                                        .font(MochiFont.body(10.5, weight: .bold))
                                        .foregroundStyle(theme.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                triageAction("checkmark.circle.fill", "Complete \(item.title)") {
                                    viewModel.trigger(.triageComplete(item.id))
                                }
                                triageAction("calendar.badge.clock", "Reschedule \(item.title)") {
                                    viewModel.trigger(.triageReschedule(item.id))
                                }
                                triageAction("xmark.circle", "Dismiss \(item.title)") {
                                    viewModel.trigger(.triageDismiss(item.id))
                                }
                            }
                            .padding(.vertical, 10)
                            if item.id != viewModel.triageItems.last?.id {
                                MochiDashedDivider()
                            }
                        }
                    }
                }

                VStack(spacing: 8) {
                    MochiButton(title: "Reschedule all to this week", variant: .primary) {
                        viewModel.trigger(.triageRescheduleAll)
                    }
                    HStack(spacing: 8) {
                        MochiButton(title: "Complete all", variant: .ghost, size: .md) {
                            viewModel.trigger(.triageCompleteAll)
                        }
                        MochiButton(title: "Dismiss all", variant: .ghost, size: .md) {
                            viewModel.trigger(.triageDismissAll)
                        }
                    }
                    MochiTextLink(title: "Later") {
                        viewModel.trigger(.triageLater)
                    }
                }
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 24, trailing: 18))
        }
        .background(theme.bg)
        .presentationDetents([.medium, .large])
    }

    private func triageAction(
        _ symbol: String, _ label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(SquishButtonStyle())
        .accessibilityLabel(label)
    }

    // MARK: - Pet stage

    private var petStage: some View {
        MochiCard(padding: EdgeInsets(top: 14, leading: 15, bottom: 16, trailing: 15)) {
            VStack(spacing: 0) {
                // Lapsed and vacation hide the mood chrome entirely - the
                // engine is paused/pinned, and a meter over a napping or
                // resting pet would be a lie.
                if !viewModel.isLapsed, !viewModel.isOnVacation {
                    MoodMeter(baseline: viewModel.baseline, buffer: viewModel.buffer)
                    if let fadeText = viewModel.boostFadeText {
                        Text(fadeText)
                            .font(MochiFont.body(9.5, weight: .bold))
                            .foregroundStyle(theme.muted)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, 2)
                            .transition(.opacity)
                    }
                }
                VStack(spacing: 2) {
                    MochiPetView(
                        mood: viewModel.isSleeping ? .sleeping : MochiMood(vitality: viewModel.displayedMood),
                        size: 128,
                        alive: true,
                        externalSquishTrigger: viewModel.petSquishTrigger,
                        onTap: viewModel.isLapsed ? nil : { viewModel.trigger(.petTapped) },
                        petName: viewModel.mochiName
                    )
                    .accessibilityLabel(
                        viewModel.isLapsed
                            ? "\(viewModel.mochiName) is napping. Membership paused."
                            : viewModel.isOnVacation
                                ? "\(viewModel.mochiName) is resting. Vacation mode on."
                                : viewModel.mochiName
                    )
                    Text(viewModel.moodTitle)
                        .font(MochiFont.display(14, weight: .semibold))
                        .foregroundStyle(theme.ink)
                    Text(viewModel.moodSub)
                        .font(MochiFont.body(11, weight: .bold))
                        .foregroundStyle(theme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                if viewModel.isLapsed {
                    MochiButton(title: viewModel.wakeCtaTitle, variant: .primary, size: .md) {
                        router.wakeMochi()
                    }
                    .accessibilityLabel("Wake \(viewModel.mochiName)")
                    .padding(.top, 10)
                } else {
                    HStack(spacing: 8) {
                        MochiButton(title: viewModel.petCtaTitle, variant: .ghost, size: .md) {
                            viewModel.trigger(.petTapped)
                        }
                        .accessibilityLabel("Pet \(viewModel.mochiName)")
                        MochiButton(title: "Treats", variant: .primary, size: .md) {
                            viewModel.trigger(.treatsTapped)
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
    }

    // MARK: - Quick add

    private var quickAdd: some View {
        HStack(spacing: 7) {
            Image(systemName: "pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.muted)
            TextField("What's next on the list?", text: viewModel.collectBinding(for: \.quickAddText, action: { .quickAddChanged($0) }))
                .font(MochiFont.body(12.5, weight: .bold))
                .foregroundStyle(theme.ink)
                .focused($quickAddFocused)
                .submitLabel(.done)
                .onSubmit {
                    viewModel.trigger(.quickAddSubmitted)
                    // Defocus so the field can't push its buffer back
                    // over the cleared text.
                    quickAddFocused = false
                }
            Button {
                // Opens the full editor (date/list/priority/repeat) seeded
                // with whatever's typed; keyboard Done still instant-adds.
                viewModel.trigger(.composeTapped)
                quickAddFocused = false
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.primaryInk)
                    .frame(width: 22, height: 22)
                    .background(theme.primary, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(SquishButtonStyle())
            .accessibilityLabel("Add task with options")
        }
        .padding(EdgeInsets(top: 8, leading: 11, bottom: 8, trailing: 11))
        .background(theme.surface, in: RoundedRectangle(cornerRadius: MochiRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: MochiRadius.md)
                .stroke(quickAddFocused ? theme.primary : theme.line, lineWidth: 2)
        )
        .animation(MochiMotion.soft, value: quickAddFocused)
    }

    // MARK: - Today

    private var todaySection: some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today's tasks")
                    .font(MochiFont.display(14, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Spacer()
                Text(viewModel.leftText)
                    .font(MochiFont.body(11, weight: .heavy))
                    .foregroundStyle(theme.muted)
            }
            .padding(.horizontal, 2)

            MochiTimelineDateHeader(text: viewModel.todayDateText)
                .padding(.horizontal, 2)

            if viewModel.showEmptyToday {
                MochiCard(padding: EdgeInsets(top: 18, leading: 16, bottom: 18, trailing: 16)) {
                    VStack(spacing: 4) {
                        Text("Nothing due today")
                            .font(MochiFont.display(14, weight: .semibold))
                            .foregroundStyle(theme.ink)
                        Text("A calm day. Add something when you're ready.")
                            .font(MochiFont.body(11.5, weight: .bold))
                            .foregroundStyle(theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                MochiTimeline(items: viewModel.todayItems, dotColor: timelineDot) { item in
                    todoRow(item)
                }
            }
        }
    }

    private var doneTodaySection: some View {
        Group {
            if !viewModel.doneTodayItems.isEmpty {
                VStack(spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Done today")
                            .font(MochiFont.display(14, weight: .semibold))
                            .foregroundStyle(theme.ink)
                        Spacer()
                        HStack(spacing: 4) {
                            Text("\(viewModel.doneTodayItems.count)")
                                .font(MochiFont.body(11, weight: .heavy))
                            Image(systemName: "party.popper.fill")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(theme.muted)
                    }
                    .padding(.horizontal, 2)
                    MochiTimeline(items: viewModel.doneTodayItems, dotColor: timelineDot) { item in
                        todoRow(item)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - This week

    private var weekSection: some View {
        Group {
            if !viewModel.weekPreview.isEmpty {
                MochiCard(padding: EdgeInsets(top: 12, leading: 15, bottom: 12, trailing: 15)) {
                    VStack(spacing: 8) {
                        MochiEyebrow(text: "This week")
                        ForEach(viewModel.weekPreview) { day in
                            HStack(spacing: 8) {
                                Text(day.dayLabel)
                                    .font(MochiFont.body(11, weight: .heavy))
                                    .foregroundStyle(theme.ink)
                                    .frame(width: 74, alignment: .leading)
                                Text(day.summary)
                                    .font(MochiFont.body(11, weight: .bold))
                                    .foregroundStyle(theme.muted)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(day.count)")
                                    .font(MochiFont.body(10, weight: .heavy))
                                    .foregroundStyle(theme.muted)
                                    .padding(EdgeInsets(top: 1, leading: 7, bottom: 1, trailing: 7))
                                    .background(theme.surface2, in: Capsule())
                                    .overlay(Capsule().stroke(theme.line, lineWidth: 1))
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Row helpers

    private func todoRow(_ item: HomeBehavior.TodoUIItem) -> some View {
        TodoItemRow(
            title: item.title,
            meta: item.meta,
            state: item.state,
            chip: item.chip,
            listName: item.listName,
            listColor: item.listColor,
            sourceBadge: item.sourceBadge,
            isRecurring: item.isRecurring,
            onTap: { viewModel.trigger(.taskTapped(item.id)) },
            onToggle: { viewModel.trigger(.toggleTask(item.id)) }
        )
    }

    private func timelineDot(_ item: HomeBehavior.TodoUIItem) -> Color {
        switch item.state {
        case .overdue: theme.danger
        case .due: theme.warn
        case .normal: theme.primary
        case .done: theme.primary.opacity(0.45)
        }
    }
}
