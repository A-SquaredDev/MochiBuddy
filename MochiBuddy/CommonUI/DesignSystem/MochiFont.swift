//
//  MochiFont.swift
//  MochiBuddy
//
//  Typography tokens — display = Fredoka (rounded, friendly),
//  body/UI = Nunito (heavy). Both ship as variable fonts in Fonts/.
//

import SwiftUI

enum MochiFont {
    /// Fredoka — headlines, buttons, card titles.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .custom("Fredoka", size: size).weight(weight)
    }

    /// Nunito — body copy, meta text, eyebrows.
    static func body(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .custom("Nunito", size: size).weight(weight)
    }
}
