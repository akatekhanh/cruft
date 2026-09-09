import Foundation
import SweepCore

/// Regular files at or above `minBytes`, found under `roots` up to `maxDepth`
/// levels deep. Skips hidden directories and anything under `~/Library`.
/// Every found item is `.risky` regardless of the category's declared risk,
/// because these are always the user's own files.
public struct LargeFilesScanner: CategoryScanner, Sendable {
    public let category: CleanCategory
    public let roots: [String]
    public let minBytes: Int64
    public let maxDepth: Int

    public init(category: CleanCategory, roots: [String],
                minBytes: Int64 = 500 * 1024 * 1024, maxDepth: Int = 3) {
        self.category = category
        self.roots = roots
        self.minBytes = minBytes
        self.maxDepth = maxDepth
    }

    public func scan() async -> [ScanItem] {
        FSHelpers.safely {
            let libraryPath = FSHelpers.expandTilde("~/Library").path
            var items: [ScanItem] = []
            for root in roots {
                let rootURL = FSHelpers.expandTilde(root)
                var isDir = false
                guard FSHelpers.exists(rootURL, isDirectory: &isDir), isDir else { continue }
                walk(rootURL, depth: 0, libraryPath: libraryPath, into: &items)
            }
            return items
        }
    }

    private func walk(_ url: URL, depth: Int, libraryPath: String, into items: inout [ScanItem]) {
        if depth > maxDepth { return }
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey],
            options: []
        ) else { return }
        for child in children {
            let name = child.lastPathComponent
            if name.hasPrefix(".") { continue }
            if child.path == libraryPath || child.path.hasPrefix(libraryPath + "/") { continue }
            if FSHelpers.isDirectory(child) {
                walk(child, depth: depth + 1, libraryPath: libraryPath, into: &items)
            } else if FSHelpers.isRegularFile(child) {
                let size = FSHelpers.sizeOf(child)
                guard size >= minBytes else { continue }
                items.append(ScanItem(
                    url: child,
                    displayName: name,
                    sizeBytes: size,
                    categoryID: category.id,
                    risk: .risky,
                    lastModified: FSHelpers.lastModified(of: child)
                ))
            }
        }
    }
}
