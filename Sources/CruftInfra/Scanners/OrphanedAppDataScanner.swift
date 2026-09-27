import Foundation
import CruftCore

/// Data left behind in `~/Library` by apps that are no longer installed.
///
/// Uninstalling on macOS usually means dragging one bundle to the Trash, which
/// leaves its support folder, cache, container and preferences behind — often
/// for years, often gigabytes. This scanner finds those by matching
/// bundle-identifier-shaped folder names against
/// [`InstalledAppsIndex`](InstalledAppsIndex).
///
/// The whole difficulty is avoiding false positives, so every rule here is a
/// rule about what *not* to report:
///
///   * only names shaped like a reverse-DNS bundle id (`com.acme.thing`), so
///     ordinary folders such as `Firefox` or `Google` are never candidates;
///   * never anything Apple (`com.apple.…`): those belong to the OS, have no
///     `.app` in `/Applications`, and would otherwise dominate the results;
///   * never an id whose parent app is installed, so helpers and login items
///     of a live app survive (handled by `isInstalled`);
///   * never a known non-app owner — developer tools and updaters that legally
///     own a bundle id without shipping an app bundle;
///   * nothing below `minBytes`, because a 40 KB plist is not worth a decision.
public struct OrphanedAppDataScanner: CategoryScanner, Sendable {
    public let category: CleanCategory
    private let roots: [String]
    private let minBytes: Int64
    /// Injected for tests only. In production the index is rebuilt on every
    /// scan (inside `scan()`, off the main actor), because an app installed or
    /// launched after Cruft started must not be reported as gone.
    private let fixedIndex: InstalledAppsIndex?

    /// Bundle ids that routinely exist without an installed `.app`: CLI tools,
    /// updaters, and frameworks that write to `~/Library` on their own. Matched
    /// as prefixes.
    private static let nonAppOwners: [String] = [
        "com.microsoft.autoupdate",
        // Updater processes: they own a bundle id, ship no .app, and belong to
        // a browser that is still installed. Google has shipped two generations
        // (Keystone, then GoogleUpdater) and Sparkle is used by dozens of apps.
        "com.google.keystone",
        "com.google.googleupdater",
        "org.sparkle-project",
        "com.brave.browser.updater",
        "com.microsoft.edgeupdater",
        "com.google.gmail",         // Chrome web apps
        "com.adobe.acc",            // Creative Cloud helpers
        "com.adobe.creativecloud",
        "com.docker.docker",        // Docker Desktop's helper tree
        "com.jetbrains.toolbox",
        "com.electron",
        "com.github.copilot",
        "org.python",
        "org.swift",
        "com.crashlytics",
        "com.postmanlabs",
        "dev.warp",
    ]

    public init(category: CleanCategory,
                roots: [String] = [
                    "~/Library/Application Support",
                    "~/Library/Caches",
                    "~/Library/Containers",
                    "~/Library/Saved Application State",
                    "~/Library/HTTPStorages",
                    "~/Library/WebKit",
                ],
                minBytes: Int64 = 1_000_000,
                index: InstalledAppsIndex? = nil) {
        self.category = category
        self.roots = roots
        self.minBytes = minBytes
        self.fixedIndex = index
    }

    /// A name macOS would only produce from a bundle identifier: at least two
    /// dots, no spaces, and a lowercase-ish first label.
    public static func bundleID(fromFolderName name: String) -> String? {
        var base = name
        for suffix in [".savedState", ".plist", ".binarycookies"] where base.hasSuffix(suffix) {
            base.removeLast(suffix.count)
        }
        let labels = base.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 3, !base.contains(" "),
              labels.allSatisfy({ !$0.isEmpty }),
              let first = labels.first,
              first.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
        else { return nil }
        return base
    }

    public static func isExcluded(_ bundleID: String) -> Bool {
        let lower = bundleID.lowercased()
        if lower.hasPrefix("com.apple.") { return true }
        return nonAppOwners.contains { lower.hasPrefix($0) }
    }

    /// Exposed for tests: decide about one candidate name without touching disk.
    public static func orphanedBundleID(forFolderName name: String,
                                        index: InstalledAppsIndex) -> String? {
        guard let id = bundleID(fromFolderName: name), !isExcluded(id) else { return nil }
        return index.isInstalled(id) ? nil : id
    }

    public func scan() async -> [ScanItem] {
        let index = fixedIndex ?? InstalledAppsIndex.current()
        return FSHelpers.safely {
            let fm = FileManager.default
            var items: [ScanItem] = []
            var seen = Set<String>()

            for root in roots {
                let rootURL = FSHelpers.expandTilde(root)
                var isDir = false
                guard FSHelpers.exists(rootURL, isDirectory: &isDir), isDir else { continue }
                guard let children = try? fm.contentsOfDirectory(
                    at: rootURL, includingPropertiesForKeys: nil, options: []
                ) else { continue }

                for child in children {
                    let name = child.lastPathComponent
                    if name.hasPrefix(".") { continue }
                    guard let id = Self.orphanedBundleID(forFolderName: name, index: index)
                    else { continue }
                    let size = FSHelpers.sizeOf(child)
                    if size < minBytes { continue }
                    // One row per leftover folder, but label it by app id so a
                    // user scanning the list sees "which app" not "which folder".
                    let label = seen.contains(id) ? "\(id) — \(rootURL.lastPathComponent)" : id
                    seen.insert(id)
                    items.append(ScanItem(
                        url: child,
                        displayName: label,
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
