import Foundation
import CruftCore

/// Deletes items that are *already in the Trash*. `FileManager.trashItem` on a
/// path inside `~/.Trash` is a silent no-op — it reports success and moves
/// nothing — so the Trash category has to remove for real. It is the only
/// category routed here, and its `RemovalMethod` is `.external` so it never
/// rides along on a one-click clean.
public struct PermanentDeleteCleaner: SpecialCleaner, Sendable {
    public let categoryIDs: Set<String>
    private let allowedRoots: [URL]

    public init(categoryIDs: Set<String> = ["trash"],
                allowedRoots: [String] = ["~/.Trash"]) {
        self.categoryIDs = categoryIDs
        self.allowedRoots = allowedRoots.map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).resolvingSymlinksInPath()
        }
    }

    public struct RefusedError: LocalizedError {
        public let path: String
        public var errorDescription: String? {
            "Refused to delete \(path): it is not inside the Trash."
        }
    }

    public func clean(_ item: ScanItem) throws {
        // Belt and braces: whatever the scanner produced, never delete outside
        // the Trash permanently.
        let target = item.url.resolvingSymlinksInPath().path
        guard allowedRoots.contains(where: { target.hasPrefix($0.path + "/") }) else {
            throw RefusedError(path: item.url.path)
        }
        try FileManager.default.removeItem(at: item.url)
    }
}
