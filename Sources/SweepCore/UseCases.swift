import Foundation

public struct ScanProgress: Sendable {
    public let finished: Int
    public let total: Int
    public let currentCategoryName: String
    public let bytesFoundSoFar: Int64
    public init(finished: Int, total: Int, currentCategoryName: String, bytesFoundSoFar: Int64) {
        self.finished = finished; self.total = total
        self.currentCategoryName = currentCategoryName; self.bytesFoundSoFar = bytesFoundSoFar
    }
}

/// Scans every category in the role's profile, in order, reporting progress.
public struct ScanUseCase: Sendable {
    private let scanners: [CategoryScanner]
    public init(scanners: [CategoryScanner]) { self.scanners = scanners }

    /// Scanners relevant to a role, in the role's declared order.
    public func scanners(for role: RoleProfile) -> [CategoryScanner] {
        role.categoryIDs.compactMap { id in scanners.first { $0.category.id == id } }
    }

    public func run(for role: RoleProfile,
                    onProgress: @Sendable (ScanProgress) -> Void) async -> [CategoryScanResult] {
        let active = scanners(for: role)
        var results: [CategoryScanResult] = []
        var bytes: Int64 = 0
        for (i, scanner) in active.enumerated() {
            onProgress(ScanProgress(finished: i, total: active.count,
                                    currentCategoryName: scanner.category.name,
                                    bytesFoundSoFar: bytes))
            let items = await scanner.scan()
            let result = CategoryScanResult(category: scanner.category, items: items)
            bytes += result.totalBytes
            if !items.isEmpty { results.append(result) }
        }
        onProgress(ScanProgress(finished: active.count, total: active.count,
                                currentCategoryName: "", bytesFoundSoFar: bytes))
        return results.sorted { $0.totalBytes > $1.totalBytes }
    }
}

/// Cleans the selected items and reports what was freed. Items whose category is
/// owned by a `SpecialCleaner` (e.g. Docker objects) go there — permanently;
/// everything else is moved to Trash (recoverable).
public struct CleanUseCase: Sendable {
    private let trash: TrashService
    private let specials: [SpecialCleaner]
    public init(trash: TrashService, specials: [SpecialCleaner] = []) {
        self.trash = trash
        self.specials = specials
    }

    public func run(items: [ScanItem]) -> CleanReport {
        var freed: Int64 = 0
        var externalBytes: Int64 = 0
        var count = 0
        var failures: [(ScanItem, String)] = []
        for item in items {
            do {
                if let cleaner = specials.first(where: { $0.categoryIDs.contains(item.categoryID) }) {
                    try cleaner.clean(item)
                    externalBytes += item.sizeBytes
                } else {
                    try trash.moveToTrash(item.url)
                }
                freed += item.sizeBytes
                count += 1
            } catch { failures.append((item, error.localizedDescription)) }
        }
        return CleanReport(freedBytes: freed, cleanedCount: count, failures: failures,
                           externallyRemovedBytes: externalBytes)
    }
}

/// Pure selection logic shared by UI and tests.
public enum SelectionPolicy {
    /// Default selection after a scan: `safe` **and** recoverable. Permanent
    /// removals are left unticked even at `safe` risk — a Docker build cache
    /// rebuilds itself, but it never lands in the Trash, and pre-ticking
    /// something with no undo would let the user destroy it without choosing to.
    public static func defaultSelection(in results: [CategoryScanResult]) -> Set<String> {
        Set(quickCleanItems(in: results).map(\.id))
    }

    public static func selectedBytes(in results: [CategoryScanResult],
                                     selection: Set<String>) -> Int64 {
        results.flatMap(\.items).filter { selection.contains($0.id) }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    /// The one-click quick clean: Safe risk AND recoverable (goes to Trash).
    /// Permanent removals (Docker) never ride along on a single click — the
    /// user opts into those item by item.
    public static func quickCleanItems(in results: [CategoryScanResult]) -> [ScanItem] {
        results.flatMap(\.items).filter {
            $0.risk == .safe
                && (Catalog.category($0.categoryID)?.removal ?? .trash) == .trash
        }
    }
}

/// Byte formatting used everywhere (single source of truth).
public enum ByteText {
    public static func string(_ bytes: Int64) -> String {
        let fmt = ByteCountFormatter()
        fmt.countStyle = .file
        return fmt.string(fromByteCount: bytes)
    }
}
