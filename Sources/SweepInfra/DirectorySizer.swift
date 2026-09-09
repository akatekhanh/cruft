import Foundation

/// Public read-only sizing for the dashboard's storage breakdown.
/// Same traversal rules as the scanners (allocated size, skip unreadable).
public enum DirectorySizer {
    /// Sum of the recursive sizes of every path (missing paths count as 0).
    public static func totalSize(ofPaths paths: [String]) -> Int64 {
        paths.reduce(0) { $0 + FSHelpers.sizeOf(FSHelpers.expandTilde($1)) }
    }
}
