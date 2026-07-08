//
//  NotificationPrefsView.swift
//  MochiBuddy
//

import SwiftUI

struct NotificationPrefsView: View {
    @State var viewModel: StateViewModel<
        NotificationPrefsBehavior.UIState,
        NotificationPrefsBehavior.ViewAction
    >
    let router: any YouRouting

    @Environment(\.mochiTheme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ScreenTopBar(
                    title: "Notifications",
                    subtitle: "Gentle nudges, never nags",
                    onBack: { router.navigateBack() }
                )

                if viewModel.systemDenied {
                    deniedBanner
                }

                MochiEyebrow(text: "How chatty should Mochi be?")
                levelSelector

                MochiCard(padding: EdgeInsets(top: 0, leading: 15, bottom: 0, trailing: 15)) {
                    VStack(spacing: 0) {
                        MochiToggleRow(
                            title: "Task reminders",
                            subtitle: "A soft tap when something's due",
                            isOn: viewModel.collectBinding(for: \.taskReminders, action: { .setTaskReminders($0) })
                        )
                        .padding(.vertical, 13)
                        MochiDashedDivider()
                        MochiToggleRow(
                            title: "Morning rundown",
                            subtitle: "The day ahead, once each morning",
                            isOn: viewModel.collectBinding(for: \.morningRundown, action: { .setMorningRundown($0) })
                        )
                        .padding(.vertical, 13)
                        MochiDashedDivider()
                        MochiToggleRow(
                            title: "Mochi's mood dips",
                            subtitle: "Only when it really needs you",
                            isOn: viewModel.collectBinding(for: \.moodDips, action: { .setMoodDips($0) })
                        )
                        .padding(.vertical, 13)
                        MochiDashedDivider()
                        MochiToggleRow(
                            title: "Silence during bedtime",
                            subtitle: viewModel.bedtimeSilenceSub,
                            isOn: viewModel.collectBinding(for: \.bedtimeSilence, action: { .setBedtimeSilence($0) })
                        )
                        .padding(.vertical, 13)
                    }
                }

                HStack(spacing: 8) {
                    Text("🌙")
                    Text("Reminders are capped so Mochi never floods your lock screen.")
                        .font(MochiFont.body(11, weight: .bold))
                        .foregroundStyle(theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 24, trailing: 18))
        }
        .background(theme.bg)
        .onLoad { viewModel.trigger(.load) }
    }

    private var levelSelector: some View {
        HStack(spacing: 4) {
            ForEach(viewModel.levelOptions) { option in
                let isOn = option.id == viewModel.selectedLevelId
                Button {
                    Haptics.selection()
                    viewModel.trigger(.selectLevel(option.id))
                } label: {
                    Text(option.label)
                        .font(MochiFont.display(12.5, weight: .medium))
                        .foregroundStyle(isOn ? theme.primaryInk : theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(isOn ? theme.primary : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(theme.surface2, in: Capsule())
        .overlay(Capsule().stroke(theme.line, lineWidth: 1.5))
        .animation(MochiMotion.soft, value: viewModel.selectedLevelId)
    }

    private var deniedBanner: some View {
        MochiCard(padding: EdgeInsets(top: 13, leading: 15, bottom: 13, trailing: 15)) {
            HStack(spacing: 11) {
                Text("🔕")
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications are off in Settings")
                        .font(MochiFont.body(13, weight: .heavy))
                        .foregroundStyle(theme.warn)
                    Text("Mochi can't nudge you until they're allowed again.")
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
