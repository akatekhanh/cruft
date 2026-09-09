import Foundation
import SweepCore

/// Shared, read-only filesystem helpers used by every scanner. Never mutates disk,
/// never throws to callers, silently skips entries it cannot read (missing
/// permissions, races, etc. — some paths require Full Disk Access).
enum FSHelpers {

    /// Expands `~` and returns a file URL. Does not check existence.
    static func expandTilde(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    /// Runs `body` and swallows any error, returning an empty result instead.
    /// Every scanner wraps its work in this so a scan never throws or crashes.
    static func safely(_ body: () throws -> [ScanItem]) -> [ScanItem] {
        do { return try body() } catch { return [] }
    }

    /// True if `url` exists; `isDirectory` reports whether it's a directory.
    static func exists(_ url: URL, isDirectory: inout Bool) -> Bool {
        var isDir: ObjCBool = false
        let ok = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        isDirectory = isDir.boolValue
        return ok
    }

    static func lastModified(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    private static func allocatedSize(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(
            forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
        ) else { return 0 }
        if let alloc = values.totalFileAllocatedSize { return Int64(alloc) }
        if let size = values.fileSize { return Int64(size) }
        return 0
    }

    /// Size of `url`: its own allocated size if it's a file, or the recursive sum
    /// of every regular file inside it if it's a directory. Uses
    /// `.totalFileAllocatedSizeKey` with a `.fileSizeKey` fallback, skipping any
    /// entry that can't be read.
    static func sizeOf(_ url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return allocatedSize(of: url)
        }
        var total: Int64 = 0
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }
        for case let child as URL in enumerator {
            guard let values = try? child.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey]
            ) else { continue }
            if values.isDirectory == true { continue }
            if let alloc = values.totalFileAllocatedSize {
                total += Int64(alloc)
            } else if let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
