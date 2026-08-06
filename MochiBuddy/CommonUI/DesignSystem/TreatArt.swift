//
//  TreatArt.swift
//  MochiBuddy
//
//  Final treat-shop illustrations (content-team art, shipped as vector-clean
//  exports in Assets.xcassets). Keyed by TreatCatalog id so a treat's card
//  finds its art by name.
//

import SwiftUI

/// A shop treat's illustration. Assets live in Assets.xcassets keyed by
/// TreatCatalog id (`treat-berry`, `treat-latte`, `treat-dango`,
/// `treat-cupcake`) plus the free `pet-mochi` action.
struct TreatArtIcon: View {
    let asset: String
    var size: CGFloat

    /// Treat card art, keyed by TreatCatalog id: berry / latte / dango / cupcake.
    init(treatId: String, size: CGFloat = 40) {
        self.asset = "treat-\(treatId)"
        self.size = size
    }

    /// The free "Pet Mochi" action art.
    init(petActionSize size: CGFloat = 28) {
        self.asset = "pet-mochi"
        self.size = size
    }

    var body: some View {
        Image(asset)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview("Treat art") {
    HStack(spacing: 12) {
        TreatArtIcon(treatId: "berry")
        TreatArtIcon(treatId: "latte")
        TreatArtIcon(treatId: "dango")
        TreatArtIcon(treatId: "cupcake")
        TreatArtIcon(petActionSize: 40)
    }
    .padding()
    .background(MochiTheme.sesame.bg)
    .environment(\.mochiTheme, .sesame)
}
