//
//  TasksView.swift
//  MochiBuddy
//

import SwiftUI

struct TasksView: View {
    @State var viewModel: ObservableStateViewModel<
        TasksBehavior.UIState,
        TasksBehavior.ViewAction,
        TasksBehavior.NavigationEvent
    >
    let router: any TasksRouting

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ScreenTopBar(title: viewModel.segment.rawValue == "Done" ? "Completed" : viewModel.segment.rawValue, subtitle: viewModel.subtitle) {
                    HStack(spacing: 7) {
                        CoinPill(coins: viewModel.coins)
                        addButton
                    }
                }
                segTabs

                switch viewModel.segment {
                case .today, .upcoming:
                    taskGroups
                    if viewModel.showEmptyCalm { emptyCalmCard }
                    if viewModel.showAllCaughtUp { allCaughtUpCard }
                case .done:
                    if let celebration = viewModel.doneCelebration {
                        celebrationCard(celebration)
                    }
                    taskGroups
                case .lists:
                    listRows
                    MochiButton(title: "Manage lists", variant: .ghost) {
                        viewModel.trigger(.manageListsTapped)
                    }
                }
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 24, trailing: 18))
        }
        .background(theme.bg)
        .onAppear { viewModel.trigger(.refresh) }
        .sheet(
            item: viewModel.collectBinding(for: \.editingTask, action: { _ in .editorDismissed })
        ) { editing in
            router.taskEditor(task: editing.task)
        }
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .showManageLists:
                router.navigateToManageLists()
            }
        }
    }

    // MARK: - Chrome

    private var addButton: some View {
        Button {
            Haptics.impact(.light)
            viewModel.trigger(.addTapped)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.primaryInk)
                .frame(width: 30, height: 30)
                .background(theme.primary, in: Circle())
        }
        .buttonStyle(SquishButtonStyle())
        .accessibilityLabel("Add task")
    }

    private var segTabs: some View {
        HStack(spacing: 4) {
            ForEach(TasksBehavior.Segment.allCases, id: \.self) { segment in
                let isOn = segment == viewModel.segment
                Button {
                    Haptics.selection()
                    viewModel.trigger(.selectSegment(segment))
                } label: {
                    Text(segment.rawValue)
                        .font(MochiFont.display(12.5, weight: .medium))
                        .foregroundStyle(isOn ? theme.primaryInk : theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(isOn ? theme.primary : .clear, in: Capsule())
                        .shadow(color: isOn ? .black.opacity(0.18) : .clear, radius: 7, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(theme.surface2, in: Capsule())
        .overlay(Capsule().stroke(theme.line, lineWidth: 1.5))
        .animation(MochiMotion.soft, value: viewModel.segment)
    }

    // MARK: - Groups

    private var taskGroups: some View {
        ForEach(viewModel.groups) { group in
            VStack(spacing: 7) {
                groupLabel(group)
                ForEach(group.items) { item in
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

    private func groupLabel(_ group: TasksBehavior.Group) -> some View {
        HStack(spacing: 8) {
            Text(group.label)
                .font(MochiFont.display(13, weight: .semibold))
                .foregroundStyle(group.isDanger ? theme.danger : theme.ink)
            if let count = group.count {
                Text("\(count)")
                    .font(MochiFont.body(10.5, weight: .heavy))
                    .foregroundStyle(theme.muted)
                    .padding(EdgeInsets(top: 1, leading: 7, bottom: 1, trailing: 7))
                    .background(theme.surface2, in: Capsule())
                    .overlay(Capsule().stroke(theme.line, lineWidth: 1))
            }
            MochiDashedDivider()
        }
        .padding(.horizontal, 2)
        .padding(.top, 4)
    }

    // MARK: - Lists

    private var listRows: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.listItems) { list in
                MochiListRow(
                    icon: list.icon,
                    title: list.name,
                    subtitle: list.countText,
                    right: {
                        Circle()
                            .fill(list.color)
                            .frame(width: 12, height: 12)
                            .shadow(color: list.color.opacity(0.4), radius: 3)
                    }
                )
            }
        }
    }

    // MARK: - Empty states

    private var emptyCalmCard: some View {
        MochiCard(padding: EdgeInsets(top: 28, leading: 18, bottom: 28, trailing: 18)) {
            VStack(spacing: 6) {
                MochiPetView(mood: .content, size: 122)
                Text("Nothing due today")
                    .font(MochiFont.display(16, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Text("A calm day. Add something when you're ready.")
                    .font(MochiFont.body(12, weight: .bold))
                    .foregroundStyle(theme.muted)
                MochiButton(title: "Add a task", size: .md, block: false) {
                    viewModel.trigger(.addTapped)
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var allCaughtUpCard: some View {
        MochiCard(padding: EdgeInsets(top: 26, leading: 18, bottom: 26, trailing: 18)) {
            VStack(spacing: 6) {
                MochiPetView(mood: .thriving, size: 128)
                Text("All caught up ✨")
                    .font(MochiFont.display(17, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Text("Mochi's doing a happy wiggle.")
                    .font(MochiFont.body(12, weight: .bold))
                    .foregroundStyle(theme.muted)
                if viewModel.streakDays > 0 {
                    Text("🔥 \(viewModel.streakDays)-day streak going strong")
                        .font(MochiFont.display(13, weight: .medium))
                        .foregroundStyle(theme.primaryText)
                        .padding(EdgeInsets(top: 7, leading: 13, bottom: 7, trailing: 13))
                        .background(theme.primarySoft, in: Capsule())
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .topLeading) {
            Text("✨").font(.system(size: 15)).offset(x: 50, y: 14)
        }
        .overlay(alignment: .topTrailing) {
            Text("🎉").font(.system(size: 15)).offset(x: -60, y: 26)
        }
    }

    private func celebrationCard(_ text: String) -> some View {
        MochiCard(padding: EdgeInsets(top: 13, leading: 15, bottom: 13, trailing: 15)) {
            HStack(spacing: 12) {
                Text("🎉").font(.system(size: 26))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Nice momentum")
                        .font(MochiFont.display(13.5, weight: .semibold))
                        .foregroundStyle(theme.ink)
                    Text(text)
                        .font(MochiFont.body(11, weight: .bold))
                        .foregroundStyle(theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
