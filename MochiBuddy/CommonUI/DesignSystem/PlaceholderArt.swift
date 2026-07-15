//
//  PlaceholderArt.swift
//  MochiBuddy
//
//  DESIGN NOTE: Stand-ins for final illustrated art from the content team
//  (treat art, the Mochi brand mark, paywall feature art). Search the repo
//  for "DESIGN NOTE" to find every slot that still needs a real asset.
//

import SwiftUI

/// A deliberately obvious "art goes here" tile: a photo glyph inside a
/// dashed frame, so pending assets are unmissable in review builds.
///
/// DESIGN NOTE: every use of this view must be replaced with a
/// content-team asset before release.
struct PlaceholderArtIcon: View {
    var size: CGFloat = 24

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        Image(systemName: "photo")
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(theme.muted)
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28)
                    .stroke(
                        theme.muted.opacity(0.6),
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                    )
            )
            .accessibilityHidden(true)
    }
}

enum PlaceholderArt {
    /// SF Symbol name for placeholder art in string-based icon pipelines
    /// (MochiListRow, paywall hooks). DESIGN NOTE: rows passing this still
    /// need a content-team asset.
    static let symbol = "photo"
}
