//
//  YouView.swift
//  MochiBuddy
//

import SwiftUI

struct YouView: View {
    @State var viewModel: ObservableStateViewModel<
        YouBehavior.UIState,
        YouBehavior.ViewAction,
        YouBehavior.NavigationEvent
    >
    let router: any YouRouting

    @Environment(\.mochiTheme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ScreenTopBar(title: "You", subtitle: "Preferences & Mochi's care") {
                    CoinPill(coins: viewModel.coins)
                }
                identityRow
                flavorCard
                careCard
                navigationRows
                MochiEyebrow(text: "Account")
                    .padding(.top, 4)
                accountRows
                MochiEyebrow(text: "About & legal")
                    .padding(.top, 4)
                legalRows
                Text(viewModel.appVersion)
                    .font(MochiFont.body(10.5, weight: .bold))
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 24, trailing: 18))
        }
        .background(theme.bg)
        .onAppear { viewModel.trigger(.refresh) }
        .alert(
            "Restore purchases",
            isPresented: viewModel.collectBinding(for: \.restoreMessage.isNotNil, action: .dismissRestoreMessage),
            actions: { Button("OK", role: .cancel) { viewModel.trigger(.dismissRestoreMessage) } },
            message: { Text(viewModel.restoreMessage ?? "") }
        )
        .alert(
            "Sign out?",
            isPresented: viewModel.collectBinding(for: \.showSignOutConfirm, action: .cancelSignOut),
            actions: {
                Button("Sign out", role: .destructive) { viewModel.trigger(.confirmSignOut) }
                Button("Stay", role: .cancel) { viewModel.trigger(.cancelSignOut) }
            },
            message: { Text("Your tasks, coins and Mochi stay safe in the cloud — sign back in anytime.") }
        )
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .editBedtime: router.navigateToBedtime()
            case .showStats: router.navigateToStats()
            case .showNotifications: router.navigateToNotifications()
            case .showReminders: router.navigateToAppleReminders()
            case .showVacation: router.navigateToVacation()
            case .showManageLists: router.navigateToManageLists()
            case .startDeleteFlow: router.navigateToDeleteWarn()
            case .signedOut: router.exitToOnboarding()
            }
        }
    }

    // MARK: - Sections

    private var identityRow: some View {
        HStack(spacing: 11) {
            Text(viewModel.avatarLetter)
                .font(MochiFont.display(15, weight: .semibold))
                .foregroundStyle(theme.primaryInk)
                .frame(width: 38, height: 38)
                .background(theme.primary, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.displayName)
                    .font(MochiFont.display(13.5, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Text(viewModel.identitySub)
                    .font(MochiFont.body(11, weight: .bold))
                    .foregroundStyle(theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if viewModel.isMember {
                Text("Mochi+")
                    .font(MochiFont.body(10, weight: .heavy))
                    .foregroundStyle(theme.primaryInk)
                    .padding(EdgeInsets(top: 3, leading: 9, bottom: 3, trailing: 9))
                    .background(theme.primary, in: Capsule())
            }
        }
        .padding(EdgeInsets(top: 11, leading: 13, bottom: 11, trailing: 13))
        .background(theme.surface2, in: RoundedRectangle(cornerRadius: MochiRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: MochiRadius.md)
                .stroke(theme.line, lineWidth: 1.5)
        )
    }

    private var flavorCard: some View {
        MochiCard(padding: EdgeInsets(top: 14, leading: 15, bottom: 16, trailing: 15)) {
            VStack(alignment: .leading, spacing: 11) {
                MochiEyebrow(text: "Flavor")
                HStack(spacing: 10) {
                    ForEach(viewModel.flavors) { flavor in
                        let isSelected = flavor.id == viewModel.selectedFlavorId
                        Button {
                            Haptics.selection()
                            viewModel.trigger(.selectFlavor(flavor.id))
                        } label: {
                            Circle()
                                .fill(flavor.color)
                                .frame(width: 36, height: 36)
                                .overlay(Circle().stroke(theme.surface, lineWidth: 2))
                                .background(
                                    Circle()
                                        .stroke(isSelected ? theme.primary : theme.line, lineWidth: isSelected ? 2.5 : 1.5)
                                        .padding(-2.5)
                                )
                                .scaleEffect(isSelected ? 1.06 : 1)
                        }
                        .buttonStyle(SquishButtonStyle())
                        .accessibilityLabel("\(flavor.id) flavor")
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                }
                .animation(MochiMotion.bounce, value: viewModel.selectedFlavorId)
            }
        }
    }

    private var careCard: some View {
        MochiCard(padding: EdgeInsets(top: 0, leading: 15, bottom: 0, trailing: 15)) {
            VStack(spacing: 0) {
                Button {
                    Haptics.impact(.light)
                    viewModel.trigger(.bedtimeTapped)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Bedtime")
                                .font(MochiFont.body(13, weight: .heavy))
                                .foregroundStyle(theme.ink)
                            Text("Mochi sleeps · nudges pause")
                                .font(MochiFont.body(11, weight: .bold))
                                .foregroundStyle(theme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(viewModel.bedtimeText)
                            .font(MochiFont.display(13, weight: .medium))
                            .foregroundStyle(theme.primaryText)
                            .padding(EdgeInsets(top: 6, leading: 11, bottom: 6, trailing: 11))
                            .background(theme.primarySoft, in: Capsule())
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                MochiDashedDivider()
                MochiToggleRow(
                    title: "Morning rundown",
                    subtitle: "A little hello each morning",
                    isOn: viewModel.collectBinding(for: \.morningRundown, action: { .setMorningRundown($0) })
                )
                .padding(.vertical, 13)
                MochiDashedDivider()
                MochiToggleRow(
                    title: "Sound",
                    subtitle: viewModel.soundEnabled ? "Cute noises on" : "Off for now",
                    isOn: viewModel.collectBinding(for: \.soundEnabled, action: { .setSoundEnabled($0) })
                )
                .padding(.vertical, 13)
            }
        }
    }

    private var navigationRows: some View {
        VStack(spacing: 8) {
            MochiListRow(title: "Streaks & stats", subtitle: "Your gentle momentum") {
                viewModel.trigger(.statsTapped)
            }
            MochiListRow(title: "Notifications", subtitle: viewModel.notificationsSub) {
                viewModel.trigger(.notificationsTapped)
            }
            MochiListRow(title: "Apple Reminders", subtitle: viewModel.remindersSub) {
                viewModel.trigger(.remindersTapped)
            }
            MochiListRow(title: "Vacation mode", subtitle: viewModel.vacationSub) {
                viewModel.trigger(.vacationTapped)
            }
            MochiListRow(title: "Manage lists", subtitle: viewModel.listsSub) {
                viewModel.trigger(.manageListsTapped)
            }
        }
    }

    private var accountRows: some View {
        VStack(spacing: 8) {
            MochiListRow(title: "Manage subscription", subtitle: viewModel.subscriptionSub) {
                openURL(MochiLinks.manageSubscriptions)
            }
            MochiListRow(
                title: "Restore purchases",
                onTap: { viewModel.trigger(.restoreTapped) },
                right: {
                    if viewModel.isRestoring {
                        ProgressView().controlSize(.small).tint(theme.muted)
                    } else {
                        MochiRowChevron()
                    }
                }
            )
            MochiListRow(title: "Sign out") {
                viewModel.trigger(.signOutTapped)
            }
            MochiListRow(
                title: "Delete account",
                subtitle: "Permanently erase your data",
                isDanger: true
            ) {
                viewModel.trigger(.deleteAccountTapped)
            }
        }
    }

    private var legalRows: some View {
        VStack(spacing: 8) {
            MochiListRow(title: "Help & support", subtitle: "hello@mochibuddy.app") {
                openURL(MochiLinks.support)
            }
            MochiListRow(title: "Privacy Policy") {
                openURL(MochiLinks.privacyPolicy)
            }
            MochiListRow(title: "Terms of Use (EULA)") {
                openURL(MochiLinks.termsOfUse)
            }
        }
    }
}
