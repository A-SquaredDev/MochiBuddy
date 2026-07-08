//
//  ReminderSettingsView.swift
//  MochiBuddy
//

import SwiftUI

struct ReminderSettingsView: View {
    @State var viewModel: StateViewModel<
        ReminderSettingsBehavior.UIState,
        ReminderSettingsBehavior.ViewAction
    >
    let router: any YouRouting

    @Environment(\.mochiTheme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ScreenTopBar(
                    title: "Apple Reminders",
                    subtitle: "Keep everything in one place",
                    onBack: { router.navigateBack() }
                )

                switch viewModel.status {
                case .loading:
                    ProgressView()
                        .tint(theme.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)

                case .disconnected:
                    primerCard

                case .systemDenied:
                    deniedCard

                case .connected:
                    connectionCard
                    MochiEyebrow(text: "Lists to import")
                    VStack(spacing: 8) {
                        ForEach(viewModel.lists) { list in
                            MochiListRow(
                                icon: nil,
                                title: list.name,
                                subtitle: list.countText,
                                right: {
                                    MochiToggle(isOn: Binding(
                                        get: { list.isSyncing },
                                        set: { viewModel.trigger(.setListSyncing(id: list.id, isOn: $0)) }
                                    ))
                                }
                            )
                        }
                    }
                    HStack(spacing: 7) {
                        Text("🔒")
                        Text("Checking one off in Mochi marks it done in Reminders too.")
                            .font(MochiFont.body(11, weight: .bold))
                            .foregroundStyle(theme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 24, trailing: 18))
        }
        .background(theme.bg)
        .onLoad { viewModel.trigger(.load) }
    }

    private var connectionCard: some View {
        MochiCard {
            HStack(spacing: 12) {
                Text("🍎")
                    .font(.system(size: 20))
                    .frame(width: 40, height: 40)
                    .background(theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Connected")
                        .font(MochiFont.display(13.5, weight: .semibold))
                        .foregroundStyle(theme.ink)
                    Text(viewModel.syncingCount == 0
                         ? "Pick lists below to start syncing"
                         : "\(viewModel.syncingCount) list\(viewModel.syncingCount == 1 ? "" : "s") syncing")
                        .font(MochiFont.body(11, weight: .bold))
                        .foregroundStyle(theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if viewModel.syncingCount > 0 {
                    MochiButton(title: "Stop syncing", variant: .ghost, size: .sm, block: false) {
                        viewModel.trigger(.disconnectTapped)
                    }
                }
            }
        }
    }

    private var primerCard: some View {
        MochiCard(padding: EdgeInsets(top: 20, leading: 16, bottom: 18, trailing: 16)) {
            VStack(spacing: 12) {
                Text("🍎")
                    .font(.system(size: 34))
                Text("Already use Reminders?")
                    .font(MochiFont.display(16, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Text("Bring your lists in so Mochi tracks everything in one place. Checking one off in Mochi marks it done in Apple Reminders too.")
                    .font(MochiFont.body(12, weight: .bold))
                    .foregroundStyle(theme.muted)
                    .multilineTextAlignment(.center)
                MochiButton(title: "Connect Apple Reminders", isLoading: viewModel.isConnecting) {
                    viewModel.trigger(.connectTapped)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var deniedCard: some View {
        MochiCard {
            HStack(spacing: 11) {
                Text("🔒")
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reminders access is off")
                        .font(MochiFont.body(13, weight: .heavy))
                        .foregroundStyle(theme.warn)
                    Text("Allow full access to Reminders in Settings to sync your lists.")
                        .font(MochiFont.body(11, weight: .bold))
                        .foregroundStyle(theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                MochiButton(title: "Open", variant: .ghost, size: .sm, block: false) {
                    openURL(MochiLinks.systemSettings)
                }
            }
        }
    }
}
