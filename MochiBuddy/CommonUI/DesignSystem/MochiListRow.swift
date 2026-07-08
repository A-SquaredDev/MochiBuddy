//
//  MochiListRow.swift
//  MochiBuddy
//
//  The generic settings/list row from the design shell: emoji icon tile,
//  title + optional subtitle, and a trailing accessory (chevron by default
//  when tappable). Danger tone recolors the title.
//

import SwiftUI

struct MochiListRow<Right: View>: View {
    let icon: String?
    var iconBg: Color?
    let title: String
    var subtitle: String?
    var isDanger = false
    var onTap: (() -> Void)?
    @ViewBuilder var right: Right

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        if let onTap {
            Button {
                Haptics.impact(.light)
                onTap()
            } label: {
                rowContent
            }
            .buttonStyle(SquishButtonStyle())
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 11) {
            if let icon {
                Text(icon)
                    .font(.system(size: 16))
                    .frame(width: 34, height: 34)
                    .background(iconBg ?? theme.surface, in: RoundedRectangle(cornerRadius: 11))
                    .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(MochiFont.body(13, weight: .heavy))
                    .foregroundStyle(isDanger ? theme.danger : theme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(MochiFont.body(11, weight: .bold))
                        .foregroundStyle(theme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            right
        }
        .multilineTextAlignment(.leading)
        .padding(EdgeInsets(top: 11, leading: 12, bottom: 11, trailing: 12))
        .background(theme.surface2, in: RoundedRectangle(cornerRadius: MochiRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: MochiRadius.md)
                .stroke(theme.line, lineWidth: 1.5)
        )
    }
}

extension MochiListRow where Right == MochiRowChevron {
    /// Navigation row — trailing chevron implied.
    init(
        icon: String?,
        iconBg: Color? = nil,
        title: String,
        subtitle: String? = nil,
        isDanger: Bool = false,
        onTap: @escaping () -> Void
    ) {
        self.init(
            icon: icon,
            iconBg: iconBg,
            title: title,
            subtitle: subtitle,
            isDanger: isDanger,
            onTap: onTap,
            right: { MochiRowChevron() }
        )
    }
}

struct MochiRowChevron: View {
    @Environment(\.mochiTheme) private var theme

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.muted)
    }
}

/// Title + optional subtitle with a MochiToggle — the card-embedded pref rows.
struct MochiToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(MochiFont.body(13, weight: .heavy))
                    .foregroundStyle(theme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(MochiFont.body(11, weight: .bold))
                        .foregroundStyle(theme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            MochiToggle(isOn: $isOn)
        }
        .accessibilityElement(children: .combine)
    }
}
