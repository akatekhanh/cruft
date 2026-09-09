import Foundation
import SweepCore

/// Each direct child of each existing root becomes one `ScanItem`.
/// Skips hidden entries (name starts with ".") and zero-byte items.
public struct DirectoryChildrenScanner: CategoryScanner, Sendable {
    public let category: CleanCategory
    public let roots: [String]
    /// Children whose name *contains* any of these substrings are skipped
    /// (used to avoid double-counting caches that belong to a more specific category).
    public let excludedChildNameContains: [String]
    /// Optional friendlier display name for a specific child name.
    public let displayNameMap: [String: String]

    public init(category: CleanCategory, roots: [String],
                excludedChildNameContains: [String] = [],
                displayNameMap: [String: String] = [:]) {
        self.category = category
        self.roots = roots
        self.excludedChildNameContains = excludedChildNameContains
        self.displayNameMap = displayNameMap
    }

    public func scan() async -> [ScanItem] {
        FSHelpers.safely {
            let fm = FileManager.default
            var items: [ScanItem] = []
            for root in roots {
                let rootURL = FSHelpers.expandTilde(root)
                var isDir = false
                guard FSHelpers.exists(rootURL, isDirectory: &isDir), isDir else { continue }
                guard let children = try? fm.contentsOfDirectory(
                    at: rootURL, includingPropertiesForKeys: [.contentModificationDateKey],
                    options: []
                ) else { continue }
                for child in children {
                    let name = child.lastPathComponent
                    if name.hasPrefix(".") { continue }
                    if excludedChildNameContains.contains(where: { name.contains($0) }) { continue }
                    let size = FSHelpers.sizeOf(child)
                    if size <= 0 { continue }
                    items.append(ScanItem(
                        url: child,
                        displayName: displayNameMap[name] ?? name,
                        sizeBytes: size,
                        categoryID: category.id,
                        risk: category.risk,
                        lastModified: FSHelpers.lastModified(of: child)
                    ))
                }
            }
            return items
        }
    }
}
