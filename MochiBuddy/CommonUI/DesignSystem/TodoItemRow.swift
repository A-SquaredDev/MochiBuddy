//
//  TodoItemRow.swift
//  MochiBuddy
//
//  A single task row (design system TodoItem). Four states drive the look:
//    normal  - surface-2 tile, muted checkbox
//    due     - warn meta ("Due soon")
//    overdue - danger-soft fill, danger meta
//    done    - filled flavor check, strikethrough, dimmed
//  A trailing chip communicates priority/state.
//

import SwiftUI

enum TodoRowState: Equatable {
    case normal
    case due
    case overdue
    case done
}

struct TodoItemRow: View {
    let title: String
    var meta: String?
    var state: TodoRowState = .normal
    var chip: String?
    /// List membership indicator - colored dot + name on the meta line.
    var listName: String? = nil
    var listColor: Color? = nil
    /// Tiny capsule after the title for externally-sourced rows ("Reminders").
    var sourceBadge: String? = nil
    /// Repeat glyph after the title - this row is an occurrence of a series.
    var isRecurring: Bool = false
    /// Passive re-time signpost (suggestions guide B): a clock-with-arrow
    /// glyph on the meta line when the editor's chip has a time to offer.
    /// Caller-supplied - Home and Reminders rows never set it (B6).
    var showsRetimeBadge: Bool = false
    /// Row-body tap (opens detail/edit); the checkbox stays independent.
    var onTap: (() -> Void)?
    let onToggle: () -> Void

    @Environment(\.mochiTheme) private var theme

    private var isDone: Bool { state == .done }

    var body: some View {
        if let onTap {
            Button {
                Haptics.impact(.light)
                onTap()
            } label: {
                rowContent
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    onToggle()
                } label: {
                    Label(
                        isDone ? "Mark incomplete" : "Complete",
                        systemImage: isDone ? "arrow.uturn.backward" : "checkmark"
                    )
                }
                Button {
                    onTap()
                } label: {
                    Label("Open", systemImage: "square.and.pencil")
                }
            } preview: {
                TodoItemPreview(
                    title: title,
                    meta: meta,
                    state: state,
                    chip: chip,
                    listName: listName,
                    listColor: listColor,
                    sourceBadge: sourceBadge,
                    isRecurring: isRecurring
                )
                .environment(\.mochiTheme, theme)
            }
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 9) {
            Button {
                Haptics.impact(isDone ? .light : .medium)
                onToggle()
            } label: {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isDone ? theme.primary : .clear)
                    .frame(width: 20, height: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(isDone ? theme.primary : theme.muted, lineWidth: 2.5)
                    )
                    .overlay {
                        if isDone {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(theme.primaryInk)
                        }
                    }
                    .contentShape(Rectangle().inset(by: -8))
            }
            .buttonStyle(SquishButtonStyle())
            .accessibilityLabel(isDone ? "Mark incomplete" : "Mark complete")

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(MochiFont.body(12, weight: .heavy))
                        .foregroundStyle(theme.ink)
                        .strikethrough(isDone, color: theme.muted)
                        .lineLimit(2)
                    if isRecurring {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(theme.muted)
                            .accessibilityLabel("Repeats")
                    }
                    if let sourceBadge {
                        Text(sourceBadge)
                            .font(MochiFont.body(9, weight: .heavy))
                            .foregroundStyle(theme.muted)
                            .padding(EdgeInsets(top: 1.5, leading: 5, bottom: 1.5, trailing: 5))
                            .background(theme.surface, in: Capsule())
                            .overlay(Capsule().stroke(theme.line, lineWidth: 1))
                    }
                }
                if meta != nil || listName != nil {
                    HStack(spacing: 4) {
                        if state == .due {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(theme.warn)
                        }
                        if let meta {
                            Text(meta)
                                .font(MochiFont.body(10.5, weight: metaEmphasized ? .heavy : .bold))
                                .foregroundStyle(metaColor)
                        }
                        // B2: clock.arrow.circlepath, never a plain clock -
                        // the due state's clock.fill sits in this same
                        // HStack. Icon only, accent tint, no chrome (B3).
                        if showsRetimeBadge {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(theme.primaryText)
                                .accessibilityLabel("Mochi has a time idea for this")
                        }
                        if let listName {
                            if meta != nil {
                                Text("·")
                                    .font(MochiFont.body(10.5, weight: .bold))
                                    .foregroundStyle(theme.muted)
                            }
                            Circle()
                                .fill(listColor ?? theme.muted)
                                .frame(width: 7, height: 7)
                            Text(listName)
                                .font(MochiFont.body(10.5, weight: .bold))
                                .foregroundStyle(theme.muted)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let chip {
                Text(chip)
                    .font(MochiFont.body(10, weight: .heavy))
                    .foregroundStyle(chipColors.text)
                    .padding(EdgeInsets(top: 2.5, leading: 7, bottom: 2.5, trailing: 7))
                    .background(chipColors.fill, in: Capsule())
            }
        }
        .padding(EdgeInsets(top: 9, leading: 10, bottom: 9, trailing: 10))
        .background(
            state == .overdue ? theme.dangerSoft : theme.surface2,
            in: RoundedRectangle(cornerRadius: MochiRadius.md)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MochiRadius.md)
                .stroke(state == .overdue ? .clear : theme.line, lineWidth: 1.5)
        )
        .opacity(isDone ? 0.6 : 1)
        .animation(MochiMotion.soft, value: state)
    }

    private var metaEmphasized: Bool { state == .overdue || state == .due }

    private var metaColor: Color {
        switch state {
        case .overdue: theme.danger
        case .due: theme.warn
        case .normal, .done: theme.muted
        }
    }

    /// Chip tone follows the row state ("ok" reuses the flavor primary).
    private var chipColors: (fill: Color, text: Color) {
        switch state {
        case .overdue: (theme.dangerSoft, theme.danger)
        case .due: (theme.warnSoft, theme.warn)
        case .normal, .done: (theme.primarySoft, theme.primaryText)
        }
    }
}

