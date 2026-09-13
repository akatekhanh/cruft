import SwiftUI
import CruftCore

/// Machine info read once at launch (sysctl is cheap but never changes mid-run).
struct DeviceInfo {
    let name: String
    let modelID: String
    let chip: String
    let ramBytes: UInt64
    let osVersion: String

    static func current() -> DeviceInfo {
        DeviceInfo(
            name: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            modelID: sysctlString("hw.model"),
            chip: sysctlString("machdep.cpu.brand_string"),
            ramBytes: ProcessInfo.processInfo.physicalMemory,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }

    private static func sysctlString(_ key: String) -> String {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }

    var symbolName: String {
        let m = modelID.lowercased()
        if m.hasPrefix("macmini") { return "macmini.fill" }
        if m.hasPrefix("macbook") { return "laptopcomputer" }
        if m.hasPrefix("imac") { return "desktopcomputer" }
        return "desktopcomputer"
    }

    /// "Mac14,3 · Apple M2 · 16 GB RAM · macOS 15.x"
    var subtitle: String {
        var parts: [String] = []
        if !modelID.isEmpty { parts.append(modelID) }
        if !chip.isEmpty { parts.append(chip) }
        // RAM is sold in binary units — .memory style says 16 GB, not 17,18 GB.
        let ram = ByteCountFormatter()
        ram.countStyle = .memory
        parts.append("\(ram.string(fromByteCount: Int64(ramBytes))) RAM")
        parts.append("macOS \(osVersion.replacingOccurrences(of: "Version ", with: ""))")
        return parts.joined(separator: " · ")
    }
}

/// The Overview tab: who this Mac is and how full it is. Read-only, no buttons —
/// scanning lives in the role tabs.
struct OverviewView: View {
    var model: AppModel
    /// Injectable so snapshots can show a generic machine instead of the
    /// developer's own, and so tests don't depend on the host.
    var device: DeviceInfo = .current()
    /// Snapshots pre-load fixed numbers; measuring live would overwrite them.
    var measuresOnAppear = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                deviceHeader
                storageCard
            }
            .padding(40)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task {
            guard measuresOnAppear else { return }
            model.refreshDiskStats()
            model.startBreakdownIfNeeded()
        }
    }

    private var deviceHeader: some View {
        HStack(spacing: 16) {
            Image(systemName: device.symbolName)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Theme.accent)
                .frame(width: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.title.weight(.semibold))
                Text(device.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ByteText.string(model.diskStats.availableBytes))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                + Text(" free")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("of \(ByteText.string(model.diskStats.totalBytes)) — \(Int(model.diskStats.fractionUsed * 100))% used")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            StorageBreakdownView(components: model.storageBreakdown,
                                 diskStats: model.diskStats)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.background.secondary)
        )
    }
}
