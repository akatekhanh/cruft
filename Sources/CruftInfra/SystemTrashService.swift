import Foundation
import CruftCore

/// Recoverable cleaning via the system Trash. Never permanently deletes.
public struct SystemTrashService: TrashService {
    public init() {}

    public func moveToTrash(_ url: URL) throws {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
    }
}
