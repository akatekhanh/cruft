import Foundation

/// Public read-only sizing for the Overview breakdown.
/// Same traversal rules as the scanners (allocated size, skip unreadable).
public enum DirectorySizer {
    /// Sum of the recursive sizes of every path (missing paths count as 0).
    public static func totalSize(ofPaths paths: [String]) -> Int64 {
        paths.reduce(0) { $0 + FSHelpers.sizeOf(FSHelpers.expandTilde($1)) }
    }

    /// Every dot-directory in the home folder, plus `~/go`.
    ///
    /// This is where "Other" actually hides. Tools install into `~/.something`
    /// by convention — `~/.colima` was 81 GB on the machine this was written on
    /// — and a breakdown that only looks at Library/Documents/Media therefore
    /// attributes the largest thing on the disk to a slice labelled "Other",
    /// which tells the user nothing. Enumerated rather than hard-coded, because
    /// the interesting one is always the tool you didn't think of.
    public static func developerDataPaths() -> [String] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var paths: [String] = []
        if let children = try? fm.contentsOfDirectory(
            at: home, includingPropertiesForKeys: [.isDirectoryKey], options: []
        ) {
            for child in children where child.lastPathComponent.hasPrefix(".") {
                // `.Trash` has its own slice and its own category; counting it
                // here would double-report it.
                if child.lastPathComponent == ".Trash" { continue }
                if FSHelpers.isDirectory(child) { paths.append(child.path) }
            }
        }
        let goDir = home.appendingPathComponent("go")
        if FSHelpers.isDirectory(goDir) { paths.append(goDir.path) }
        return paths
    }

    /// This user's slice of `/private/var/folders` — the per-user cache and temp
    /// area macOS hands to sandboxed apps. `NSTemporaryDirectory()` points
    /// inside it, so its grandparent is the whole tree for this user without
    /// having to guess the hashed directory name.
    ///
    /// Returns the subdirectories worth measuring rather than the tree itself,
    /// because one of them must be left out — see `cloneDirectoryNames`.
    public static func systemTempPaths() -> [String] {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .deletingLastPathComponent()
        guard temp.path.hasPrefix("/private/var/folders/")
                || temp.path.hasPrefix("/var/folders/") else { return [] }
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: temp, includingPropertiesForKeys: nil, options: []
        ) else { return [temp.path] }
        return children
            .filter { !cloneDirectoryNames.contains($0.lastPathComponent) }
            .map(\.path)
    }

    /// Subdirectories of the per-user temp tree that hold APFS *clones* rather
    /// than data, and must be excluded from any size that claims to be
    /// reclaimable space.
    ///
    /// `X/` is where macOS puts code-signing clones of app bundles. They are
    /// copy-on-write: every file reports its full allocated size, so a directory
    /// walk sees a real number — 54 GB across 39 Chrome clones on the machine
    /// this was written on — while the blocks are shared with the installed app
    /// and nothing is actually occupied. Verified by deleting one outright: `du`
    /// said 1.4 GB, the volume's free space did not move a byte.
    ///
    /// Counting them inflated the Overview's total past the disk's own used
    /// figure, and any category built on that number would have promised space
    /// it cannot deliver — the exact dishonesty this app exists to avoid.
    public static let cloneDirectoryNames: Set<String> = ["X"]

    /// Where Homebrew keeps everything it installed, per architecture.
    public static func homebrewPaths() -> [String] {
        ["/opt/homebrew", "/usr/local/Homebrew", "/usr/local/Cellar"]
            .filter { FSHelpers.isDirectory(URL(fileURLWithPath: $0)) }
    }
}
