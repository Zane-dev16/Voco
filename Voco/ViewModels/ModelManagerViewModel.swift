//
//  ModelManagerViewModel.swift
//  Voco
//
//  Created by Irell Zane on 14/05/2026.
//

import Foundation
import Observation

@Observable
@MainActor
final class ModelManagerViewModel {
    private let modelManager: ModelManagerService

    let availableModels: [TranslationModel] = TranslationModel.availableModels
    var selectedModel: TranslationModel?
    var alertMessage: String?
    var showAlert = false

    init(modelManager: ModelManagerService) {
        self.modelManager = modelManager
    }

    func download(_ model: TranslationModel) {
        modelManager.download(model)
    }

    func cancelDownload(_ model: TranslationModel) {
        modelManager.cancelDownload(for: model.id)
    }

    func deleteModel(_ model: TranslationModel) {
        do {
            try modelManager.deleteModel(model)
        } catch {
            alertMessage = "Failed to delete: \\(error.localizedDescription)"
            showAlert = true
        }
    }

    func state(for model: TranslationModel) -> DownloadState {
        modelManager.downloadStates[model.id] ?? .notDownloaded
    }

    var formattedDiskUsage: String {
        ByteCountFormatter.string(fromByteCount: modelManager.totalDiskUsage(), countStyle: .file)
    }
}
