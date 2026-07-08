//
//  ScreenTopBar.swift
//  MochiBuddy
//
//  Header row used on the app's main screens: optional round back button,
//  screen title + subtitle, optional trailing accessory (e.g. CoinPill).
//

import SwiftUI

struct ScreenTopBar<Right: View>: View {
    let title: String
    var subtitle: String?
    var onBack: (() -> Void)?
    @ViewBuilder var right: Right

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            if let onBack {
                Button {
                    Haptics.impact(.light)
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .frame(width: 34, height: 34)
                        .background(theme.surface2, in: Circle())
                }
                .buttonStyle(SquishButtonStyle())
                .accessibilityLabel("Back")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(MochiFont.display(22, weight: .semibold))
                    .foregroundStyle(theme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(MochiFont.body(12, weight: .bold))
                        .foregroundStyle(theme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            right
        }
    }
}

extension ScreenTopBar where Right == EmptyView {
    init(title: String, subtitle: String? = nil, onBack: (() -> Void)? = nil) {
        self.init(title: title, subtitle: subtitle, onBack: onBack, right: { EmptyView() })
    }
}
