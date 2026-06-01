//
//  DownloadPreflight.swift
//  Voco
//
//  Pre-download checks for network type and storage capacity.
//  Used by OnboardingView and ModelCatalogView before model downloads.
//

import Foundation
import Network
import OSLog

private let log = Logger(subsystem: "com.zanishlabs.Voco", category: "preflight")

/// Result of a pre-download check.
enum PreflightResult: Equatable, Sendable {
    /// All clear — proceed with download.
    case proceed
    /// User should be warned about cellular data usage.
    case cellularWarning(bytes: Int64)
    /// Insufficient free storage to download the model safely.
    case insufficientStorage(needed: Int64, available: Int64)
}

/// Stateless pre-download checks for network and storage.
enum DownloadPreflight {

    /// Checks cellular connectivity and free storage for a model of the given size.
    /// Returns `.proceed` if both pass, or a warning result.
    static func check(modelSizeBytes: Int64) async -> PreflightResult {
        // 1. Check network type
        let path = await currentPath()
        if path.isExpensive {
            return .cellularWarning(bytes: modelSizeBytes)
        }

        // 2. Check storage: need ~2× model size for download + temp + overhead
        let required = modelSizeBytes * 2
        let available = freeStorage()
        if available < required {
            return .insufficientStorage(needed: required, available: available)
        }

        return .proceed
    }

    // MARK: - Private

    private static func currentPath() async -> NWPath {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.resume(returning: path)
                monitor.cancel()
            }
            monitor.start(queue: .global())
        }
    }

    private static func freeStorage() -> Int64 {
        guard let docURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return 0
        }
        do {
            let values = try docURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        } catch {
            log.error("Failed to read free storage: \(error)")
            return 0
        }
    }
}
