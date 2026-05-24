//
//  EnvironmentKeys.swift
//  Voco
//

import SwiftUI

struct LifecycleManagerKey: EnvironmentKey {
    static let defaultValue = ModelLifecycleManager()
}

struct DownloadManagerKey: EnvironmentKey {
    static let defaultValue = ModelManagerService()
}

extension EnvironmentValues {
    var lifecycleManager: ModelLifecycleManager {
        get { self[LifecycleManagerKey.self] }
        set { self[LifecycleManagerKey.self] = newValue }
    }

    var downloadManager: ModelManagerService {
        get { self[DownloadManagerKey.self] }
        set { self[DownloadManagerKey.self] = newValue }
    }
}
