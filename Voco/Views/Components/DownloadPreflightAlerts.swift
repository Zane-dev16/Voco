//
//  DownloadPreflightAlerts.swift
//  Voco
//
//  Shared cellular/storage confirmation alerts for model downloads.
//  Used by ModelCatalogView and OnboardingView (S7-24 dedup).
//

import SwiftUI

struct DownloadPreflightAlerts: ViewModifier {
    let model: TranslationModel
    @Binding var showCellularWarning: Bool
    @Binding var showStorageWarning: Bool
    /// Starts the download after the user accepted a warning.
    /// Cellular confirmations revalidate storage only (the fatal constraint);
    /// explicit storage overrides go straight through.
    let onConfirmedDownload: () -> Void
    /// Optional cleanup when the user cancels a warning (e.g. reset busy state).
    var onCancelWarning: (() -> Void)? = nil

    func body(content: Content) -> some View {
        content
            .alert("Download over cellular?", isPresented: $showCellularWarning) {
                Button("Download Anyway") { confirmIgnoringNetwork() }
                Button("Cancel", role: .cancel) { onCancelWarning?() }
            } message: {
                Text("This model is \(model.formattedSize). Downloading over cellular may use a significant amount of data.")
            }
            .alert("Insufficient Storage", isPresented: $showStorageWarning) {
                Button("Try Anyway") { onConfirmedDownload() }
                Button("Cancel", role: .cancel) { onCancelWarning?() }
            } message: {
                Text("This model requires about \(ByteCountFormatter.string(fromByteCount: model.fileSizeBytes * 2, countStyle: .file)) of free space.")
            }
    }

    /// User already accepted the network condition — revalidate only storage,
    /// since free space may have moved while the warning was up.
    private func confirmIgnoringNetwork() {
        Task {
            let result = DownloadPreflight.checkStorage(modelSizeBytes: model.fileSizeBytes)
            await MainActor.run {
                if result == .proceed {
                    onConfirmedDownload()
                } else {
                    showStorageWarning = true
                }
            }
        }
    }
}

extension View {
    func downloadPreflightAlerts(
        model: TranslationModel,
        showCellularWarning: Binding<Bool>,
        showStorageWarning: Binding<Bool>,
        onConfirmedDownload: @escaping () -> Void,
        onCancelWarning: (() -> Void)? = nil
    ) -> some View {
        modifier(DownloadPreflightAlerts(
            model: model,
            showCellularWarning: showCellularWarning,
            showStorageWarning: showStorageWarning,
            onConfirmedDownload: onConfirmedDownload,
            onCancelWarning: onCancelWarning
        ))
    }
}
