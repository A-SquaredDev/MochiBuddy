//
//  BedtimeSettingsView.swift
//  MochiBuddy
//

import SwiftUI

struct BedtimeSettingsView: View {
    @State var viewModel: StateViewModel<
        BedtimeSettingsBehavior.UIState,
        BedtimeSettingsBehavior.ViewAction
    >
    let router: any YouRouting

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ScreenTopBar(
                    title: "Bedtime",
                    subtitle: "Mochi sleeps · nudges pause",
                    onBack: { router.navigateBack() }
                )

                MochiCard(padding: EdgeInsets(top: 18, leading: 15, bottom: 16, trailing: 15)) {
                    VStack(spacing: 14) {
                        MochiPetView(mood: .tired, size: 110, squishOnTap: false)
                            .overlay(alignment: .topTrailing) {
                                Text("🌙")
                                    .font(.system(size: 22))
                                    .offset(x: 8, y: -8)
                            }
                        Text("Mochi rests while you do — no anxious pings at night, and a friendly rundown when you both wake up.")
                            .font(MochiFont.body(12, weight: .bold))
                            .foregroundStyle(theme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }

                HStack(spacing: 10) {
                    TimePill(
                        label: "Bedtime",
                        time: viewModel.bedtimeText,
                        isActive: viewModel.editing == .bedtime
                    ) {
                        viewModel.trigger(.bedtimeTapped)
                    }
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.muted)
                    TimePill(
                        label: "Wake up",
                        time: viewModel.wakeText,
                        isActive: viewModel.editing == .wake
                    ) {
                        viewModel.trigger(.wakeTapped)
                    }
                }

                if viewModel.editing != .none {
                    DatePicker(
                        "",
                        selection: viewModel.editing == .bedtime
                            ? viewModel.collectBinding(for: \.bedtimeDate, action: { .bedtimeChanged($0) })
                            : viewModel.collectBinding(for: \.wakeDate, action: { .wakeChanged($0) }),
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(height: 130)
                    .clipped()
                    .colorScheme(theme.isDark ? .dark : .light)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Text("Changes save automatically.")
                    .font(MochiFont.body(11, weight: .bold))
                    .foregroundStyle(theme.muted)
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 24, trailing: 18))
        }
        .background(theme.bg)
        .animation(MochiMotion.soft, value: viewModel.editing)
        .onLoad { viewModel.trigger(.load) }
    }
}
