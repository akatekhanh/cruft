import SwiftUI
import SweepCore
import SweepInfra

struct SweepApp: App {
    @State private var model = AppModel(
        scan: ScanUseCase(scanners: SweepInfraFactory.makeAllScanners()),
        clean: CleanUseCase(trash: SystemTrashService(),
                            specials: SweepInfraFactory.makeSpecialCleaners())
    )

    var body: some Scene {
        WindowGroup("Sweep") {
            RootView(model: model)
                .frame(minWidth: 980, minHeight: 640)
        }
        // .contentMinSize, not .contentSize: the Results list and the Overview
        // scroll view both want to grow, and the user should be free to resize
        // rather than have the window track the content's ideal height.
        .windowResizability(.contentMinSize)
    }
}

/// Entry point. `SWEEP_SNAPSHOT_DIR=<dir>` renders each screen to PNG offscreen
/// (no Screen Recording permission needed) and exits — used for visual self-checks.
@main
struct SweepMain {
    static func main() {
        if let dir = ProcessInfo.processInfo.environment["SWEEP_SNAPSHOT_DIR"] {
            MainActor.assumeIsolated { SnapshotRunner.run(outputDir: dir) }
        } else {
            SweepApp.main()
        }
    }
}
