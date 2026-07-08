//
//  VacationView.swift
//  MochiBuddy
//

import SwiftUI

struct VacationView: View {
    @State var viewModel: StateViewModel<
        VacationBehavior.UIState,
        VacationBehavior.ViewAction
    >
    let router: any YouRouting

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ScreenTopBar(
                    title: "Vacation mode",
                    subtitle: "Rest easy — Mochi's got you",
                    onBack: { router.navigateBack() }
                )

                MochiCard(padding: EdgeInsets(top: 18, leading: 15, bottom: 16, trailing: 15)) {
                    VStack(spacing: 6) {
                        MochiPetView(mood: .content, size: 130, squishOnTap: false)
                            .overlay(alignment: .topTrailing) {
                                Text("💤")
                                    .font(.system(size: 22))
                                    .offset(x: 4, y: 2)
                            }
                        Text(viewModel.isOn ? "Nudges are paused" : "Need a breather?")
                            .font(MochiFont.display(15, weight: .semibold))
                            .foregroundStyle(theme.ink)
                        Text("Stress won't build while you're away. Your tasks stay exactly as they are.")
                            .font(MochiFont.body(11.5, weight: .bold))
                            .foregroundStyle(theme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }

                MochiCard(padding: EdgeInsets(top: 0, leading: 15, bottom: 0, trailing: 15)) {
                    VStack(spacing: 0) {
                        MochiToggleRow(
                            title: "Vacation mode",
                            subtitle: viewModel.toggleSub,
                            isOn: viewModel.collectBinding(for: \.isOn, action: { .setVacation($0) })
                        )
                        .padding(.vertical, 13)
                        if viewModel.isOn {
                            MochiDashedDivider()
                            MochiToggleRow(
                                title: "Auto-resume",
                                subtitle: "Pick up where you left off",
                                isOn: viewModel.collectBinding(for: \.autoResume, action: { .setAutoResume($0) })
                            )
                            .padding(.vertical, 13)
                            if viewModel.autoResume {
                                MochiDashedDivider()
                                DatePicker(
                                    "Back on",
                                    selection: viewModel.collectBinding(for: \.resumeDate, action: { .resumeDateChanged($0) }),
                                    in: viewModel.minimumResumeDate...,
                                    displayedComponents: .date
                                )
                                .font(MochiFont.body(13, weight: .heavy))
                                .foregroundStyle(theme.ink)
                                .tint(theme.primary)
                                .padding(.vertical, 8)
                                .colorScheme(theme.isDark ? .dark : .light)
                            }
                        }
                    }
                }

                if viewModel.isOn {
                    MochiButton(title: "Turn off & catch up", variant: .ghost) {
                        viewModel.trigger(.turnOffTapped)
                    }
                }
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 24, trailing: 18))
        }
        .background(theme.bg)
        .animation(MochiMotion.soft, value: viewModel.isOn)
        .animation(MochiMotion.soft, value: viewModel.autoResume)
        .onLoad { viewModel.trigger(.load) }
    }
}
