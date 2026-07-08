//
//  TodoItemRow.swift
//  MochiBuddy
//
//  A single task row (design system TodoItem). Four states drive the look:
//    normal  — surface-2 tile, muted checkbox
//    due     — warn meta ("Due soon")
//    overdue — danger-soft fill, danger meta
//    done    — filled flavor check, strikethrough, dimmed
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
                Text(title)
                    .font(MochiFont.body(12, weight: .heavy))
                    .foregroundStyle(theme.ink)
                    .strikethrough(isDone, color: theme.muted)
                    .lineLimit(2)
                if let meta {
                    Text(meta)
                        .font(MochiFont.body(10.5, weight: metaEmphasized ? .heavy : .bold))
                        .foregroundStyle(metaColor)
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
