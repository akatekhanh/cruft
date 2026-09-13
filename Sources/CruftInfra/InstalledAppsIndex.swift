import AppKit
import Foundation

/// Every bundle identifier this Mac can currently launch, used to tell
/// leftover data from data an installed app still needs.
///
/// Getting this wrong is expensive — a false "orphan" means offering to delete
/// the settings of an app the user still has — so the index is deliberately
/// over-inclusive. Anything it can't prove is gone stays out of the results.
public struct InstalledAppsIndex: Sendable {
    /// Lowercased bundle identifiers of installed (or currently running) apps.
    public let bundleIDs: Set<String>

    public init(bundleIDs: Set<String>) {
        self.bundleIDs = bundleIDs
    }

    /// Reads the app folders macOS actually installs into, plus every running
    /// process — that last part catches CLI tools, menu-bar helpers and
    /// background agents that own a bundle id but have no `.app` anywhere.
    public static func current() -> InstalledAppsIndex {
        var ids = Set<String>()

        for root in appRoots() {
            for app in appBundles(in: root) {
                if let id = bundleIdentifier(of: app) {
                    ids.insert(id.lowercased())
                }
            }
        }

        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier {
                ids.insert(id.lowercased())
            }
        }

        return InstalledAppsIndex(bundleIDs: ids)
    }

    /// True when `id` (or any app it is nested under) is still installed.
    /// A helper's data lives under its parent's id (`com.acme.app.helper`
    /// beside `com.acme.app`), so a prefix match keeps the parent's helpers.
    public func isInstalled(_ id: String) -> Bool {
        let lower = id.lowercased()
        if bundleIDs.contains(lower) { return true }
        return bundleIDs.contains { lower.hasPrefix($0 + ".") }
    }

    private static func appRoots() -> [URL] {
        var roots = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Library/CoreServices",
            "~/Applications",
        ].map(FSHelpers.expandTilde)
        // Setapp and JetBrains Toolbox install outside /Applications.
        roots.append(FSHelpers.expandTilde("~/Applications/Setapp"))
        roots.append(FSHelpers.expandTilde("~/Library/Application Support/JetBrains/Toolbox/apps"))
        return roots
    }

    /// `.app` bundles directly in `root` or one level down (Setapp, Adobe and
    /// Microsoft all nest their apps in a subfolder).
    private static func appBundles(in root: URL) -> [URL] {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }

        var apps: [URL] = []
        for child in children {
            if child.pathExtension == "app" {
                apps.append(child)
            } else if FSHelpers.isDirectory(child) {
                guard let grandchildren = try? fm.contentsOfDirectory(
                    at: child, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                ) else { continue }
                apps.append(contentsOf: grandchildren.filter { $0.pathExtension == "app" })
            }
        }
        return apps
    }

    private static func bundleIdentifier(of app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return info["CFBundleIdentifier"] as? String
    }
}
