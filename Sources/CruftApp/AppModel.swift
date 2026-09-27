import Foundation
import Observation
import CruftCore
import CruftInfra

/// Top-level state machine driving which screen is shown.
enum Phase {
    case onboarding
    case idle
    case scanning(ScanProgress)
    case results
    case done(CleanReport)
}

/// Disk usage snapshot for the root volume.
struct DiskStats {
    var totalBytes: Int64 = 0
    var availableBytes: Int64 = 0

    var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
    var fractionUsed: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
}

@MainActor
@Observable
final class AppModel {
    private static let roleDefaultsKey = "cruft.role"

    private let scanUseCase: ScanUseCase
    private let cleanUseCase: CleanUseCase

    var phase: Phase
    var role: RoleProfile
    /// Top tab: "overview" or a role id. Overview is a screen, not a role —
    /// switching to it never touches the scan state underneath.
    var selectedTab: String = "overview"
    var results: [CategoryScanResult] = []
    var selection: Set<String> = []
    /// nil means "All results" is selected in the sidebar.
    var selectedCategoryID: String?
    /// Risk sub-tab in the detail pane. nil shows every level grouped; a value
    /// shows that level alone so the user can review one confidence tier at a time.
    var riskFilter: RiskLevel?
    var diskStats = DiskStats()
    var isCleaning = false

    /// Storage breakdown for the Overview chart. Fixed identity order — the
    /// palette follows the entity, so slots must never re-sort by size.
    ///
    /// The list is deliberately longer than a tidy chart would like. Every slice
    /// missing here lands in "Other", and an Overview whose biggest slice is
    /// "Other" has explained nothing: the point of measuring developer data and
    /// the system temp area is that on a real working Mac they are where the
    /// space went.
    var storageBreakdown: [StorageComponent] = AppModel.initialBreakdown()

    static func initialBreakdown() -> [StorageComponent] {
        var components: [StorageComponent] = [
            StorageComponent(id: "apps", name: "Apps", paths: ["/Applications"]),
            StorageComponent(id: "appdata", name: "App data & caches", paths: ["~/Library"]),
            // Homebrew belongs here rather than in its own slice: it is developer
            // tooling, and one fewer slice keeps the palette clear of the red
            // step, which would read as a warning in a chart about disk space.
            StorageComponent(id: "devdata", name: "Developer data",
                             paths: DirectorySizer.developerDataPaths()
                                 + DirectorySizer.homebrewPaths()),
            StorageComponent(id: "documents", name: "Documents", paths: ["~/Documents"]),
            StorageComponent(id: "media", name: "Media",
                             paths: ["~/Movies", "~/Pictures", "~/Music"]),
            StorageComponent(id: "downloads", name: "Downloads & Desktop",
                             paths: ["~/Downloads", "~/Desktop"]),
        ]
        let temp = DirectorySizer.systemTempPaths()
        if !temp.isEmpty {
            components.append(StorageComponent(id: "systemtemp", name: "System temp",
                                               paths: temp))
        }
        return components
    }
    private var breakdownStarted = false

    init(scan: ScanUseCase, clean: CleanUseCase) {
        self.scanUseCase = scan
        self.cleanUseCase = clean

        if let savedID = UserDefaults.standard.string(forKey: Self.roleDefaultsKey),
           let saved = Catalog.role(savedID) {
            self.role = saved
            self.phase = .idle
        } else {
            self.role = Catalog.roles[0]
            self.phase = .onboarding
        }

        refreshDiskStats()
    }

