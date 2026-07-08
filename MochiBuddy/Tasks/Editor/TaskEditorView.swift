//
//  TaskEditorView.swift
//  MochiBuddy
//
//  The Add / Edit task sheet — full field set, snooze + delete in edit
//  mode. Dismisses itself when the ViewModel reports done; the presenting
//  screen refreshes on dismiss.
//

import SwiftUI

struct TaskEditorView: View {
    @State var viewModel: ObservableStateViewModel<
        TaskEditorBehavior.UIState,
        TaskEditorBehavior.ViewAction,
        TaskEditorBehavior.NavigationEvent
    >

    @Environment(\.mochiTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(viewModel.isEditing ? "Edit task" : "New task")
                    .font(MochiFont.display(18, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.muted)
                        .frame(width: 30, height: 30)
                        .background(theme.surface2, in: Circle())
                        .overlay(Circle().stroke(theme.line, lineWidth: 1))
                }
                .buttonStyle(SquishButtonStyle())
                .accessibilityLabel("Close")
            }
            .padding(EdgeInsets(top: 22, leading: 18, bottom: 14, trailing: 18))

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    titleField
                    if let banner = viewModel.overdueBanner {
                        overdueBanner(banner)
                    }
                    whenBlock
                    fieldBlock("Priority") {
                        choiceRow(viewModel.priorityOptions, selected: viewModel.selectedPriorityId) {
                            viewModel.trigger(.selectPriority($0))
                        }
                    }
                    fieldBlock("List") {
                        choiceRow(viewModel.listOptions, selected: viewModel.selectedListId) {
                            viewModel.trigger(.selectList($0))
                        }
                    }
                    fieldBlock("Repeat") {
                        choiceRow(viewModel.repeatOptions, selected: viewModel.selectedRepeatId) {
                            viewModel.trigger(.selectRepeat($0))
                        }
                    }
                    fieldBlock("Notes") {
                        TextField(
                            "Add a note…",
                            text: viewModel.collectBinding(for: \.notes, action: { .notesChanged($0) }),
                            axis: .vertical
                        )
                        .font(MochiFont.body(12.5, weight: .bold))
                        .foregroundStyle(theme.ink)
                        .lineLimit(2...5)
                        .padding(EdgeInsets(top: 11, leading: 13, bottom: 11, trailing: 13))
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: MochiRadius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: MochiRadius.md)
                                .stroke(theme.line, lineWidth: 1.5)
                        )
                    }
                }
                .padding(EdgeInsets(top: 0, leading: 18, bottom: 16, trailing: 18))
            }
            .scrollDismissesKeyboard(.interactively)

            footer
        }
        .background(theme.bg)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .animation(MochiMotion.soft, value: viewModel.activePicker)
        .onLoad {
            viewModel.trigger(.load)
            if !viewModel.isEditing {
                titleFocused = true
            }
        }
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .done:
                dismiss()
            }
        }
    }

    // MARK: - Fields

    private var titleField: some View {
        HStack(spacing: 7) {
            Text("✏️")
                .font(.system(size: 13))
            TextField(
                "What's next on the list?",
                text: viewModel.collectBinding(for: \.title, action: { .titleChanged($0) })
            )
            .font(MochiFont.body(13, weight: .heavy))
            .foregroundStyle(theme.ink)
            .focused($titleFocused)
        }
        .padding(EdgeInsets(top: 11, leading: 11, bottom: 11, trailing: 11))
        .background(theme.surface, in: RoundedRectangle(cornerRadius: MochiRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: MochiRadius.md)
                .stroke(titleFocused ? theme.primary : theme.line, lineWidth: 2)
        )
    }

    private func overdueBanner(_ text: String) -> some View {
        HStack(spacing: 9) {
            Text("⏰").font(.system(size: 18))
            VStack(alignment: .leading, spacing: 1) {
                Text(text)
                    .font(MochiFont.display(13, weight: .semibold))
                    .foregroundStyle(theme.danger)
                Text("Clearing this lifts Mochi the most")
                    .font(MochiFont.body(11, weight: .bold))
                    .foregroundStyle(theme.danger.opacity(0.8))
            }
            Spacer()
        }
        .padding(EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13))
        .background(theme.dangerSoft, in: RoundedRectangle(cornerRadius: MochiRadius.md))
    }

    private var whenBlock: some View {
        fieldBlock("When") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    valuePill(icon: "📅", text: viewModel.dateText, active: viewModel.hasDate) {
                        viewModel.trigger(.dateTapped)
                    }
                    valuePill(icon: "⏰", text: viewModel.timeText, active: viewModel.hasTime) {
                        viewModel.trigger(.timeTapped)
                    }
                    if viewModel.hasDate {
                        valuePill(icon: nil, text: "No date", active: false) {
                            viewModel.trigger(.noDateTapped)
                        }
                    }
                }
                switch viewModel.activePicker {
                case .date:
                    DatePicker(
                        "",
                        selection: viewModel.collectBinding(for: \.date, action: { .dateChanged($0) }),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(theme.primary)
                    .colorScheme(theme.isDark ? .dark : .light)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                case .time:
                    DatePicker(
                        "",
                        selection: viewModel.collectBinding(for: \.time, action: { .timeChanged($0) }),
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(height: 120)
                    .clipped()
                    .colorScheme(theme.isDark ? .dark : .light)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                case .none:
                    EmptyView()
                }
            }
        }
    }

    private func fieldBlock(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            MochiEyebrow(text: label)
            content()
        }
    }

    private func valuePill(icon: String?, text: String, active: Bool, onTap: @escaping () -> Void) -> some View {
        Button {
            Haptics.impact(.light)
            onTap()
        } label: {
            HStack(spacing: 7) {
                if let icon {
                    Text(icon).font(.system(size: 14))
                }
                Text(text)
                    .font(MochiFont.display(13, weight: .medium))
                    .foregroundStyle(active ? theme.primaryInk : theme.ink)
            }
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
            .background(active ? theme.primary : theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(active ? theme.primary : theme.line, lineWidth: 1.5)
            )
        }
        .buttonStyle(SquishButtonStyle())
    }

    private func choiceRow(
        _ options: [TaskEditorBehavior.ChoiceChip],
        selected: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        FlowLayout(spacing: 7) {
            ForEach(options) { option in
                let isOn = option.id == selected
                Button {
                    Haptics.selection()
                    onSelect(option.id)
                } label: {
                    HStack(spacing: 6) {
                        if let color = dotColor(option.dot) {
                            Circle().fill(color).frame(width: 9, height: 9)
                        }
                        Text(option.label)
                            .font(MochiFont.display(12.5, weight: .medium))
                            .foregroundStyle(isOn ? theme.primaryInk : theme.ink)
                    }
                    .padding(EdgeInsets(top: 8, leading: 13, bottom: 8, trailing: 13))
                    .background(isOn ? theme.primary : theme.surface, in: Capsule())
                    .overlay(Capsule().stroke(isOn ? theme.primary : theme.line, lineWidth: 1.5))
                    .shadow(color: isOn ? .black.opacity(0.16) : .clear, radius: 7, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
    }

    private func dotColor(_ dot: TaskEditorBehavior.ChipDot) -> Color? {
        switch dot {
        case .none: nil
        case .custom(let color): color
        case .warn: theme.warn
        case .danger: theme.danger
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 9) {
            MochiButton(
                title: viewModel.isEditing ? "Save changes" : "Add task",
                isLoading: viewModel.isWorking,
                isDisabled: !viewModel.canSave
            ) {
                viewModel.trigger(.saveTapped)
            }
            if viewModel.isEditing {
                HStack(spacing: 8) {
                    MochiButton(title: "Snooze", variant: .ghost, size: .md) {
                        viewModel.trigger(.snoozeTapped)
                    }
                    DangerButton(title: "Delete task") {
                        viewModel.trigger(.deleteTapped)
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 12, leading: 18, bottom: 16, trailing: 18))
        .background(theme.bg)
    }
}

/// Wrapping chip row — Layout so chips flow to new lines like the design's
/// flex-wrap rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placement = arrange(proposal: proposal, subviews: subviews)
        for (subview, position) in zip(subviews, placement.positions) {
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x - spacing)
        }
        return (CGSize(width: totalWidth, height: y + rowHeight), positions)
    }
}
