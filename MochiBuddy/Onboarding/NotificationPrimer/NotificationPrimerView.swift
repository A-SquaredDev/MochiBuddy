//
//  NotificationPrimerView.swift
//  MochiBuddy
//

import SwiftUI

struct NotificationPrimerView: View {
    @State var viewModel: ObservableStateViewModel<
        NotificationPrimerBehavior.UIState,
        NotificationPrimerBehavior.ViewAction,
        NotificationPrimerBehavior.NavigationEvent
    >
    let router: any OnboardingRouting

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        OnbScaffold(
            progress: (index: 4, total: 8),
            onBack: { router.navigateBack() }
        ) {
            Halo(size: 168) {
                MochiPetView(vitality: 72, size: 124)
            }
            OnbHeading(
                eyebrow: "A gentle nudge",
                title: "Let Mochi give you a little nudge",
                bodyText: "A soft tap when something needs you, and a warm hello each morning. Never spammy — Mochi goes quiet the moment you're caught up."
            )
            MockNotification(
                title: "Mochi",
                message: "Morning! 3 things today — light one, we've got this ☀️",
                time: "8:02"
            )
        } footer: {
            MochiButton(title: "Enable reminders 🔔", isLoading: viewModel.isRequesting) {
                viewModel.trigger(.enableTapped)
            }
            MochiTextLink(title: "Maybe later") {
                viewModel.trigger(.laterTapped)
            }
        }
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .next:
                router.navigateToAppleReminders()
            }
        }
    }
}

/// Lock-screen style mock notification.
private struct MockNotification: View {
    let title: String
    let message: String
    let time: String

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Text("🍡")
                .font(.system(size: 18))
                .frame(width: 34, height: 34)
                .background(theme.primarySoft, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(MochiFont.display(13, weight: .semibold))
                        .foregroundStyle(theme.ink)
                    Spacer()
                    Text(time)
                        .font(MochiFont.body(10.5, weight: .heavy))
                        .foregroundStyle(theme.muted)
                }
                Text(message)
                    .font(MochiFont.body(12, weight: .bold))
                    .lineSpacing(3)
                    .foregroundStyle(theme.muted)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(EdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 14))
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 10)
    }
}
