import AppKit
import SwiftUI
import CruftCore
import CruftInfra

/// Renders each app screen offscreen to PNG for visual verification.
@MainActor
enum SnapshotRunner {
    static func run(outputDir: String) {
        let dir = URL(fileURLWithPath: outputDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let model = AppModel(
            scan: ScanUseCase(scanners: []),
            clean: CleanUseCase(trash: SystemTrashService())
        )
        model.results = Self.fakeResults()
        model.selection = SelectionPolicy.defaultSelection(in: model.results)
        model.diskStats = DiskStats(totalBytes: 245_110_000_000, availableBytes: 56_560_000_000)
        model.storageBreakdown = Self.fakeBreakdown()

        for scheme in [("light", NSAppearance(named: .aqua)!),
                       ("dark", NSAppearance(named: .darkAqua)!)] {
            snap(OnboardingView(model: model), "onboarding-\(scheme.0)", dir, scheme.1)
            // The tab bar is part of every real screen, so shots that omit it
            // would misrepresent the app in the README.
            model.selectedTab = "overview"
            snap(chrome(model, OverviewView(model: model, device: Self.fakeDevice,
                                            measuresOnAppear: false)),
                 "overview-\(scheme.0)", dir, scheme.1)
            model.selectedTab = model.role.id
            snap(chrome(model, DashboardView(model: model)), "dashboard-\(scheme.0)", dir, scheme.1)
            model.selectedTab = Catalog.smartRole.id
            model.role = Catalog.smartRole
            model.riskFilter = nil
            snap(chrome(model, ResultsView(model: model)), "results-\(scheme.0)", dir, scheme.1)
            // One shot per risk sub-tab: the point of the tabs is that each tier
            // can be reviewed alone, so the README should show one alone.
            model.riskFilter = .review
            snap(chrome(model, ResultsView(model: model)), "results-review-\(scheme.0)", dir, scheme.1)
            model.riskFilter = .risky
            snap(chrome(model, ResultsView(model: model)), "results-risky-\(scheme.0)", dir, scheme.1)
            model.riskFilter = nil
            snap(DoneView(model: model,
                          report: CleanReport(freedBytes: 3_460_000_000, cleanedCount: 42,
                                              failures: [])),
                 "done-\(scheme.0)", dir, scheme.1)
        }
        print("snapshots written to \(dir.path)")
        exit(0)
    }

    /// Wraps a screen in the app chrome (the role tab bar) so snapshots match
    /// what a user actually sees.
    private static func chrome(_ model: AppModel, _ view: some View) -> some View {
        VStack(spacing: 0) {
            RoleTabBar(model: model)
            Divider()
            view
        }
    }

    private static func snap(_ view: some View, _ name: String, _ dir: URL,
                             _ appearance: NSAppearance) {
        // NSHostingView inside an offscreen window renders NavigationSplitView
        // reliably (ImageRenderer does not).
        let content = view.frame(width: 1080, height: 700)
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: AnyView(content))
        hosting.frame = NSRect(x: 0, y: 0, width: 1080, height: 700)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = hosting
        // Lazy containers (List/NavigationSplitView) only lay out in an
        // ordered-in window; park it off the visible area and pump the run loop.
        // On-screen, not parked off-screen: NavigationSplitView's sidebar only
        // materialises in a window the window server actually composites, and
        // renders as a blank half-drawn material otherwise.
        window.center()
        window.orderFrontRegardless()
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        window.makeKeyAndOrderFront(nil)
        // NavigationSplitView's sidebar resolves over several layout passes; a
        // single settle leaves it blank (with a half-drawn material gradient).
        // Pump, re-layout, pump again until it has actually drawn.
        for _ in 0..<3 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.8))
            window.layoutIfNeeded()
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
        // Capture through the window server, not cacheDisplay: SwiftUI's List
        // inside NavigationSplitView draws nothing on the AppKit display path,
        // which left the sidebar blank. Capturing one's own window needs no
        // screen-recording permission.
        let png: Data?
        if let shot = captureOwnWindow(CGWindowID(window.windowNumber)) {
            png = NSBitmapImageRep(cgImage: shot).representation(using: .png, properties: [:])
        } else if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            png = rep.representation(using: .png, properties: [:])
        } else {
            png = nil
        }
        guard let png else {
            print("snapshot \(name): capture failed"); return
        }
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }

    private static func fakeResults() -> [CategoryScanResult] {
        /// `idleDays` drives the "unused N months" badge, so snapshots show it.
        func fake(_ catID: String, _ entries: [(String, Int64)],
                  risk: RiskLevel? = nil, idleDays: Int = 0) -> CategoryScanResult? {
            guard let c = Catalog.category(catID) else { return nil }
            let date = Date(timeIntervalSinceNow: -Double(idleDays) * 86400)
            let items = entries.map { (name, size) in
                ScanItem(url: URL(fileURLWithPath: "/tmp/fake/\(name)"), displayName: name,
                         sizeBytes: size, categoryID: c.id, risk: risk ?? c.risk,
                         lastModified: date, lastAccessed: date)
            }
            return CategoryScanResult(category: c, items: items)
        }
        return [
            fake("xcode-derived", [("MyApp-abcdef", 4_800_000_000),
                                   ("ClientWork-xyz", 1_200_000_000)]),
            fake("docker-build-cache", [("Build cache (183 entries)", 14_370_000_000)]),
            fake("npm-cache", [("npm cache", 2_100_000_000)]),
            fake("user-caches", [("com.spotify.client", 900_000_000),
                                 ("com.apple.dt.Xcode", 640_000_000)]),
            fake("docker-unused-volumes", [("pgdata", 1_200_000_000),
                                           ("minio_data", 950_000_000)]),
            fake("ai-models", [("Ollama models (all of them)", 12_800_000_000)], idleDays: 200),
            fake("orphaned-app-data", [("com.oldvendor.tool", 840_000_000),
                                       ("com.deadapp.editor", 210_000_000)], idleDays: 500),
            fake("old-downloads", [("installer-2025.dmg", 3_100_000_000),
                                   ("report-final-v2.pdf", 18_000_000)]),
            fake("large-files", [("footage-raw.mov", 8_900_000_000)]),
        ].compactMap { $0 }
    }

    /// Deliberately the deprecated CoreGraphics call rather than its
    /// ScreenCaptureKit replacement, and the one warning this build emits:
    /// capturing a window of one's own process needs no screen-recording
    /// permission, so snapshots keep working in CI and over SSH, where
    /// ScreenCaptureKit would prompt for consent and fail without a UI session.
    private static func captureOwnWindow(_ id: CGWindowID) -> CGImage? {
        CGWindowListCreateImage(.null, .optionIncludingWindow, id,
                                [.boundsIgnoreFraming, .bestResolution])
    }

    /// A generic machine — snapshots ship in the README, so they must not
    /// carry whoever generated them.
    private static let fakeDevice = DeviceInfo(
        name: "Mac mini", modelID: "Mac16,10", chip: "Apple M4",
        ramBytes: 17_179_869_184, osVersion: "Version 15.5 (Build 24F74)"
    )

    private static func fakeBreakdown() -> [StorageComponent] {
        [
            StorageComponent(id: "apps", name: "Apps", paths: [],
                             bytes: 6_570_000_000, measured: true),
            StorageComponent(id: "appdata", name: "App data & caches", paths: [],
                             bytes: 19_360_000_000, measured: true),
            StorageComponent(id: "devdata", name: "Developer data", paths: [],
                             bytes: 107_540_000_000, measured: true),
            StorageComponent(id: "documents", name: "Documents", paths: [],
                             bytes: 7_800_000_000, measured: true),
            StorageComponent(id: "media", name: "Media", paths: [],
                             bytes: 448_000_000, measured: true),
            StorageComponent(id: "downloads", name: "Downloads & Desktop", paths: [],
                             bytes: 255_500_000, measured: true),
            StorageComponent(id: "systemtemp", name: "System temp", paths: [],
                             bytes: 566_400_000, measured: true),
        ]
    }
}
