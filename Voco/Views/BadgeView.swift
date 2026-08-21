//
//  BadgeView.swift
//  Voco
//
//  Shared badge component used across model catalog, settings, and onboarding.
//
//  Accessibility notes:
//  - Status color is decorative reinforcement only: text is rendered with the
//    adaptive primary color (≥ 7:1 contrast on the light tint in light/dark
//    mode, WCAG AA for caption-size text), while the tinted capsule background
//    plus border carry the hue.
//  - The badge is a single accessibility element whose label is the badge text,
//    so VoiceOver reads "Recommended" instead of an unstyled fragment.
//

import SwiftUI

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .overlay(
                Capsule()
                    .strokeBorder(color.opacity(0.55), lineWidth: 1)
            )
            .clipShape(Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: text))
    }
}
