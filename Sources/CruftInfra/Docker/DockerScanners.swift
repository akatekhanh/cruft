import Foundation
import CruftCore

/// One `docker system df -v` call shared by every Docker category scanner in a
/// scan run (it's the expensive part — Docker walks container filesystems).
/// Results are cached briefly so five categories cost one CLI call, while a
/// user-triggered rescan after the TTL still sees fresh data.
public actor DockerInventory {
    private let ttl: TimeInterval
    private var fetchedAt: Date?
    private var reachable = false
    private var byCategory: [String: [ScanItem]] = [:]

    public init(ttl: TimeInterval = 15) { self.ttl = ttl }

    public func items(for categoryID: String) -> [ScanItem] {
        refreshIfStale()
        return byCategory[categoryID] ?? []
    }

    public func isDaemonReachable() -> Bool {
        refreshIfStale()
        return reachable
    }

    private func refreshIfStale() {
        if let fetchedAt, Date().timeIntervalSince(fetchedAt) < ttl { return }
        fetchedAt = Date()
        reachable = false
        byCategory = [:]
        guard let cli = DockerCLI(), cli.isDaemonReachable() else { return }
        reachable = true
        if let json = try? cli.systemDF() {
            byCategory = DockerUsageParser.items(fromDF: json)
        }
    }
}

/// Scanner for one granular Docker category — all the work is in the shared
/// inventory; this just picks its bucket.
public struct DockerObjectScanner: CategoryScanner, Sendable {
    public let category: CleanCategory
    private let inventory: DockerInventory

    public init(category: CleanCategory, inventory: DockerInventory) {
        self.category = category
        self.inventory = inventory
    }

    public func scan() async -> [ScanItem] {
        await inventory.items(for: category.id)
    }
}

/// The old whole-disk category, kept as a fallback: only reported when the
/// Docker daemon is NOT reachable (when it is, the granular categories above
/// cover the same bytes item by item — showing both would double-count).
public struct DockerDiskFallbackScanner: CategoryScanner, Sendable {
    public let category: CleanCategory
    private let inventory: DockerInventory
    private let wholeDisk: WholeDirectoryScanner

    public init(category: CleanCategory, inventory: DockerInventory) {
        self.category = category
        self.inventory = inventory
        self.wholeDisk = WholeDirectoryScanner(
            category: category,
            roots: ["~/Library/Containers/com.docker.docker/Data/vms"],
            labels: ["Docker virtual disk"]
        )
    }

    public func scan() async -> [ScanItem] {
        if await inventory.isDaemonReachable() { return [] }
        return await wholeDisk.scan()
    }
}

/// Removes Docker objects through the docker CLI. Owned categories are exactly
/// the granular ones — the whole-disk fallback stays a normal file (trashable).
public struct DockerCleaner: SpecialCleaner, Sendable {
    public var categoryIDs: Set<String> { Set(DockerUsageParser.categoryIDs) }

    public init() {}

    public func clean(_ item: ScanItem) throws {
        guard let cli = DockerCLI() else {
            throw DockerCLI.CommandError(message: "docker CLI not found")
        }
        // docker://local/<kind>/<ref> — ref may itself contain slashes (registry paths).
        let comps = item.url.pathComponents
        guard comps.count >= 3 else {
            throw DockerCLI.CommandError(message: "unrecognized item id: \(item.id)")
        }
        let kind = comps[1]
        let ref = comps.dropFirst(2).joined(separator: "/")
        switch kind {
        case "image": try cli.removeImage(ref)
        case "container": try cli.removeContainer(ref)
        case "volume": try cli.removeVolume(ref)
        case "build-cache": try cli.pruneBuildCache()
        default:
            throw DockerCLI.CommandError(message: "unknown docker object kind: \(kind)")
        }
    }
}
