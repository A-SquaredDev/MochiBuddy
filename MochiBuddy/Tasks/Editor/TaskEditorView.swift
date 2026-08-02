//
//  TaskEditorView.swift
//  MochiBuddy
//
//  The Add / Edit task sheet - full field set, snooze + delete in edit
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
    @FocusState private var notesFocused: Bool

    var body: some View {
        // NavigationStack solely as a toolbar host - without it the keyboard
        // accessory (the checkmark that dismisses) never renders in a sheet.
        NavigationStack {
            editorContent
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var editorContent: some View {
        // The footer hides while a field is focused: letting it ride the
        // sheet's keyboard avoidance stacked it above the accessory bar
        // with a dead gap in between. The accessory checkmark is the
        // affordance while typing; dismissing brings the footer back.
        VStack(spacing: 0) {
            editorFields
            if !titleFocused && !notesFocused {
                footer
            }
        }
        .animation(MochiMotion.soft, value: titleFocused || notesFocused)
        .background(theme.bg.ignoresSafeArea())
        .toolbar {
            // Notes is a multiline field, so return inserts a newline;
            // the accessory checkmark is the only way to dismiss there.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    titleFocused = false
                    notesFocused = false
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                }
                .accessibilityLabel("Dismiss keyboard")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .confirmationDialog(
            "This task repeats",
            isPresented: viewModel.collectBinding(for: \.showSaveScopeOptions, action: .cancelSaveScope),
            titleVisibility: .visible,
            actions: {
                Button("Just this occurrence") { viewModel.trigger(.confirmSaveOccurrence) }
                Button("The whole series") { viewModel.trigger(.confirmSaveSeries) }
                Button("Cancel", role: .cancel) { viewModel.trigger(.cancelSaveScope) }
            },
            message: {
                Text("Changing just this occurrence detaches it. The series keeps repeating with its old details.")
            }
        )
        .confirmationDialog(
            "This task repeats",
            isPresented: viewModel.collectBinding(for: \.showDeleteOptions, action: .cancelDeleteOptions),
            titleVisibility: .visible,
            actions: {
                Button("Skip this occurrence") { viewModel.trigger(.confirmSkipOccurrence) }
                Button("Delete the series", role: .destructive) { viewModel.trigger(.confirmDeleteSeries) }
                Button("Cancel", role: .cancel) { viewModel.trigger(.cancelDeleteOptions) }
            },
            message: {
                Text("Skipping moves it to its next date. Deleting the series stops it for good.")
            }
        )
        .animation(MochiMotion.soft, value: viewModel.activePicker)
        .animation(MochiMotion.soft, value: viewModel.selectedRepeatId)
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

    private var editorFields: some View {
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
                    // D8: EFFORT shares the Priority row under its own
                    // eyebrow - two labeled controls, distinct shapes
                    // (chips vs a pill+menu), never an eighth block.
                    HStack(alignment: .top, spacing: 12) {
                        fieldBlock("Priority") {
                            choiceRow(viewModel.priorityOptions, selected: viewModel.selectedPriorityId) {
                                viewModel.trigger(.selectPriority($0))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        fieldBlock("Effort") {
                            effortPill
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    fieldBlock("List") {
                        if viewModel.isLoadingLists {
                            // Inbox is local and could render now, but the
                            // whole row appearing at once beats a lone chip
                            // gaining neighbors a beat later.
                            HStack(spacing: 7) {
                                ForEach(0..<3, id: \.self) { index in
                                    SkeletonBone(
                                        width: [64, 88, 72][index], height: 30, radius: 15
                                    )
                                }
                            }
                            .mochiShimmer()
                        } else {
                            choiceRow(viewModel.listOptions, selected: viewModel.selectedListId) {
                                viewModel.trigger(.selectList($0))
                            }
                        }
                    }
                    fieldBlock("Repeat") {
                        VStack(alignment: .leading, spacing: 10) {
                            choiceRow(viewModel.repeatOptions, selected: viewModel.selectedRepeatId) {
                                viewModel.trigger(.selectRepeat($0))
                            }
                            if !viewModel.repeatDayOptions.isEmpty {
                                repeatDayRow
                            }
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
                        .focused($notesFocused)
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
        }
    }

    // MARK: - Fields

    private var titleField: some View {
        HStack(spacing: 7) {
            Image(systemName: "pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.muted)
            TextField(
                "What's next on the list?",
                text: viewModel.collectBinding(for: \.title, action: { .titleChanged($0) })
            )
            .font(MochiFont.body(13, weight: .heavy))
            .foregroundStyle(theme.ink)
            .focused($titleFocused)
            .submitLabel(.done)
            .onSubmit { titleFocused = false }
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
                Text("Clearing this lifts \(viewModel.petName) the most")
                    .font(MochiFont.body(11, weight: .bold))
                    .foregroundStyle(theme.danger.opacity(0.8))
            }
            Spacer()
        }
        .padding(EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13))
        .background(theme.dangerSoft, in: RoundedRectangle(cornerRadius: MochiRadius.md))
    }

    private var whenBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            fieldBlock("Date") {
                VStack(alignment: .leading, spacing: 10) {
                    choiceRow(viewModel.dateOptions, selected: viewModel.selectedDateId) {
                        viewModel.trigger(.selectDateOption($0))
                    }
                    if viewModel.activePicker == .date {
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
                    }
                }
            }
            if viewModel.hasDate {
                fieldBlock("Time") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            valuePill(icon: nil, text: viewModel.timeText, active: viewModel.hasTime) {
                                viewModel.trigger(.timeTapped)
                            }
                            if viewModel.hasTime {
                                Button {
                                    Haptics.impact(.light)
                                    viewModel.trigger(.clearTimeTapped)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(theme.muted)
                                }
                                .buttonStyle(SquishButtonStyle())
                                .accessibilityLabel("Remove time")
                            }
                        }
                        if viewModel.activePicker == .time {
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
                        }
                    }
                }
            }
            if let chip = viewModel.suggestionChip {
                suggestionRow(chip)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(MochiMotion.soft, value: viewModel.suggestionChip)
    }

    /// The suggested-time chip (Personal Layer, Feature 5) - present only
    /// while its gates pass, absent otherwise. The whole row is the
    /// accept button; the small x is the dismiss affordance.
    private func suggestionRow(_ chip: TaskEditorBehavior.SuggestionChip) -> some View {
        HStack(spacing: 9) {
            Button {
                guard !chip.isConfirmed else { return }
                Haptics.impact(.light)
                viewModel.trigger(.suggestionTapped)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: chip.isConfirmed ? "checkmark.circle.fill" : "clock")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(chip.isConfirmed ? theme.primary : theme.muted)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(chip.label)
                            .font(MochiFont.display(13, weight: .medium))
                            .foregroundStyle(theme.ink)
                        if !chip.reason.isEmpty {
                            Text(chip.reason)
                                .font(MochiFont.body(11, weight: .bold))
                                .foregroundStyle(theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(SquishButtonStyle())
            .accessibilityLabel(chip.accessibilityLabel)
            if !chip.isConfirmed {
                Button {
                    Haptics.impact(.light)
                    viewModel.trigger(.suggestionDismissed)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.muted)
                        .frame(width: 26, height: 26)
                        .background(theme.surface2, in: Circle())
                }
                .buttonStyle(SquishButtonStyle())
                .accessibilityLabel(SuggestionCopy.dismissAccessibilityLabel)
            }
        }
        .padding(EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 10))
        .background(theme.surface, in: RoundedRectangle(cornerRadius: MochiRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: MochiRadius.md)
                .stroke(theme.line, lineWidth: 1.5)
        )
    }

    private func fieldBlock(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            MochiEyebrow(text: label)
            content()
        }
    }

    /// The EFFORT pill (effort guide D8): the valuePill recipe as a menu
    /// label - four magnitude levels plus Clear, no clock times anywhere.
    private var effortPill: some View {
        Menu {
            ForEach(viewModel.effortOptions) { option in
                Button(option.label) {
                    Haptics.selection()
                    viewModel.trigger(.selectEffort(option.id))
                }
            }
            if viewModel.hasEffort {
                Divider()
                Button("Clear", role: .destructive) {
                    Haptics.impact(.light)
                    viewModel.trigger(.selectEffort(nil))
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(viewModel.effortText)
                    .font(MochiFont.display(13, weight: .medium))
                    .foregroundStyle(viewModel.hasEffort ? theme.primaryInk : theme.muted)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(viewModel.hasEffort ? theme.primaryInk : theme.muted)
            }
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
            .background(
                viewModel.hasEffort ? theme.primary : theme.surface,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(viewModel.hasEffort ? theme.primary : theme.line, lineWidth: 1.5)
            )
        }
        .accessibilityLabel(
            viewModel.hasEffort ? "Effort: \(viewModel.effortText)" : "Set effort"
        )
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

    /// Sun–Sat toggles for the custom repeat cadence.
    private var repeatDayRow: some View {
        HStack(spacing: 6) {
            ForEach(viewModel.repeatDayOptions) { day in
                Button {
                    Haptics.selection()
                    viewModel.trigger(.toggleRepeatDay(day.id))
                } label: {
                    Text(day.label)
                        .font(MochiFont.display(11.5, weight: .medium))
                        .foregroundStyle(day.isOn ? theme.primaryInk : theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(day.isOn ? theme.primary : theme.surface, in: Capsule())
                        .overlay(Capsule().stroke(day.isOn ? theme.primary : theme.line, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.accessibilityLabel)
                .accessibilityAddTraits(day.isOn ? [.isSelected] : [])
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
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
                            // A list's color can match theme.primary exactly
                            // (e.g. Black Sesame + the default purple), so the
                            // dot needs a ring to stay visible on selection.
                            Circle()
                                .fill(color)
                                .overlay(
                                    Circle().stroke(
                                        isOn ? theme.primaryInk.opacity(0.85) : .clear,
                                        lineWidth: 1.5
                                    )
                                )
                                .frame(width: 9, height: 9)
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

/// Wrapping chip row - Layout so chips flow to new lines like the design's
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
