import SwiftUI
import CruftCore
import CruftInfra

struct CruftApp: App {
    @State private var model = AppModel(
        scan: ScanUseCase(scanners: CruftInfraFactory.makeAllScanners()),
        clean: CleanUseCase(trash: SystemTrashService(),
                            specials: CruftInfraFactory.makeSpecialCleaners())
    )

    var body: some Scene {
        WindowGroup("Cruft") {
            RootView(model: model)
                .frame(minWidth: 980, minHeight: 640)
        }
        // .contentMinSize, not .contentSize: the Results list and the Overview
        // scroll view both want to grow, and the user should be free to resize
        // rather than have the window track the content's ideal height.
        .windowResizability(.contentMinSize)
    }
}

/// Entry point. `CRUFT_SNAPSHOT_DIR=<dir>` renders each screen to PNG offscreen
/// (no Screen Recording permission needed) and exits — used for visual self-checks.
@main
struct CruftMain {
    static func main() {
        if let dir = ProcessInfo.processInfo.environment["CRUFT_SNAPSHOT_DIR"] {
            MainActor.assumeIsolated { SnapshotRunner.run(outputDir: dir) }
        } else {
            CruftApp.main()
        }
    }
}
