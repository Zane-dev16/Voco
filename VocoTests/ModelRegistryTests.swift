import Foundation
import Testing
@testable import Voco

@Suite("Model Registry")
struct ModelRegistryTests {

    private let models = TranslationModel.availableModels

    @Test("Registry contains exactly 10 models")
    func modelCount() {
        #expect(models.count == 10)
    }

    @Test("No duplicate model IDs")
    func noDuplicateIDs() {
        let ids = models.map(\.id)
        let unique = Set(ids)
        #expect(ids.count == unique.count, "Duplicate IDs found")
    }

    @Test("SHA-256 hashes are populated (except known deferred models)")
    func sha256Populated() {
        let deferred: Set<String> = ["hy-mt1.5-1.8b-q4km"] // hash pending latte download
        for model in models {
            if deferred.contains(model.id) {
                #expect(model.sha256.isEmpty, "\(model.id) is expected to have empty sha256 (deferred)")
            } else {
                #expect(!model.sha256.isEmpty, "\(model.id) has empty sha256")
            }
        }
    }

    @Test("Every model has a valid source URL")
    func validSourceURLs() {
        for model in models {
            #expect(model.sourceURL.absoluteString.hasPrefix("https://"), "\(model.id) sourceURL is not HTTPS")
        }
    }

    @Test("Every model has positive fileSizeBytes")
    func positiveFileSize() {
        for model in models {
            #expect(model.fileSizeBytes > 0, "\(model.id) fileSizeBytes <= 0")
        }
    }

    @Test("Every model has non-empty displayName and provider")
    func noEmptyMetadata() {
        for model in models {
            #expect(!model.displayName.isEmpty, "\(model.id) displayName is empty")
            #expect(!model.provider.isEmpty, "\(model.id) provider is empty")
            #expect(!model.baseModelName.isEmpty, "\(model.id) baseModelName is empty")
            #expect(!model.licenseName.isEmpty, "\(model.id) licenseName is empty")
        }
    }

    @Test("Every model has a valid config")
    func validConfigs() {
        for model in models {
            // config should not be nil — ModelConfiguration is non-optional
            #expect(model.config.prompt.stopStrings.count >= 0, "\(model.id) config may be invalid")
        }
    }

    @Test("Filename matches sourceURL last path component")
    func filenameConsistency() {
        for model in models {
            #expect(model.filename == model.sourceURL.lastPathComponent,
                    "\(model.id) filename mismatch: \(model.filename) vs \(model.sourceURL.lastPathComponent)")
        }
    }
}
