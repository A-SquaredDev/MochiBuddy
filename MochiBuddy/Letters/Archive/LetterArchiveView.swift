//
//  LetterArchiveView.swift
//  MochiBuddy
//

import SwiftUI

struct LetterArchiveView: View {
    @State var viewModel: LetterArchiveViewModel
    let router: any YouRouting

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ScreenTopBar(
                    title: "\(viewModel.petName)'s letters",
                    subtitle: "One every Sunday, yours to keep",
                    onBack: { router.navigateBack() }
                )

                if viewModel.isLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                } else if viewModel.showEmptyState {
                    emptyState
                } else {
                    letterRows
                }
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 24, trailing: 18))
        }
        .background(theme.bg)
        .onLoad { viewModel.trigger(.load) }
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .openLetter(let letter):
                router.navigateToLetter(letter, source: .archive)
            }
        }
    }

    private var letterRows: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.rows) { row in
                Button {
                    viewModel.trigger(.letterTapped(row.id))
                } label: {
                    MochiCard(padding: EdgeInsets(top: 13, leading: 15, bottom: 13, trailing: 15)) {
                        HStack(spacing: 10) {
                            Image(systemName: row.isUnread ? "envelope.badge.fill" : "envelope.open")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(row.isUnread ? theme.primary : theme.muted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .font(MochiFont.body(13.5, weight: .heavy))
                                    .foregroundStyle(theme.ink)
                                Text(row.snippet)
                                    .font(MochiFont.body(11.5, weight: .bold))
                                    .foregroundStyle(theme.muted)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(theme.muted)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    row.isUnread ? "\(row.title), unread letter" : "\(row.title), letter"
                )
            }
        }
    }

    private var emptyState: some View {
        MochiCard(padding: EdgeInsets(top: 22, leading: 18, bottom: 22, trailing: 18)) {
            VStack(spacing: 6) {
                Image(systemName: "envelope")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(theme.muted)
                Text("No letters yet")
                    .font(MochiFont.body(13.5, weight: .heavy))
                    .foregroundStyle(theme.ink)
                Text("\(viewModel.petName) writes every Sunday evening. The first one arrives after your first full week together.")
                    .font(MochiFont.body(11.5, weight: .bold))
                    .foregroundStyle(theme.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
