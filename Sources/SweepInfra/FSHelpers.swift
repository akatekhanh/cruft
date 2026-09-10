import Foundation
import SweepCore

/// Shared, read-only filesystem helpers used by every scanner. Never mutates disk,
/// never throws to callers, silently skips entries it cannot read (missing
/// permissions, races, etc. — some paths require Full Disk Access).
public enum FSHelpers {

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

    /// Last read. macOS keeps this per-file, and a directory's own access date
    /// says little about its contents, so for a directory we take the newest
    /// access date among its immediate children instead.
    static func lastAccessed(of url: URL) -> Date? {
        func accessDate(_ u: URL) -> Date? {
            try? u.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate
        }
        guard isDirectory(url) else { return accessDate(url) }
        let children = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.contentAccessDateKey], options: []
        )) ?? []
        let dates = children.compactMap(accessDate) + [accessDate(url)].compactMap { $0 }
        return dates.max()
    }

    static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
    }

    /// True when the item is managed by iCloud Drive (or another File Provider).
    ///
    /// This changes what deletion *means*: trashing a synced file removes it
    /// from every device signed into that account, not just this Mac. With
    /// "Desktop & Documents Folders" enabled — which macOS offers during setup —
    /// `~/Desktop` and `~/Documents` are entirely File-Provider territory, so
    /// this is not an edge case. Reading these attributes is metadata-only and
    /// never triggers a download of an evicted file.
    public static func isCloudManaged(_ url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey]),
           values.isUbiquitousItem == true {
            return true
        }
        // A file evicted to the cloud is "dataless": it occupies no local blocks
        // and materialises on read. Those are cloud items too, even when the
        // ubiquity flag is not reported for the path we were handed.
        if let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
           values.ubiquitousItemDownloadingStatus != nil {
            return true
        }
        // The path the user sees is not the path the ubiquity API recognises.
        // With "Desktop & Documents Folders" on, ~/Desktop is a firmlink to the
        // real iCloud location, and every ubiquity key above reports nil for it
        // (verified on macOS 26) — only the ~/Library/Mobile Documents path
        // answers true. So fall back to asking whether this path lives under a
        // user folder that iCloud has taken over.
        let path = url.path
        return cloudManagedUserRoots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// `~/Desktop` and/or `~/Documents`, but only the ones iCloud is currently
    /// syncing. iCloud creates the matching folder under `com~apple~CloudDocs`
    /// exactly when that sync is enabled, which makes its presence the reliable
    /// signal. Computed once: this is consulted per scanned file.
    private static let cloudManagedUserRoots: [String] = {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let cloudDocs = home.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs")
        return ["Desktop", "Documents"].compactMap { name in
            fm.fileExists(atPath: cloudDocs.appendingPathComponent(name).path)
                ? home.appendingPathComponent(name).path
                : nil
        }
    }()

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