/// Long-press preview card: the row's full metadata with no truncation.
private struct TodoItemPreview: View {
    let title: String
    var meta: String?
    var state: TodoRowState
    var chip: String?
    var listName: String?
    var listColor: Color?
    var sourceBadge: String?
    var isRecurring: Bool

    @Environment(\.mochiTheme) private var theme

    private var metaColor: Color {
        switch state {
        case .overdue: theme.danger
        case .due: theme.warn
        case .normal, .done: theme.muted
        }
    }

    private var chipColors: (fill: Color, text: Color) {
        switch state {
        case .overdue: (theme.dangerSoft, theme.danger)
        case .due: (theme.warnSoft, theme.warn)
        case .normal, .done: (theme.primarySoft, theme.primaryText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(MochiFont.body(14, weight: .heavy))
                .foregroundStyle(theme.ink)
                .strikethrough(state == .done, color: theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if let meta {
                HStack(spacing: 5) {
                    if state == .due {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(theme.warn)
                    }
                    Text(meta)
                        .font(MochiFont.body(11.5, weight: .bold))
                        .foregroundStyle(metaColor)
                }
            }

            if listName != nil || chip != nil || sourceBadge != nil || isRecurring {
                HStack(spacing: 8) {
                    if let listName {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(listColor ?? theme.muted)
                                .frame(width: 8, height: 8)
                            Text(listName)
                                .font(MochiFont.body(11, weight: .bold))
                                .foregroundStyle(theme.muted)
                        }
                    }
                    if let chip {
                        Text(chip)
                            .font(MochiFont.body(10.5, weight: .heavy))
                            .foregroundStyle(chipColors.text)
                            .padding(EdgeInsets(top: 2.5, leading: 8, bottom: 2.5, trailing: 8))
                            .background(chipColors.fill, in: Capsule())
                    }
                    if let sourceBadge {
                        Text(sourceBadge)
                            .font(MochiFont.body(10, weight: .heavy))
                            .foregroundStyle(theme.muted)
                            .padding(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                            .background(theme.surface, in: Capsule())
                            .overlay(Capsule().stroke(theme.line, lineWidth: 1))
                    }
                    if isRecurring {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .bold))
                            Text("Repeats")
                                .font(MochiFont.body(11, weight: .bold))
                        }
                        .foregroundStyle(theme.muted)
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 260, maxWidth: 340, alignment: .leading)
        .background(theme.surface2)
    }
}
