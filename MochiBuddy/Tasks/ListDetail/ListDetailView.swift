//
//  ListDetailView.swift
//  MochiBuddy
//
//  Pushed from a Lists row — the tasks living in one list, open then done.
//

import SwiftUI

struct ListDetailView: View {
    @State var viewModel: StateViewModel<
        ListDetailBehavior.UIState,
        ListDetailBehavior.ViewAction
    >
    let router: any TasksRouting

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ScreenTopBar(
                    title: "\(viewModel.icon) \(viewModel.title)",
                    subtitle: viewModel.subtitle,
                    onBack: { router.navigateBack() }
                ) {
                    if viewModel.canAdd {
                        addButton
                    }
                }

                if viewModel.isLoading {
                    loadingSkeleton
                } else if viewModel.showEmpty {
                    emptyCard
                } else {
                    openSection
                    doneSection
                }
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 24, trailing: 18))
            .animation(MochiMotion.soft, value: viewModel.isLoading)
        }
        .background(theme.bg)
        .onLoad { viewModel.trigger(.refresh) }
        .sheet(
            item: viewModel.collectBinding(for: \.editingTask, action: { _ in .editorDismissed })
        ) { editing in
            router.taskEditor(
                task: editing.task,
                draftTitle: nil,
                draftListId: viewModel.newTaskListId
            )
        }
    }

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
        .accessibilityLabel("Add task to this list")
    }

    private var loadingSkeleton: some View {
        VStack(spacing: 7) {
            SkeletonTodoRow(titleWidth: 164, metaWidth: 98)
            SkeletonTodoRow(titleWidth: 122, metaWidth: 74)
            SkeletonTodoRow(titleWidth: 186, metaWidth: 110)
        }
        .mochiShimmer()
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading this list")
    }

    private var openSection: some View {
        VStack(spacing: 7) {
            ForEach(viewModel.openItems) { item in
                todoRow(item)
            }
        }
    }

    private var doneSection: some View {
        Group {
            if !viewModel.doneItems.isEmpty {
                VStack(spacing: 7) {
                    HStack(spacing: 8) {
                        Text("Done")
                            .font(MochiFont.display(13, weight: .semibold))
                            .foregroundStyle(theme.ink)
                        MochiDashedDivider()
                    }
                    .padding(.horizontal, 2)
                    .padding(.top, 4)
                    ForEach(viewModel.doneItems) { item in
                        todoRow(item)
                    }
                }
            }
        }
    }

    private var emptyCard: some View {
        MochiCard(padding: EdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16)) {
            VStack(spacing: 4) {
                Text("Nothing in here yet")
                    .font(MochiFont.display(14, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Text("Tasks you add to this list will show up here.")
                    .font(MochiFont.body(11.5, weight: .bold))
                    .foregroundStyle(theme.muted)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func todoRow(_ item: TasksBehavior.TodoUIItem) -> some View {
        TodoItemRow(
            title: item.title,
            meta: item.meta,
            state: item.state,
            chip: item.chip,
            sourceBadge: item.sourceBadge,
            onTap: { viewModel.trigger(.taskTapped(item.id)) },
            onToggle: { viewModel.trigger(.toggleTask(item.id)) }
        )
    }
}
