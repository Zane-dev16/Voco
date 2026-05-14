//
//  DownloadState.swift
//  Voco
//
//  Created by Irell Zane on 14/05/2026.
//

import Foundation

enum DownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case processing
    case downloaded
    case failed(String)

    var isActive: Bool {
        if case .downloading = self { return true }
        return false
    }
}