    func refreshDiskStats() {
        let url = URL(fileURLWithPath: "/")
        do {
            let values = try url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
            ])
            var stats = DiskStats()
            if let total = values.volumeTotalCapacity {
                stats.totalBytes = Int64(total)
            }
            if let available = values.volumeAvailableCapacityForImportantUsage {
                stats.availableBytes = available
            }
            diskStats = stats
        } catch {
            diskStats = DiskStats()
        }
    }

    /// Measures each breakdown component off the main thread, filling the chart
    /// progressively. Once per launch — directory walks are not cheap.
    func startBreakdownIfNeeded() {
        guard !breakdownStarted else { return }
        breakdownStarted = true
        for index in storageBreakdown.indices {
            let paths = storageBreakdown[index].paths
            let id = storageBreakdown[index].id
            Task.detached(priority: .utility) {
                let bytes = DirectorySizer.totalSize(ofPaths: paths)
                await MainActor.run {
                    guard let i = self.storageBreakdown.firstIndex(where: { $0.id == id })
                    else { return }
                    self.storageBreakdown[i].bytes = bytes
                    self.storageBreakdown[i].measured = true
                }
            }
        }
    }

    func choose(role: RoleProfile) {
        self.role = role
        self.selectedTab = role.id
        UserDefaults.standard.set(role.id, forKey: Self.roleDefaultsKey)
        phase = .idle
    }

    /// Tab-bar click: Overview shows the machine status screen; anything else
    /// selects that role (and rescans if the user was reviewing results).
    func selectTab(_ id: String) {
        if id == "overview" {
            selectedTab = "overview"
            refreshDiskStats()
            return
        }
        guard let newRole = Catalog.role(id) else { return }
        selectedTab = id
        switchRole(to: newRole)
    }

    /// Tab-bar switch: picks the role and — if the user was already reviewing
    /// results — kicks off a scan of the new role right away, so moving across
    /// roles to clean the whole machine is one click per role.
    func switchRole(to newRole: RoleProfile) {
        guard newRole.id != role.id else { return }
        let wasReviewing: Bool
        switch phase {
        case .results, .done: wasReviewing = true
        default: wasReviewing = false
        }
        choose(role: newRole)
        results = []
        selection = []
        selectedCategoryID = nil
        riskFilter = nil
        if wasReviewing { startScan() }
    }

    func startScan() {
        phase = .scanning(ScanProgress(finished: 0, total: 1, currentCategoryName: "", bytesFoundSoFar: 0))
        let scanUseCase = scanUseCase
        let currentRole = role
        Task {
            let scanResults = await scanUseCase.run(for: currentRole) { progress in
                Task { @MainActor in
                    // Each update hops to the main actor in its own Task, so two
                    // can land out of order; never let the bar step backwards.
                    if case .scanning(let current) = self.phase,
                       progress.finished >= current.finished {
                        self.phase = .scanning(progress)
                    }
                }
            }
            self.results = scanResults
            self.selection = SelectionPolicy.defaultSelection(in: scanResults)
            self.selectedCategoryID = nil
            self.riskFilter = nil
            self.phase = .results
        }
    }

    func toggle(item: ScanItem) {
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    /// Selects (or deselects) every selectable item in a category. All items are
    /// selectable regardless of risk — only the *default* selection is safe-only.
    func toggleCategory(_ category: CleanCategory, select: Bool) {
        guard let result = results.first(where: { $0.category.id == category.id }) else { return }
        for item in result.items {
            if select {
                selection.insert(item.id)
            } else {
                selection.remove(item.id)
            }
        }
    }

    /// Select or deselect every item of a given risk level across the given
    /// categories. Selecting skips items that `SelectionPolicy.isBulkSelectable`
    /// rejects (permanent removals, iCloud files); deselecting clears them all.
    func setSelection(for risk: RiskLevel, select: Bool, in categories: [CategoryScanResult]) {
        for result in categories {
            for item in result.items where item.risk == risk {
                if select {
                    if SelectionPolicy.isBulkSelectable(item) { selection.insert(item.id) }
                } else {
                    selection.remove(item.id)
                }
            }
        }
    }

    var selectedBytes: Int64 {
        SelectionPolicy.selectedBytes(in: results, selection: selection)
    }

    var quickCleanItems: [ScanItem] {
        SelectionPolicy.quickCleanItems(in: results)
    }

    /// One click: select exactly the quick-clean set (Safe + Trash-recoverable)
    /// and clean it. Shown on the Smart Clean tab.
    func quickClean() {
        let items = quickCleanItems
        guard !items.isEmpty, !isCleaning else { return }
        selection = Set(items.map(\.id))
        clean()
    }

    var selectedCount: Int {
        results.flatMap(\.items).filter { selection.contains($0.id) }.count
    }

    /// True when the selection contains items that are removed permanently by an
    /// external tool (Docker) instead of going to the Trash — the footer copy
    /// must not promise "Trash" then.
    var selectionHasExternalRemoval: Bool {
        results.flatMap(\.items).contains { item in
            selection.contains(item.id)
                && Catalog.category(item.categoryID)?.removal == .external
        }
    }

    func clean() {
        guard !isCleaning else { return }
        let itemsToClean = results.flatMap(\.items).filter { selection.contains($0.id) }
        guard !itemsToClean.isEmpty else { return }
        isCleaning = true
        let cleanUseCase = cleanUseCase
        Task {
            let report = await Task.detached { cleanUseCase.run(items: itemsToClean) }.value
            let cleanedIDs = Set(itemsToClean.map(\.id)).subtracting(Set(report.failures.map { $0.item.id }))
            self.results = self.results.compactMap { result in
                let remaining = result.items.filter { !cleanedIDs.contains($0.id) }
                if remaining.isEmpty { return nil }
                return CategoryScanResult(category: result.category, items: remaining)
            }
            self.selection.subtract(cleanedIDs)
            self.isCleaning = false
            self.refreshDiskStats()
            self.phase = .done(report)
        }
    }

    func backToDashboard() {
        results = []
        selection = []
        selectedCategoryID = nil
        riskFilter = nil
        refreshDiskStats()
        phase = .idle
    }

    func rescan() {
        results = []
        selection = []
        selectedCategoryID = nil
        riskFilter = nil
        startScan()
    }
}
