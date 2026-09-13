import Foundation

/// Adapter port: scans one category and returns found items. Must never mutate disk.
public protocol CategoryScanner: Sendable {
    var category: CleanCategory { get }
    func scan() async -> [ScanItem]
}

/// Adapter port: recoverable cleaning only (move to Trash — never permanent delete).
public protocol TrashService: Sendable {
    func moveToTrash(_ url: URL) throws
}

/// Adapter port for categories whose items are not plain files on disk (e.g. Docker
/// objects, removed via the docker CLI). `CleanUseCase` routes an item here when its
/// category id is owned by a special cleaner; everything else falls back to Trash.
/// Removal through this port is permanent — such categories must be declared with
/// `RemovalMethod.external` so the UI can be honest about it.
public protocol SpecialCleaner: Sendable {
    var categoryIDs: Set<String> { get }
    func clean(_ item: ScanItem) throws
}
