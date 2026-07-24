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
                ScreenTopBar(title: "You", subtitle: "Preferences & care for \(viewModel.mochiName)") {
                    if !viewModel.isLapsed {
                        CoinPill(coins: viewModel.coins)
                    }
                }
                identityRow
                if viewModel.isLapsed {
                    wakeMochiCard
                } else {
                    flavorCard
                    careCard
                }
                yourMochiCard
                navigationRows
                MochiEyebrow(text: "Account")
                    .padding(.top, 4)
                accountRows
                MochiEyebrow(text: "About & legal")
                    .padding(.top, 4)
                legalRows
                #if DEBUG
                MochiListRow(title: "Scheduler inspector", subtitle: "DEBUG · forecast vs pending queue") {
                    viewModel.trigger(.devSchedulerTapped)
                }
                .padding(.top, 4)
                #endif
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
            message: { Text("Your tasks, coins and \(viewModel.mochiName) stay safe in the cloud. Sign back in anytime.") }
        )
        .alert(
            "What should \(viewModel.mochiName) call you?",
            isPresented: viewModel.collectBinding(for: \.showNameEditor, action: .cancelEditName),
            actions: {
                TextField(
                    "Your name",
                    text: viewModel.collectBinding(for: \.nameDraft, action: { .nameDraftChanged($0) })
                )
                Button("Save") { viewModel.trigger(.confirmEditName) }
                Button("Cancel", role: .cancel) { viewModel.trigger(.cancelEditName) }
            }
        )
        .sheet(
            isPresented: viewModel.collectBinding(for: \.showMochiRename, action: .cancelRenameMochi)
        ) {
            mochiRenameSheet
                .presentationDetents([.height(240)])
                .presentationDragIndicator(.visible)
        }
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .editBedtime: router.navigateToBedtime()
            case .showStats: router.navigateToStats()
            case .showNotifications: router.navigateToNotifications()
            case .showReminders: router.navigateToAppleReminders()
            case .showVacation: router.navigateToVacation()
            case .showLetters: router.navigateToLetters()
            case .showManageLists: router.navigateToManageLists()
            case .startDeleteFlow: router.navigateToDeleteWarn()
            case .signedOut: router.exitToOnboarding()
            case .wakeMochi: router.wakeMochi()
            #if DEBUG
            case .showDevScheduler: router.navigateToDevScheduler()
            #endif
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
            Button {
                Haptics.impact(.light)
                viewModel.trigger(.editNameTapped)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.muted)
                    .frame(width: 28, height: 28)
                    .background(theme.surface, in: Circle())
                    .overlay(Circle().stroke(theme.line, lineWidth: 1))
            }
            .buttonStyle(SquishButtonStyle())
            .accessibilityLabel("Edit name")
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
                            Text("\(viewModel.mochiName) sleeps · nudges pause")
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

    /// Lapsed replacement for the care/flavor cards: the pet naps, one CTA.
    /// Honest labeling, not a comeback nudge (winback doctrine).
    private var wakeMochiCard: some View {
        MochiCard(padding: EdgeInsets(top: 16, leading: 15, bottom: 16, trailing: 15)) {
            VStack(spacing: 6) {
                MochiPetView(mood: .sleeping, size: 96, petName: viewModel.mochiName)
                Text("\(viewModel.mochiName) is napping")
                    .font(MochiFont.display(14, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Text("Your tasks, coins and streak are safe. Nothing was deleted.")
                    .font(MochiFont.body(11.5, weight: .bold))
                    .foregroundStyle(theme.muted)
                    .multilineTextAlignment(.center)
                MochiButton(title: viewModel.wakeCtaTitle, variant: .primary, size: .md) {
                    viewModel.trigger(.wakeMochiTapped)
                }
                .accessibilityLabel("Wake \(viewModel.mochiName)")
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// "Your Mochi" - name + adoption date. Available in EVERY state,
    /// including lapsed: a rename is a pure text fix and withholding a
    /// text field as resubscribe pressure is manipulation we don't do.
    private var yourMochiCard: some View {
        MochiCard(padding: EdgeInsets(top: 14, leading: 15, bottom: 14, trailing: 15)) {
            VStack(alignment: .leading, spacing: 11) {
                MochiEyebrow(text: "Your Mochi")
                Button {
                    Haptics.impact(.light)
                    viewModel.trigger(.renameMochiTapped)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(viewModel.mochiName)
                                .font(MochiFont.display(13.5, weight: .semibold))
                                .foregroundStyle(theme.ink)
                                .lineLimit(1)
                            if !viewModel.adoptedOnText.isEmpty {
                                Text(viewModel.adoptedOnText)
                                    .font(MochiFont.body(11, weight: .bold))
                                    .foregroundStyle(theme.muted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.muted)
                            .frame(width: 28, height: 28)
                            .background(theme.surface, in: Circle())
                            .overlay(Circle().stroke(theme.line, lineWidth: 1))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rename \(viewModel.mochiName)")
            }
        }
    }

    /// The small rename sheet - same field, same rules as onboarding.
    private var mochiRenameSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("A new name for \(viewModel.mochiName)?")
                .font(MochiFont.display(16, weight: .semibold))
                .foregroundStyle(theme.ink)
                .padding(.top, 22)
            HStack(spacing: 7) {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.muted)
                PetNameTextField(
                    text: viewModel.collectBinding(for: \.mochiNameDraft, action: { .mochiNameDraftChanged($0) }),
                    textColor: UIColor(theme.ink),
                    onSubmit: { viewModel.trigger(.confirmRenameMochi) }
                )
                .frame(height: 22)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: MochiRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: MochiRadius.md)
                    .stroke(theme.line, lineWidth: 2)
            )
            MochiButton(title: "Save") {
                viewModel.trigger(.confirmRenameMochi)
            }
            MochiTextLink(title: "Cancel") {
                viewModel.trigger(.cancelRenameMochi)
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .background(theme.bg)
    }

    private var navigationRows: some View {
        VStack(spacing: 8) {
            MochiListRow(title: "Streaks & stats", subtitle: "Your gentle momentum") {
                viewModel.trigger(.statsTapped)
            }
            // Lapsed hides what's meaningless with Mochi asleep: nudge
            // prefs, new Reminders imports, vacation mode.
            if !viewModel.isLapsed {
                MochiListRow(title: "Notifications", subtitle: viewModel.notificationsSub) {
                    viewModel.trigger(.notificationsTapped)
                }
                MochiListRow(title: "Apple Reminders", subtitle: viewModel.remindersSub) {
                    viewModel.trigger(.remindersTapped)
                }
                MochiListRow(title: "Vacation mode", subtitle: viewModel.vacationSub) {
                    viewModel.trigger(.vacationTapped)
                }
            }
            // The archive belongs to the Personal Layer; this row is its
            // temporary home until the Journal tab (Feature 6) takes over.
            // Readable in every state incl. lapsed - the letters are theirs.
            MochiListRow(title: "\(viewModel.mochiName)'s letters", subtitle: "The Sunday archive") {
                viewModel.trigger(.lettersTapped)
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
