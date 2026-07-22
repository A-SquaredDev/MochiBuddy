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
    @State private var celebrationDrag: CGFloat = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ScreenTopBar(title: viewModel.segment.rawValue == "Done" ? "Completed" : viewModel.segment.rawValue, subtitle: viewModel.subtitle) {
                    HStack(spacing: 7) {
                        if viewModel.isLoading {
                            SkeletonBone(width: 58, height: 28, radius: 14)
                        } else if !viewModel.isLapsed {
                            // Lapsed: coins frozen+hidden, no new tasks.
                            CoinPill(coins: viewModel.coins)
                        }
                        if !viewModel.isLapsed {
                            addButton
                        }
                    }
                }
                segTabs

                if viewModel.isLoading {
                    loadingSkeleton
                } else {
                    segmentContent
                }
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 24, trailing: 18))
            .animation(MochiMotion.soft, value: viewModel.isLoading)
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
            case .showListDetail(let source):
                router.navigateToListDetail(source: source)
            }
        }
    }

    @ViewBuilder
    private var segmentContent: some View {
        switch viewModel.segment {
        case .today, .upcoming:
            if viewModel.showEmptyCalm { emptyCalmCard }
            if viewModel.showAllCaughtUp { allCaughtUpCard }
            taskGroups
            if let footnote = viewModel.footnote {
                footnoteCard(footnote)
            }
        case .done:
            if let celebration = viewModel.doneCelebration {
                celebrationCard(celebration)
            }
            doneTimeline
        case .lists:
            listRows
            MochiButton(title: "Manage lists", variant: .ghost) {
                viewModel.trigger(.manageListsTapped)
            }
        }
    }

    // MARK: - Loading skeleton

    /// A ghost "Today" group while the first fetch runs - group label,
    /// dashed divider, and rows matching TodoItemRow's shape.
    private var loadingSkeleton: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                SkeletonBone(width: 64, height: 12)
                SkeletonBone(width: 26, height: 15, radius: 8)
                MochiDashedDivider()
            }
            .padding(.horizontal, 2)
            .padding(.top, 4)
            SkeletonTodoRow(titleWidth: 164, metaWidth: 98)
            SkeletonTodoRow(titleWidth: 122, metaWidth: 74)
            SkeletonTodoRow(titleWidth: 186, metaWidth: 110)
            SkeletonTodoRow(titleWidth: 140, metaWidth: 86)
            MochiLoadingPhrase(phrases: [
                "Mochi is fetching your tasks…",
                "Sniffing out due dates…",
                "Sorting the to-dos…",
            ])
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
        .mochiShimmer()
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your tasks")
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
                    todoRow(item)
                }
            }
        }
    }

    /// Done tab: per-day timeline - date header, dashed rail, node per task.
    private var doneTimeline: some View {
        ForEach(viewModel.groups) { group in
            VStack(spacing: 7) {
                MochiTimelineDateHeader(text: doneHeaderText(group))
                    .padding(.horizontal, 2)
                    .padding(.top, 4)
                MochiTimeline(items: group.items, dotColor: { _ in theme.primary.opacity(0.45) }) { item in
                    todoRow(item)
                }
            }
        }
    }

    private func doneHeaderText(_ group: TasksBehavior.Group) -> String {
        group.count.map { "\(group.label) · \($0)" } ?? group.label
    }

    private func todoRow(_ item: TasksBehavior.TodoUIItem) -> some View {
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

    private func footnoteCard(_ text: String) -> some View {
        Text(text)
            .font(MochiFont.body(10.5, weight: .bold))
            .foregroundStyle(theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            .background(theme.surface2, in: RoundedRectangle(cornerRadius: MochiRadius.md))
            .padding(.top, 2)
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
                    subtitle: list.badge.map { "\(list.countText) · \($0)" } ?? list.countText,
                    onTap: { viewModel.trigger(.listTapped(list.id)) },
                    right: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(list.color)
                                .frame(width: 12, height: 12)
                                .shadow(color: list.color.opacity(0.4), radius: 3)
                            MochiRowChevron()
                        }
                    }
                )
            }
            if let hint = viewModel.remindersAccessHint {
                MochiListRow(
                    icon: "checklist",
                    title: "Apple Reminders paused",
                    subtitle: hint,
                    right: { EmptyView() }
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
                if !viewModel.isLapsed {
                    MochiButton(title: "Add a task", size: .md, block: false) {
                        viewModel.trigger(.addTapped)
                    }
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var allCaughtUpCard: some View {
        MochiCard(padding: EdgeInsets(top: 26, leading: 18, bottom: 26, trailing: 18)) {
            VStack(spacing: 6) {
                MochiPetView(mood: .thriving, size: 128)
                Text("All caught up")
                    .font(MochiFont.display(17, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Text("Mochi's doing a happy wiggle.")
                    .font(MochiFont.body(12, weight: .bold))
                    .foregroundStyle(theme.muted)
                if viewModel.streakDays > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("\(viewModel.streakDays)-day streak going strong")
                            .font(MochiFont.display(13, weight: .medium))
                    }
                    .foregroundStyle(theme.primaryText)
                    .padding(EdgeInsets(top: 7, leading: 13, bottom: 7, trailing: 13))
                    .background(theme.primarySoft, in: Capsule())
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .topLeading) {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundStyle(theme.primaryText)
                .offset(x: 50, y: 14)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "sparkle")
                .font(.system(size: 11))
                .foregroundStyle(theme.primaryText)
                .offset(x: -60, y: 26)
        }
    }

    /// Swipe horizontally past the threshold - or tap the ✕ - to dismiss
    /// for the rest of the day.
    private func celebrationCard(_ text: String) -> some View {
        MochiCard(padding: EdgeInsets(top: 13, leading: 15, bottom: 13, trailing: 15)) {
            HStack(spacing: 12) {
                Image(systemName: "party.popper.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.primaryText)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Nice momentum")
                        .font(MochiFont.display(13.5, weight: .semibold))
                        .foregroundStyle(theme.ink)
                    Text(text)
                        .font(MochiFont.body(11, weight: .bold))
                        .foregroundStyle(theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    Haptics.impact(.light)
                    viewModel.trigger(.dismissCelebration)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.muted)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .offset(x: celebrationDrag)
        .opacity(1 - min(0.6, Double(abs(celebrationDrag)) / 200.0))
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    celebrationDrag = value.translation.width
                }
                .onEnded { value in
                    if abs(value.translation.width) > 80 {
                        Haptics.impact(.light)
                        viewModel.trigger(.dismissCelebration)
                    }
                    withAnimation(MochiMotion.soft) { celebrationDrag = 0 }
                }
        )
        .animation(MochiMotion.soft, value: celebrationDrag == 0)
    }
}
