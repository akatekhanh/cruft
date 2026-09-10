import Foundation
import SweepCore

/// Old copies of self-updating command-line tools that install each release
/// side by side and never remove the previous one — Claude Code, Cursor Agent,
/// GitHub Copilot CLI and friends. Each release is a ~200 MB binary, and a tool
/// that ships several times a week accumulates gigabytes within a month.
///
/// The only difficult part is knowing which copy is live, and the answer is the
/// launcher symlink, not the timestamp: these tools stage the next release on
/// disk *before* moving the symlink onto it, so the newest directory by
/// modification date is sometimes the one that is not in use yet. Deleting by
/// "keep the newest" would then remove the running binary.
///
/// If the symlink can't be resolved, the whole location is skipped: without
/// knowing what's live, no version here is safe to offer.
public struct CLIVersionsScanner: CategoryScanner, Sendable {
    /// One self-updating tool: where its versions live, and the launcher that
    /// points at the active one.
    public struct Tool: Sendable {
        public let name: String
        public let versionsDir: String
        public let launcher: String

        public init(name: String, versionsDir: String, launcher: String) {
            self.name = name
            self.versionsDir = versionsDir
            self.launcher = launcher
        }
    }

    public let category: CleanCategory
    private let tools: [Tool]

    public static let defaultTools: [Tool] = [
        .init(name: "Claude Code", versionsDir: "~/.local/share/claude/versions",
              launcher: "~/.local/bin/claude"),
        .init(name: "Cursor Agent", versionsDir: "~/.local/share/cursor-agent/versions",
              launcher: "~/.local/bin/cursor-agent"),
        .init(name: "Copilot CLI", versionsDir: "~/.copilot/pkg/universal",
              launcher: "~/.copilot/bin/copilot"),
    ]

    public init(category: CleanCategory, tools: [Tool] = defaultTools) {
        self.category = category
        self.tools = tools
    }

    /// The version directory the launcher currently points at, resolved through
    /// however many symlink hops it takes. Nil when the launcher is missing or
    /// doesn't lead into `versionsDir` — in which case the caller must not
    /// delete anything there.
    public static func activeVersion(versionsDir: URL, launcher: URL) -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: launcher.path) else { return nil }
        let resolved = launcher.resolvingSymlinksInPath()
        let base = versionsDir.resolvingSymlinksInPath().path
        guard resolved.path.hasPrefix(base + "/") else { return nil }
        // …/versions/2.1.265[/optional/extra] → "2.1.265"
        let relative = String(resolved.path.dropFirst(base.count + 1))
        return relative.split(separator: "/").first.map(String.init)
    }

    public func scan() async -> [ScanItem] {
        FSHelpers.safely {
            let fm = FileManager.default
            var items: [ScanItem] = []

            for tool in tools {
                let dir = FSHelpers.expandTilde(tool.versionsDir)
                var isDir = false
                guard FSHelpers.exists(dir, isDirectory: &isDir), isDir else { continue }
                guard let active = Self.activeVersion(
                    versionsDir: dir, launcher: FSHelpers.expandTilde(tool.launcher)
                ) else { continue }
                guard let children = try? fm.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: nil, options: []
                ) else { continue }

                for child in children {
                    let name = child.lastPathComponent
                    if name.hasPrefix(".") || name == active { continue }
                    let size = FSHelpers.sizeOf(child)
                    if size <= 0 { continue }
                    items.append(ScanItem(
                        url: child,
                        displayName: "\(tool.name) \(name)",
                        sizeBytes: size,
                        categoryID: category.id,
                        risk: category.risk,
                        lastModified: FSHelpers.lastModified(of: child),
                        lastAccessed: FSHelpers.lastAccessed(of: child)
                    ))
                }
            }
            return items
        }
    }
}
