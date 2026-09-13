import Foundation
import CruftCore

/// Merges several scanners that feed one category (e.g. AI model stores, where
/// Hugging Face wants per-model children but Ollama's blob store is one opaque
/// unit). All child scanners must be built with the same category.
public struct CompositeScanner: CategoryScanner, Sendable {
    public let category: CleanCategory
    private let scanners: [CategoryScanner]

    public init(category: CleanCategory, scanners: [CategoryScanner]) {
        self.category = category
        self.scanners = scanners
    }

    public func scan() async -> [ScanItem] {
        var items: [ScanItem] = []
        for scanner in scanners {
            items += await scanner.scan()
        }
        return items
    }
}
