import Foundation

/// How dangerous it is to clean an item. Ordered: safe < review < risky.
public enum RiskLevel: Int, Codable, CaseIterable, Comparable, Sendable {
    case safe = 0    // regenerated automatically, zero loss
    case review = 1  // safe but has a cost (re-download, rebuild, re-login)
    case risky = 2   // real potential data loss; big space win; explicit opt-in

    public static func < (l: RiskLevel, r: RiskLevel) -> Bool { l.rawValue < r.rawValue }

    /// Plain-language label shown in UI section headers.
    public var label: String {
        switch self {
        case .safe: return "Safe to clean"
        case .review: return "Worth a look"
        case .risky: return "Risky — check carefully"
        }
    }
}

/// How items of a category leave the machine when cleaned.
public enum RemovalMethod: Sendable, Hashable {
    /// Recoverable: moved to Trash via `FileManager.trashItem`.
    case trash
    /// Handed to the tool that owns the data (e.g. `docker rmi`). NOT recoverable —
    /// UI copy must say so explicitly wherever these items appear.
    case external
}

public struct CleanCategory: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// What this is, in plain language.
    public let detail: String
    /// What happens after cleaning, in plain language.
    public let consequence: String
    public let risk: RiskLevel
    public let systemImage: String
    public let removal: RemovalMethod

    public init(id: String, name: String, detail: String, consequence: String,
                risk: RiskLevel, systemImage: String, removal: RemovalMethod = .trash) {
        self.id = id; self.name = name; self.detail = detail
        self.consequence = consequence; self.risk = risk; self.systemImage = systemImage
        self.removal = removal
    }
}

public struct RoleProfile: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let blurb: String
    public let systemImage: String
    public let categoryIDs: [String]

    public init(id: String, name: String, blurb: String, systemImage: String,
                categoryIDs: [String]) {
        self.id = id; self.name = name; self.blurb = blurb
        self.systemImage = systemImage; self.categoryIDs = categoryIDs
    }
}

public struct ScanItem: Identifiable, Hashable, Sendable {
    /// Stable id = file path.
    public var id: String { url.path }
    public let url: URL
    public let displayName: String
    public let sizeBytes: Int64
    public let categoryID: String
    /// Per-item risk; defaults to the category's risk but a scanner may raise it.
    public let risk: RiskLevel
    public let lastModified: Date?

    public init(url: URL, displayName: String, sizeBytes: Int64, categoryID: String,
                risk: RiskLevel, lastModified: Date? = nil) {
        self.url = url; self.displayName = displayName; self.sizeBytes = sizeBytes
        self.categoryID = categoryID; self.risk = risk; self.lastModified = lastModified
    }
}

public struct CategoryScanResult: Identifiable, Sendable {
    public let category: CleanCategory
    public let items: [ScanItem]
    public var id: String { category.id }
    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }

    public init(category: CleanCategory, items: [ScanItem]) {
        self.category = category
        self.items = items.sorted { $0.sizeBytes > $1.sizeBytes }
    }
}

public struct CleanReport: Sendable {
    public let freedBytes: Int64
    public let cleanedCount: Int
    public let failures: [(item: ScanItem, message: String)]
    /// Portion of `freedBytes` that was removed permanently by an external tool
    /// (e.g. Docker) instead of going to the Trash. 0 = everything is restorable.
    public let externallyRemovedBytes: Int64
    public init(freedBytes: Int64, cleanedCount: Int,
                failures: [(item: ScanItem, message: String)],
                externallyRemovedBytes: Int64 = 0) {
        self.freedBytes = freedBytes; self.cleanedCount = cleanedCount
        self.failures = failures
        self.externallyRemovedBytes = externallyRemovedBytes
    }
}
