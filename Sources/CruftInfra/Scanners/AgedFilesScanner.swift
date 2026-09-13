import Foundation
import CruftCore

/// Top-level entries of `root` whose content modification date is older than
/// `olderThanDays`. Folders count via their recursive size.
public struct AgedFilesScanner: CategoryScanner, Sendable {
    public let category: CleanCategory
    public let root: String
    public let olderThanDays: Int

    public init(category: CleanCategory, root: String, olderThanDays: Int) {
        self.category = category
        self.root = root
        self.olderThanDays = olderThanDays
    }

    public func scan() async -> [ScanItem] {
        FSHelpers.safely {
            let fm = FileManager.default
            let rootURL = FSHelpers.expandTilde(root)
            var isDir = false
            guard FSHelpers.exists(rootURL, isDirectory: &isDir), isDir else { return [] }
            guard let children = try? fm.contentsOfDirectory(
                at: rootURL, includingPropertiesForKeys: [.contentModificationDateKey],
                options: []
            ) else { return [] }
            let cutoff = Calendar.current.date(
                byAdding: .day, value: -olderThanDays, to: Date()
            ) ?? .distantPast
            var items: [ScanItem] = []
            for child in children {
                let name = child.lastPathComponent
                if name.hasPrefix(".") { continue }
                guard let modified = FSHelpers.lastModified(of: child), modified < cutoff else { continue }
                let size = FSHelpers.sizeOf(child)
                if size <= 0 { continue }
                items.append(ScanItem(
                    url: child,
                    displayName: name,
                    sizeBytes: size,
                    categoryID: category.id,
                    risk: category.risk,
                    lastModified: modified,
                    isCloudManaged: FSHelpers.isCloudManaged(child)
                ))
            }
            return items
        }
    }
}
