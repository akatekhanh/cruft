import Foundation
import SweepCore

/// Composition root for scanners: wires every `Catalog` category to a concrete
/// `CategoryScanner`, in `Catalog.categories` order.
public enum SweepInfraFactory {

    /// Shared across all Docker scanners so one scan run issues one `docker system df`.
    private static let dockerInventory = DockerInventory()

    /// One scanner per `Catalog` category, in `Catalog.categories` order.
    public static func makeAllScanners() -> [CategoryScanner] {
        Catalog.categories.map(makeScanner(for:))
    }

    /// Cleaners for categories whose items are not files (routed before Trash).
    public static func makeSpecialCleaners() -> [SpecialCleaner] {
        [DockerCleaner()]
    }

    private static func makeScanner(for category: CleanCategory) -> CategoryScanner {
        switch category.id {
        case "trash":
            return DirectoryChildrenScanner(category: category, roots: ["~/.Trash"])

        case "logs":
            return DirectoryChildrenScanner(category: category, roots: ["~/Library/Logs"])

        case "user-caches":
            return DirectoryChildrenScanner(
                category: category,
                roots: ["~/Library/Caches"],
                excludedChildNameContains: [
                    "Homebrew", "pip", "Yarn", "CocoaPods", "Google", "Firefox",
                    "Microsoft Edge", "com.apple.Safari", "com.bohemiancoding.sketch3",
                    "com.figma.Desktop", "com.apple.FontRegistry",
                ]
            )

        case "xcode-derived":
            return DirectoryChildrenScanner(
                category: category, roots: ["~/Library/Developer/Xcode/DerivedData"]
            )

        case "device-support":
            return DirectoryChildrenScanner(
                category: category, roots: ["~/Library/Developer/Xcode/iOS DeviceSupport"]
            )

        case "simulators":
            return WholeDirectoryScanner(
                category: category,
                roots: ["~/Library/Developer/CoreSimulator/Caches"],
                labels: ["Simulator caches"]
            )

        case "npm-cache":
            return WholeDirectoryScanner(
                category: category,
                roots: ["~/.npm", "~/Library/Caches/Yarn", "~/Library/pnpm/store"],
                labels: ["npm cache", "Yarn cache", "pnpm store"]
            )

        case "pip-cache":
            return WholeDirectoryScanner(
                category: category,
                roots: ["~/Library/Caches/pip", "~/.cache/pip"],
                labels: ["pip cache", "pip cache (XDG)"]
            )

        case "brew-cache":
            return WholeDirectoryScanner(
                category: category, roots: ["~/Library/Caches/Homebrew"], labels: ["Homebrew cache"]
            )

        case "cocoapods-cache":
            return WholeDirectoryScanner(
                category: category, roots: ["~/Library/Caches/CocoaPods"], labels: ["CocoaPods cache"]
            )

        case "gradle-cache":
            return WholeDirectoryScanner(
                category: category,
                roots: ["~/.gradle/caches", "~/.m2/repository"],
                labels: ["Gradle caches", "Maven repository"]
            )

        case "docker-build-cache", "docker-dangling-images", "docker-stopped-containers",
             "docker-unused-images", "docker-unused-volumes":
            return DockerObjectScanner(category: category, inventory: dockerInventory)

        case "docker-data":
            return DockerDiskFallbackScanner(category: category, inventory: dockerInventory)

        case "orphaned-app-data":
            return OrphanedAppDataScanner(category: category)

        case "ai-models":
            return CompositeScanner(category: category, scanners: [
                // Ollama's blob store is content-addressed — models share blobs,
                // so it's honest only as one unit.
                WholeDirectoryScanner(category: category,
                                      roots: ["~/.ollama/models"],
                                      labels: ["Ollama models (all of them)"]),
                // Per-model children where the layout allows picking.
                DirectoryChildrenScanner(category: category,
                                         roots: ["~/.cache/huggingface/hub",
                                                 "~/.lmstudio/models",
                                                 "~/.cache/lm-studio/models"]),
                WholeDirectoryScanner(category: category,
                                      roots: ["~/.cache/torch", "~/.cache/whisper"],
                                      labels: ["PyTorch model cache", "Whisper models"]),
            ])

        case "adobe-media-cache":
            return WholeDirectoryScanner(
                category: category,
                roots: [
                    "~/Library/Application Support/Adobe/Common/Media Cache Files",
                    "~/Library/Application Support/Adobe/Common/Media Cache",
                ],
                labels: ["Adobe media cache files", "Adobe media cache"]
            )

        case "font-caches":
            return WholeDirectoryScanner(
                category: category,
                roots: ["~/Library/Caches/com.apple.FontRegistry"],
                labels: ["Font cache"]
            )

        case "sketch-cache":
            return WholeDirectoryScanner(
                category: category,
                roots: [
                    "~/Library/Caches/com.bohemiancoding.sketch3",
                    "~/Library/Caches/com.figma.Desktop",
                ],
                labels: ["Sketch cache", "Figma cache"]
            )

        case "fcp-render":
            return FCPRenderScanner(category: category)

        case "screen-recordings":
            return NamePatternScanner(
                category: category, roots: ["~/Desktop", "~/Movies"], prefixes: ["Screen Recording"]
            )

        case "browser-caches":
            return WholeDirectoryScanner(
                category: category,
                roots: [
                    "~/Library/Caches/Google/Chrome", "~/Library/Caches/com.apple.Safari",
                    "~/Library/Caches/Firefox", "~/Library/Caches/Microsoft Edge",
                ],
                labels: ["Chrome cache", "Safari cache", "Firefox cache", "Edge cache"]
            )

        case "zoom-teams-cache":
            return WholeDirectoryScanner(
                category: category,
                roots: [
                    "~/Library/Application Support/zoom.us/AutoUpdater",
                    "~/Library/Caches/us.zoom.xos",
                    "~/Library/Caches/com.microsoft.teams2",
                ],
                labels: ["Zoom updater", "Zoom cache", "Teams cache"]
            )

        case "old-downloads":
            return AgedFilesScanner(category: category, root: "~/Downloads", olderThanDays: 90)

        case "desktop-screenshots":
            return NamePatternScanner(
                category: category, roots: ["~/Desktop"], prefixes: ["Screenshot", "Ảnh chụp"]
            )

        case "mail-downloads":
            return WholeDirectoryScanner(
                category: category,
                roots: ["~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"],
                labels: ["Mail downloads cache"]
            )

        case "large-files":
            return LargeFilesScanner(
                category: category,
                roots: ["~/Downloads", "~/Desktop", "~/Documents", "~/Movies"]
            )

        case "ios-backups":
            return DirectoryChildrenScanner(
                category: category,
                roots: ["~/Library/Application Support/MobileSync/Backup"]
            )

        default:
            // Should not happen: every Catalog category is handled above.
            return DirectoryChildrenScanner(category: category, roots: [])
        }
    }
}
