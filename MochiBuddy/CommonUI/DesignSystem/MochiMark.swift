//
//  MochiMark.swift
//  MochiBuddy
//
//  The flat Mochi brand mark: a one-color glyph (the `mochi-mark` template
//  asset - a blob with the eyes and smile knocked out) tinted to the current
//  tone. Use where a compact brand icon is wanted and the live MochiPetView
//  would be too heavy: the restore card, paywall hooks, the delete-account
//  companion row, the letter-card signature.
//

import SwiftUI

struct MochiMark: View {
    var size: CGFloat = 20
    /// Glyph tint; defaults to the flavor's primary text tone.
    var color: Color? = nil

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        Image("mochi-mark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(color ?? theme.primaryText)
            .accessibilityHidden(true)
    }
}
