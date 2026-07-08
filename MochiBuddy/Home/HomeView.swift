//
//  HomeView.swift
//  MochiBuddy
//
//  Home — pet + mood react to task completion and petting. Mood shows a
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
                header
                petStage
                quickAdd
                todaySection
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 24, trailing: 18))
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
            router.taskEditor(task: editing.task)
        }
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
                VStack(spacing: 2) {
                    MochiPetView(
                        vitality: viewModel.displayedMood,
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
                    MochiButton(title: "Treats 🍡", variant: .primary, size: .md) {
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
            Text("✏️")
                .font(.system(size: 13))
            TextField("What's next on the list?", text: viewModel.collectBinding(for: \.quickAddText, action: { .quickAddChanged($0) }))
                .font(MochiFont.body(12.5, weight: .bold))
                .foregroundStyle(theme.ink)
                .focused($quickAddFocused)
                .submitLabel(.done)
                .onSubmit { viewModel.trigger(.quickAddSubmitted) }
            Button {
                viewModel.trigger(.quickAddSubmitted)
                quickAddFocused = false
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.primaryInk)
                    .frame(width: 22, height: 22)
                    .background(theme.primary, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(SquishButtonStyle())
            .accessibilityLabel("Add task")
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
                ForEach(viewModel.todayItems) { item in
                    TodoItemRow(
                        title: item.title,
                        meta: item.meta,
                        state: item.state,
                        chip: item.chip,
                        onTap: { viewModel.trigger(.taskTapped(item.id)) },
                        onToggle: { viewModel.trigger(.toggleTask(item.id)) }
                    )
                }
            }
        }
    }
}
