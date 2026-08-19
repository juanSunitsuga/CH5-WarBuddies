//
//  TermsLegendView.swift
//  RiftboundVisionApp
//
//  Created by Anthony Martin Hasurungan on 19/08/26.
//

import SwiftUI

/// "Terms and their Meanings" — the four table gestures a player has to
/// recognise before anything else on screen means much: Ready,
/// Exhaust/Pay, Recycle a rune, Draw.
///
/// This is new in V3 and it's the reason the header got taller. It sits
/// next to the turn banner rather than in a help sheet because it's for
/// the person who has the app open *while learning the game* — a legend
/// you have to go looking for isn't a legend.
///
/// The glyphs are the reference's own SVGs, added to `Assets.xcassets`
/// with vector representation preserved so they stay crisp at whatever
/// height the header ends up.
struct TermsLegendView: View {
    /// Icon height. The board's "Iconics" sizes (50/80pt) are *type*
    /// sizes; artwork isn't typography, so these are sized to sit on the
    /// same baseline as the 15pt caption underneath, matching the mockup's
    /// proportions.
    private static let glyphHeight: CGFloat = 46

    private struct Term: Identifiable {
        let id = UUID()
        let asset: String
        let caption: String
        /// Read aloud instead of the artwork, which VoiceOver can't
        /// describe on its own.
        let accessibility: String
    }

    private static let terms: [Term] = [
        Term(asset: RiftboundArt.ready,
             caption: "Ready",
             accessibility: "Ready: turn an exhausted card upright again."),
        Term(asset: RiftboundArt.exhaustOrPay,
             caption: "Exhaust/Pay",
             accessibility: "Exhaust or pay: turn a card sideways to spend it."),
        Term(asset: RiftboundArt.recycleARune,
             caption: "Recycle a rune",
             accessibility: "Recycle a rune: send a rune to the trash and take a new one."),
        Term(asset: RiftboundArt.draw,
             caption: "Draw",
             accessibility: "Draw: take the top card of your deck into hand.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Terms and their Meanings")
                .font(RiftboundFont.heading)
                .foregroundStyle(RiftboundPalette.regularText)

            HStack(alignment: .bottom, spacing: 22) {
                ForEach(Self.terms) { term in
                    VStack(spacing: 6) {
                        Image(term.asset)
                            .resizable()
                            .scaledToFit()
                            .frame(height: Self.glyphHeight)
                        Text(term.caption)
                            .font(RiftboundFont.body)
                            .foregroundStyle(RiftboundPalette.regularText)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(term.accessibility)
                }
            }
        }
    }
}

#Preview {
    TermsLegendView()
        .padding()
        .background(RiftboundPalette.mainBackground)
}
