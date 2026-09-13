import Foundation
import CruftCore

/// Top-level files (not directories) whose name starts with any of `prefixes`
/// (case-insensitive).
public struct NamePatternScanner: CategoryScanner, Sendable {
    public let category: CleanCategory
    public let roots: [String]
    public let prefixes: [String]

    public init(category: CleanCategory, roots: [String], prefixes: [String]) {
        self.category = category
        self.roots = roots
        self.prefixes = prefixes
    }

    public func scan() async -> [ScanItem] {
        FSHelpers.safely {
            let fm = FileManager.default
            let lowerPrefixes = prefixes.map { $0.lowercased() }
            var items: [ScanItem] = []
            for root in roots {
                let rootURL = FSHelpers.expandTilde(root)
                var isDir = false
                guard FSHelpers.exists(rootURL, isDirectory: &isDir), isDir else { continue }
                guard let children = try? fm.contentsOfDirectory(
                    at: rootURL,
                    includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                    options: []
                ) else { continue }
                for child in children {
                    let name = child.lastPathComponent
                    if name.hasPrefix(".") { continue }
                    let lowerName = name.lowercased()
                    guard lowerPrefixes.contains(where: { lowerName.hasPrefix($0) }) else { continue }
                    guard FSHelpers.isRegularFile(child) else { continue }
                    let size = FSHelpers.sizeOf(child)
                    if size <= 0 { continue }
                    items.append(ScanItem(
                        url: child,
                        displayName: name,
                        sizeBytes: size,
                        categoryID: category.id,
                        risk: category.risk,
                        lastModified: FSHelpers.lastModified(of: child),
                    isCloudManaged: FSHelpers.isCloudManaged(child)
                ))
                }
            }
            return items
        }
    }
}
