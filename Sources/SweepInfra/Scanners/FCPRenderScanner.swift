import Foundation
import SweepCore

/// Finds `Render Files` directories inside top-level `*.fcpbundle` libraries in
/// `~/Movies`. `FileManager` reads package directories like any other folder,
/// so no special "descend into package" handling is needed.
public struct FCPRenderScanner: CategoryScanner, Sendable {
    public let category: CleanCategory

    public init(category: CleanCategory) {
        self.category = category
    }

    public func scan() async -> [ScanItem] {
        FSHelpers.safely {
            let fm = FileManager.default
            let moviesURL = FSHelpers.expandTilde("~/Movies")
            var isDir = false
            guard FSHelpers.exists(moviesURL, isDirectory: &isDir), isDir else { return [] }
            guard let bundles = try? fm.contentsOfDirectory(
                at: moviesURL, includingPropertiesForKeys: [.isDirectoryKey], options: []
            ) else { return [] }
            var items: [ScanItem] = []
            for bundle in bundles {
                guard bundle.pathExtension.lowercased() == "fcpbundle",
                      FSHelpers.isDirectory(bundle) else { continue }
                let libraryName = bundle.deletingPathExtension().lastPathComponent
                findRenderFiles(in: bundle, depth: 0, libraryName: libraryName, into: &items)
            }
            return items
        }
    }

    private func findRenderFiles(in url: URL, depth: Int, libraryName: String,
                                  into items: inout [ScanItem]) {
        guard depth <= 4 else { return }
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: []
        ) else { return }
        for child in children {
            guard FSHelpers.isDirectory(child) else { continue }
            if child.lastPathComponent == "Render Files" {
                let size = FSHelpers.sizeOf(child)
                if size > 0 {
                    items.append(ScanItem(
                        url: child,
                        displayName: "\(libraryName) — Render Files",
                        sizeBytes: size,
                        categoryID: category.id,
                        risk: category.risk,
                        lastModified: FSHelpers.lastModified(of: child),
                    isCloudManaged: FSHelpers.isCloudManaged(child)
                ))
                }
                continue
            }
            findRenderFiles(in: child, depth: depth + 1, libraryName: libraryName, into: &items)
        }
    }
}
