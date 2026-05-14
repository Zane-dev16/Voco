//
//  RootViewModel.swift
//  Voco
//
//  Created by Irell Zane on 14/05/2026.
//

import SwiftUI

/// Root view model driving the main ContentView.
/// Manages app-level state and navigation.
@Observable
@MainActor
final class RootViewModel {
    // MARK: - State

    /// Current app phase (used for onboarding flow, etc.)
    enum AppPhase {
        case onboarding
        case ready
    }

    var phase: AppPhase = .ready

    // MARK: - Init

    init() {}
}
