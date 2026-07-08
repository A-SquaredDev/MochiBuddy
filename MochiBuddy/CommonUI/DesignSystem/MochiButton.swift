//
//  MochiButton.swift
//  MochiBuddy
//
//  The primary Mochi action control — Fredoka type, full pill, springy
//  press. Primary fills with the flavor primary; ghost uses the soft tint.
//

import SwiftUI

struct MochiButton: View {
    enum Variant {
        case primary
        case ghost
    }

    enum Size {
        case sm, md, lg

        var vPadding: CGFloat {
            switch self {
            case .sm: 9
            case .md: 12
            case .lg: 15
            }
        }

        var hPadding: CGFloat {
            switch self {
            case .sm: 12
            case .md: 14
            case .lg: 18
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .sm: 12
            case .md: 13
            case .lg: 15
            }
        }
    }

    let title: String
    var variant: Variant = .primary
    var size: Size = .lg
    var block = true
    var isLoading = false
    var isDisabled = false
    let action: () -> Void

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        Button {
            Haptics.impact(.medium)
            action()
        } label: {
            HStack(spacing: 7) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(foreground)
                }
                Text(title)
                    .font(MochiFont.display(size.fontSize, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.vertical, size.vPadding)
            .padding(.horizontal, size.hPadding)
            .frame(maxWidth: block ? .infinity : nil)
            .background(background, in: Capsule())
        }
        .buttonStyle(SquishButtonStyle())
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled || isLoading ? 0.45 : 1)
    }

    private var background: Color {
        switch variant {
        case .primary: theme.primary
        case .ghost: theme.primarySoft
        }
    }

    private var foreground: Color {
        switch variant {
        case .primary: theme.primaryInk
        case .ghost: theme.primaryText
        }
    }
}

/// Scales down with the Mochi bounce while pressed.
struct SquishButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(MochiMotion.bounce, value: configuration.isPressed)
    }
}

/// The muted secondary text link used under primary CTAs.
struct MochiTextLink: View {
    let title: String
    var strong = false
    var action: (() -> Void)?

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        Group {
            if let action {
                Button(action: action) { label }
                    .buttonStyle(.plain)
            } else {
                label
            }
        }
    }

    private var label: some View {
        Text(title)
            .font(MochiFont.body(12.5, weight: .heavy))
            .foregroundStyle(strong ? theme.primaryText : theme.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
    }
}
