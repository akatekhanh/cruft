import Foundation
import SweepCore

/// The virtual disk files behind the container runtimes people use instead of
/// Docker Desktop — Colima, Lima, Podman, OrbStack, Rancher Desktop.
///
/// Why this deserves its own scanner: on a Mac that runs containers through a
/// VM, this file is routinely the largest single object on the disk (tens of
/// gigabytes), and it is invisible to every "clean my caches" tool because it
/// is one opaque file, not a cache directory. Worse, it is *sparse and
/// grow-only*: `docker system prune` frees space inside the guest filesystem
/// but the host file keeps its high-water mark, so a user who prunes 30 GB sees
/// no change on their disk and has no idea why.
///
/// Sweep therefore reports it as `risky` and explains that distinction rather
/// than offering a cheerful one-click fix: reclaiming the space really does
/// mean recreating the VM (`colima delete`, `limactl factory-reset`, and so
/// on), which is a decision, not a cleanup.
public struct ContainerVMScanner: CategoryScanner, Sendable {
    public let category: CleanCategory
    private let candidates: [(path: String, label: String)]
    private let minBytes: Int64

    /// Each runtime's disk-image location, as the runtime itself documents it.
    /// `Data/vms` (Docker Desktop) is deliberately absent — the `docker-data`
    /// category already owns it, and double-reporting the same bytes would
    /// inflate the totals.
    public static let defaultCandidates: [(path: String, label: String)] = [
        ("~/.colima/_lima", "Colima VM disk"),
        ("~/.lima", "Lima VM disks"),
        ("~/.local/share/containers/podman/machine", "Podman machine disk"),
        ("~/.orbstack/data", "OrbStack data"),
        ("~/Library/Application Support/rancher-desktop/lima", "Rancher Desktop VM disk"),
        ("~/.docker/desktop/vms", "Docker Desktop VM disk (legacy path)"),
    ]

    public init(category: CleanCategory,
                candidates: [(path: String, label: String)] = defaultCandidates,
                minBytes: Int64 = 100_000_000) {
        self.category = category
        self.candidates = candidates
        self.minBytes = minBytes
    }

    public func scan() async -> [ScanItem] {
        FSHelpers.safely {
            var items: [ScanItem] = []
            for candidate in candidates {
                let url = FSHelpers.expandTilde(candidate.path)
                var isDir = false
                guard FSHelpers.exists(url, isDirectory: &isDir) else { continue }
                let size = FSHelpers.sizeOf(url)
                // A stopped runtime that was never used leaves a few MB of
                // config behind; that is not worth a decision.
                guard size >= minBytes else { continue }
                items.append(ScanItem(
                    url: url,
                    displayName: candidate.label,
                    sizeBytes: size,
                    categoryID: category.id,
                    risk: category.risk,
                    lastModified: FSHelpers.lastModified(of: url),
                    lastAccessed: FSHelpers.lastAccessed(of: url)
                ))
            }
            return items
        }
    }
}
