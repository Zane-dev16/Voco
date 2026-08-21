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
        // 1. Check network type. If the path monitor doesn't report within the
        //    timeout, assume Wi-Fi rather than hanging the preflight indefinitely.
        let isExpensive = await currentPathIsExpensive()
        if isExpensive {
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

    private static func currentPathIsExpensive(timeoutSeconds: Double = 2) async -> Bool {
        await withCheckedContinuation { continuation in
            // Guarantees exactly one resume between the monitor callback and
            // the timeout fallback.
            let didResume = OSAllocatedUnfairLock(initialState: false)
            // @Sendable closure (not a local func): Swift 6 treats captured
            // local funcs as non-Sendable values even when declared @Sendable.
            let resumeOnce: @Sendable (Bool) -> Void = { expensive in
                let won = didResume.withLock { flag -> Bool in
                    if flag { return false }
                    flag = true
                    return true
                }
                guard won else { return }
                continuation.resume(returning: expensive)
            }
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                resumeOnce(path.isExpensive)
                monitor.cancel()
            }
            monitor.start(queue: .global())

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds) {
                // Timeout: treat as non-expensive so a flaky path update never
                // blocks the download flow forever.
                resumeOnce(false)
                monitor.cancel()
            }
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
