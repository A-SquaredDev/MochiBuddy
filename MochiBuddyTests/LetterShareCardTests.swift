//
//  LetterShareCardTests.swift
//  MochiBuddyTests
//
//  The share card must render REAL pixels through ImageRenderer - the
//  share sheet's payload is whatever this produces, and a silent nil or
//  blank render would ship an empty postcard. (The share sheet itself is
//  UIKit's; what we own is the image handed to it.)
//

import SwiftUI
import Testing
@testable import MochiBuddy

@Suite("Letters · share card")
@MainActor
struct LetterShareCardTests {

    @Test("the card renders a non-empty, non-uniform image at share scale")
    func rendersRealPixels() throws {
        let card = LetterShareCard(
            letterText: "Hey. It's Nori.\n\nThis week was heavy. Nori stayed close.\n\nFrom Nori",
            petName: "Nori",
            adoptionLine: "With Nori since July 2026",
            weekTitle: "Week of July 13",
            theme: .sesame
        )
        let renderer = ImageRenderer(content: card.environment(\.mochiTheme, MochiTheme.sesame))
        renderer.scale = 3
        let image = try #require(renderer.uiImage, "the renderer must produce an image")

        #expect(image.size.width >= 400, "card width is fixed at 420pt")
        #expect(image.size.height >= 100, "text content must give the card real height")

        // Non-uniform: sample a handful of pixels and demand at least two
        // distinct colors - a blank or single-color render is a failure
        // even when non-nil.
        let cgImage = try #require(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Dense grid: 50x50 samples across the whole card. Sparse points
        // can all land on background between text lines; a real render has
        // dozens of distinct colors (text, pet, dashed placeholder).
        var seen = Set<[UInt8]>()
        for gridY in 0..<50 {
            for gridX in 0..<50 {
                let x = min(width - 1, (gridX * width) / 50)
                let y = min(height - 1, (gridY * height) / 50)
                let offset = (y * width + x) * 4
                seen.insert(Array(pixels[offset..<offset + 4]))
            }
        }
        #expect(seen.count >= 10, "got \(seen.count) distinct colors - a near-uniform image means the card drew nothing")
    }
}
