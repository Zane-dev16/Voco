//
//  Log.swift
//  Voco
//
//  Shared structured logging wrapper. Uses OSLog internally;
//  callers just import Foundation — no OSLog import needed.
//

import Foundation
import OSLog

/// Namespaced logging facade. Each static member is a Logger instance
/// pre-configured with the app's subsystem and a fixed category.
enum VocoLog {
    /// General app-level events.
    static let general = Logger(subsystem: "com.zanishlabs.Voco", category: "app")

    /// Model lifecycle events: download, activation, deletion.
    static let models = Logger(subsystem: "com.zanishlabs.Voco", category: "models")

    /// Speech / audio recognition events.
    static let speech = Logger(subsystem: "com.zanishlabs.Voco", category: "speech")

    /// Translation lifecycle and inference events.
    static let translation = Logger(subsystem: "com.zanishlabs.Voco", category: "translation")
}
