//
//  ManageListsView.swift
//  MochiBuddy
//
//  A List (not ScrollView) so rows get drag-to-reorder for free -
//  long-press a row and drag. Everything else is restyled to match
//  the design shell.
//

import SwiftUI

struct ManageListsView: View {
    @State var viewModel: StateViewModel<
        ManageListsBehavior.UIState,
        ManageListsBehavior.ViewAction
    >
    let router: any BackRouting
    /// Builds the task-editor sheet for a repeating series (routers own DI).
    let taskEditor: (TaskItem) -> AnyView

    @Environment(\.mochiTheme) private var theme
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        List {
            Group {
                ScreenTopBar(
                    title: "Manage lists",
                    subtitle: "Edit, reorder or remove",
                    onBack: { router.navigateBack() }
                )

                if viewModel.lists.isEmpty {
                    emptyHint
                }
            }
            .listRowStyling()

            ForEach(viewModel.lists) { list in
                listRow(list)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    // The card is the CELL background (not an inner view):
                    // a clear cell makes the drag-lift shadow render as a
                    // solid dark slab under the row while reordering.
                    .listRowBackground(
                        ZStack {
                            RoundedRectangle(cornerRadius: MochiRadius.md)
                                .fill(theme.surface2)
                            RoundedRectangle(cornerRadius: MochiRadius.md)
                                .strokeBorder(theme.line, lineWidth: 1.5)
                        }
                    )
            }
            .onMove { from, to in
                viewModel.trigger(.moveList(from: from, to: to))
            }

            if !viewModel.repeating.isEmpty {
                Group {
                    MochiEyebrow(text: "Repeating tasks")
                        .padding(.top, 4)
                }
                .listRowStyling()
                ForEach(viewModel.repeating) { series in
                    repeatingRow(series)
                        .listRowStyling()
                }
            }

            if viewModel.canAddLists {
                Group {
                    MochiEyebrow(text: "New list")
                        .padding(.top, 4)
                    colorPicker
                    nameInput
                }
                .listRowStyling()
            }
        }
        .listStyle(.plain)
        // Spacing lives BETWEEN cells, not inside them - in-cell bottom
        // padding widens the drag-lift shadow past the card.
        .listRowSpacing(8)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .contentMargins(.horizontal, 18, for: .scrollContent)
        .contentMargins(.top, 8, for: .scrollContent)
        .contentMargins(.bottom, 24, for: .scrollContent)
        .background(theme.bg)
        .onLoad { viewModel.trigger(.load) }
        .sheet(
            item: viewModel.collectBinding(for: \.editingSeries, action: { _ in .seriesEditorDismissed })
        ) { editing in
            taskEditor(editing.task)
        }
        .alert(
            "Delete \(viewModel.deleteCandidateName ?? "list")?",
            isPresented: viewModel.collectBinding(for: \.showDeleteConfirm, action: .cancelDelete),
            actions: {
                Button("Delete", role: .destructive) { viewModel.trigger(.confirmDelete) }
                Button("Keep", role: .cancel) { viewModel.trigger(.cancelDelete) }
            },
            message: { Text("Its tasks move to your Inbox, so nothing is lost.") }
        )
        .alert(
            "Rename list",
            isPresented: viewModel.collectBinding(for: \.showRename, action: .cancelRename),
            actions: {
                TextField(
                    "List name",
                    text: viewModel.collectBinding(for: \.renameDraft, action: { .renameDraftChanged($0) })
                )
                Button("Save") { viewModel.trigger(.confirmRename) }
                Button("Cancel", role: .cancel) { viewModel.trigger(.cancelRename) }
            }
        )
    }

    private func listRow(_ list: ManageListsBehavior.ListUIItem) -> some View {
        VStack(spacing: 0) {
            listRowHeader(list)
            if viewModel.editingColorListId == list.id {
                rowColorPicker(list)
            }
        }
        .padding(EdgeInsets(top: 11, leading: 12, bottom: 11, trailing: 12))
        .animation(MochiMotion.soft, value: viewModel.editingColorListId)
    }

    private func listRowHeader(_ list: ManageListsBehavior.ListUIItem) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.muted)
            Button {
                Haptics.impact(.light)
                viewModel.trigger(.colorDotTapped(id: list.id))
            } label: {
                Circle()
                    .fill(list.color)
                    .frame(width: 12, height: 12)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change color of \(list.name)")
            HStack(spacing: 6) {
                Image(systemName: list.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.muted)
                Text(list.name)
                    .font(MochiFont.body(13, weight: .heavy))
                    .foregroundStyle(theme.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                viewModel.trigger(.renameTapped(id: list.id))
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.muted)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rename \(list.name)")
            Button {
                viewModel.trigger(.deleteTapped(id: list.id))
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.danger)
                    .frame(width: 28, height: 28)
                    .background(theme.dangerSoft, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(list.name)")
        }
    }

    /// A live recurring series - tap to edit its rule in the task editor.
    private func repeatingRow(_ series: ManageListsBehavior.RepeatingUIItem) -> some View {
        Button {
            Haptics.impact(.light)
            viewModel.trigger(.seriesTapped(id: series.id))
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                VStack(alignment: .leading, spacing: 1) {
                    Text(series.title)
                        .font(MochiFont.body(13, weight: .heavy))
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                    Text(series.cadence)
                        .font(MochiFont.body(11, weight: .bold))
                        .foregroundStyle(theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                MochiRowChevron()
            }
            .padding(EdgeInsets(top: 11, leading: 12, bottom: 11, trailing: 12))
            .background(theme.surface2, in: RoundedRectangle(cornerRadius: MochiRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: MochiRadius.md)
                    .stroke(theme.line, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Inline swatches shown under a row after tapping its color dot.
    private func rowColorPicker(_ list: ManageListsBehavior.ListUIItem) -> some View {
        HStack(spacing: 6) {
            ForEach(viewModel.colorChoices) { choice in
                let isSelected = choice.id == list.colorHex
                Button {
                    Haptics.selection()
                    viewModel.trigger(.selectRowColor(id: list.id, colorHex: choice.id))
                } label: {
                    Circle()
                        .fill(choice.color)
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle().stroke(isSelected ? theme.ink : theme.line, lineWidth: isSelected ? 2.5 : 1.5)
                        )
                }
                .buttonStyle(SquishButtonStyle())
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
    }

    private var colorPicker: some View {
        HStack(spacing: 6) {
            ForEach(viewModel.colorChoices) { choice in
                let isSelected = choice.id == viewModel.selectedColorId
                Button {
                    Haptics.selection()
                    viewModel.trigger(.selectColor(choice.id))
                } label: {
                    Circle()
                        .fill(choice.color)
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle().stroke(isSelected ? theme.ink : theme.line, lineWidth: isSelected ? 2.5 : 1.5)
                        )
                }
                .buttonStyle(SquishButtonStyle())
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(MochiMotion.soft, value: viewModel.selectedColorId)
    }

    private var nameInput: some View {
        HStack(spacing: 10) {
            Image(systemName: "tag.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.muted)
            TextField(
                "Name your list…",
                text: viewModel.collectBinding(for: \.draftName, action: { .draftNameChanged($0) })
            )
            .font(MochiFont.body(13, weight: .heavy))
            .foregroundStyle(theme.ink)
            .focused($nameFieldFocused)
            .submitLabel(.done)
            .onSubmit { viewModel.trigger(.createTapped) }
            Button {
                Haptics.impact(.medium)
                viewModel.trigger(.createTapped)
                nameFieldFocused = false
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.primaryInk)
                    .frame(width: 30, height: 30)
                    .background(theme.primary, in: Circle())
            }
            .buttonStyle(SquishButtonStyle())
            .disabled(!viewModel.canCreate)
            .opacity(viewModel.canCreate ? 1 : 0.45)
            .accessibilityLabel("Create list")
        }
        .padding(EdgeInsets(top: 9, leading: 13, bottom: 9, trailing: 9))
        .background(theme.surface, in: RoundedRectangle(cornerRadius: MochiRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: MochiRadius.md)
                .stroke(theme.line, lineWidth: 1.5)
        )
    }

    private var emptyHint: some View {
        MochiCard {
            HStack(spacing: 11) {
                Image(systemName: "folder")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.muted)
                Text("No lists yet. Mochi files everything in the Inbox. Make one below to sort your tasks.")
                    .font(MochiFont.body(12, weight: .bold))
                    .foregroundStyle(theme.muted)
            }
        }
    }
}

private extension View {
    /// Strips List chrome so rows render as free-standing design-shell cards.
    func listRowStyling() -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
    }
}
