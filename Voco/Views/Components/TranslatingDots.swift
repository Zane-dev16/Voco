//
//  TranslatingDots.swift
//  Voco
//
//  Five-pulse "translating in progress" indicator.
//

import SwiftUI

struct TranslatingDots: View {
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<5) { dotIndex in
                PulsingDot(delay: Double(dotIndex) * 0.1)
            }
        }
    }
}

private struct PulsingDot: View {
    let delay: Double
    @State private var isActive = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(Color.blue)
            .frame(width: 8, height: 8)
            .opacity(isActive ? 1.0 : 0.25)
            .offset(y: isActive ? -6 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .easeInOut(duration: 0.45)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    isActive = true
                }
            }
            .onDisappear {
                // Reset the animation state so the repeatForever animation is
                // released when the dots leave the hierarchy instead of
                // continuing to tick off-screen.
                isActive = false
            }
    }
}
