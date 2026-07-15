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
    @FocusState private var quickAddFocused: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                if viewModel.isLoading {
                    loadingSkeleton
                } else {
                    header
                    petStage
                    quickAdd
                    todaySection
                    doneTodaySection
                    weekSection
                }
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 24, trailing: 18))
            .animation(MochiMotion.soft, value: viewModel.isLoading)
        }
        .background(theme.bg)
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
                        MochiPetView(mood: .sleeping, size: 128, bobbing: true)
                        Text("Mochi is snoozing")
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
        .accessibilityLabel("Loading your day. Mochi is snoozing.")
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
            Button {
                viewModel.trigger(.treatsTapped)
            } label: {
                CoinPill(coins: viewModel.coins)
            }
            .buttonStyle(SquishButtonStyle())
            .accessibilityHint("Opens the treat shop")
            StreakBadge(days: viewModel.streakDays)
        }
    }

    // MARK: - Pet stage

    private var petStage: some View {
        MochiCard(padding: EdgeInsets(top: 14, leading: 15, bottom: 16, trailing: 15)) {
            VStack(spacing: 0) {
                MoodMeter(baseline: viewModel.baseline, buffer: viewModel.buffer)
                if let fadeText = viewModel.boostFadeText {
                    Text(fadeText)
                        .font(MochiFont.body(9.5, weight: .bold))
                        .foregroundStyle(theme.muted)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 2)
                        .transition(.opacity)
                }
                VStack(spacing: 2) {
                    MochiPetView(
                        mood: viewModel.isSleeping ? .sleeping : MochiMood(vitality: viewModel.displayedMood),
                        size: 128,
                        externalSquishTrigger: viewModel.petSquishTrigger,
                        onTap: { viewModel.trigger(.petTapped) }
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
                HStack(spacing: 8) {
                    MochiButton(title: "Pet Mochi", variant: .ghost, size: .md) {
                        viewModel.trigger(.petTapped)
                    }
                    MochiButton(title: "Treats", variant: .primary, size: .md) {
                        viewModel.trigger(.treatsTapped)
                    }
                }
                .padding(.top, 10)
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
