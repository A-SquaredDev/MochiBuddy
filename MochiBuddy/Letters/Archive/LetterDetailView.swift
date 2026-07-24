//
//  LetterDetailView.swift
//  MochiBuddy
//
//  One letter, read in full. Works pushed (archive, with back) or as a
//  sheet (Home envelope / notification tap, with close). Sharing renders
//  the Feature 1-deferred card via ImageRenderer: PRIVATE variant by
//  default; full is a per-share opt-in and rough letters never offer it.
//

import SwiftUI

struct LetterDetailView: View {
    @State var viewModel: LetterDetailViewModel
    /// Nil when pushed (back arrow via router); set when presented as a
    /// sheet (close button).
    var onClose: (() -> Void)?
    var onBack: (() -> Void)?

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ScreenTopBar(
                    title: viewModel.weekTitle,
                    subtitle: viewModel.dateRangeText,
                    onBack: onBack ?? onClose ?? {}
                ) {
                    shareMenu
                }

                letterCard
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 24, trailing: 18))
        }
        .background(theme.bg)
        .onLoad { viewModel.trigger(.load) }
    }

    private var letterCard: some View {
        MochiCard(padding: EdgeInsets(top: 20, leading: 18, bottom: 20, trailing: 18)) {
            VStack(alignment: .leading, spacing: 14) {
                MochiPetView(
                    mood: .content, size: 64, squishOnTap: false,
                    petName: viewModel.petName
                )
                .frame(maxWidth: .infinity)
                Text(viewModel.bodyText)
                    .font(MochiFont.body(14, weight: .bold))
                    .foregroundStyle(theme.ink)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !viewModel.adoptionLine.isEmpty {
                    Text(viewModel.adoptionLine)
                        .font(MochiFont.body(10.5, weight: .heavy))
                        .foregroundStyle(theme.muted)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Letter from \(viewModel.petName). \(viewModel.bodyText)")
    }

    // MARK: - Sharing

    private var shareMenu: some View {
        Menu {
            ShareLink(
                item: renderCard(text: viewModel.letter.privateRenderedText),
                preview: SharePreview(
                    "Letter from \(viewModel.petName)",
                    image: renderCard(text: viewModel.letter.privateRenderedText)
                )
            ) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .simultaneousGesture(TapGesture().onEnded {
                viewModel.trigger(.sharedTapped(variant: "private"))
            })
            if viewModel.offersFullShare {
                ShareLink(
                    item: renderCard(text: viewModel.letter.fullRenderedText),
                    preview: SharePreview(
                        "Letter from \(viewModel.petName)",
                        image: renderCard(text: viewModel.letter.fullRenderedText)
                    )
                ) {
                    Label("Share with task names", systemImage: "square.and.arrow.up.on.square")
                }
                .simultaneousGesture(TapGesture().onEnded {
                    viewModel.trigger(.sharedTapped(variant: "full"))
                })
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(theme.primaryText)
        }
        .accessibilityLabel("Share this letter")
    }

    /// The rendered share card. Private text by default; the full variant
    /// only ever reaches here through the explicit opt-in above.
    private func renderCard(text: String) -> Image {
        let card = LetterShareCard(
            letterText: text,
            petName: viewModel.petName,
            adoptionLine: viewModel.adoptionLine,
            weekTitle: viewModel.weekTitle,
            theme: theme
        )
        // ImageRenderer content gets no app environment - hand the theme
        // through explicitly or the pet and placeholder render default.
        let renderer = ImageRenderer(content: card.environment(\.mochiTheme, theme))
        renderer.scale = 3
        if let image = renderer.uiImage {
            return Image(uiImage: image)
        }
        return Image(systemName: "envelope")
    }
}

/// The shareable postcard (Personal Layer, Feature 3): letter text, the
/// pet pose, the adoption-age line, a small wordmark.
struct LetterShareCard: View {
    let letterText: String
    let petName: String
    let adoptionLine: String
    let weekTitle: String
    let theme: MochiTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(weekTitle)
                    .font(MochiFont.display(15))
                    .foregroundStyle(theme.muted)
                Spacer()
                MochiPetView(mood: .content, size: 52, squishOnTap: false, showsSparkles: false)
            }
            Text(letterText)
                .font(MochiFont.body(15, weight: .bold))
                .foregroundStyle(theme.ink)
                .lineSpacing(5)
            HStack(spacing: 6) {
                if !adoptionLine.isEmpty {
                    Text(adoptionLine)
                        .font(MochiFont.body(11, weight: .heavy))
                        .foregroundStyle(theme.muted)
                }
                Spacer()
                // DESIGN NOTE: brand wordmark pending content-team art.
                PlaceholderArtIcon(size: 16)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(theme.bg)
    }
}
