import Foundation
import SweepCore

/// Each root itself is a single `ScanItem` (used for npm/pip/brew-style caches
/// where the whole directory is "one thing" to the user).
public struct WholeDirectoryScanner: CategoryScanner, Sendable {
    public let category: CleanCategory
    public let roots: [String]
    public let labels: [String]

    public init(category: CleanCategory, roots: [String], labels: [String]) {
        self.category = category
        self.roots = roots
        self.labels = labels
    }

    public func scan() async -> [ScanItem] {
        FSHelpers.safely {
            var items: [ScanItem] = []
            for (index, root) in roots.enumerated() {
                let url = FSHelpers.expandTilde(root)
                var isDir = false
                guard FSHelpers.exists(url, isDirectory: &isDir) else { continue }
                let size = FSHelpers.sizeOf(url)
                if size <= 0 { continue }
                let label = index < labels.count ? labels[index] : url.lastPathComponent
                items.append(ScanItem(
                    url: url,
                    displayName: label,
                    sizeBytes: size,
                    categoryID: category.id,
                    risk: category.risk,
                    lastModified: FSHelpers.lastModified(of: url),
                    lastAccessed: FSHelpers.lastAccessed(of: url)
                ))
            }
            return items
        }
    }
}
