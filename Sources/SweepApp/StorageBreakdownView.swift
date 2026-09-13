import SwiftUI
import SweepCore

/// One slice of the storage bar. `bytes` grows in as measurement finishes;
/// `measured == false` renders as a placeholder in the legend.
struct StorageComponent: Identifiable, Equatable {
    let id: String
    let name: String
    /// Paths summed for this component (empty for derived slices).
    let paths: [String]
    var bytes: Int64 = 0
    var measured = false
}

/// Categorical palette, validated for colour-vision deficiency and for contrast
/// against each mode's surface (see docs/DESIGN.md). The slot order is fixed and
/// tied to the component's identity, never to its size — a slice must not change
/// colour because the disk filled up.
///
/// Seven slots, taken in order from the reference palette's eight. The red
/// eighth step is deliberately left unused: in a chart about disk space a red
/// wedge reads as an alarm, and this app does not alarm people about their own
/// files. "Other" and "Free" are neutral fills rather than series hues, because
/// they are absences rather than things.
enum VizPalette {
    private static let light: [Color] = [
        Color(red: 0x2A / 255.0, green: 0x78 / 255.0, blue: 0xD6 / 255.0), // blue
        Color(red: 0xEB / 255.0, green: 0x68 / 255.0, blue: 0x34 / 255.0), // orange
        Color(red: 0x1B / 255.0, green: 0xAF / 255.0, blue: 0x7A / 255.0), // aqua
        Color(red: 0xED / 255.0, green: 0xA1 / 255.0, blue: 0x00 / 255.0), // yellow
        Color(red: 0xE8 / 255.0, green: 0x7B / 255.0, blue: 0xA4 / 255.0), // magenta
        Color(red: 0x00 / 255.0, green: 0x83 / 255.0, blue: 0x00 / 255.0), // green
        Color(red: 0x4A / 255.0, green: 0x3A / 255.0, blue: 0xA7 / 255.0), // violet
    ]
    private static let dark: [Color] = [
        Color(red: 0x39 / 255.0, green: 0x87 / 255.0, blue: 0xE5 / 255.0),
        Color(red: 0xD9 / 255.0, green: 0x59 / 255.0, blue: 0x26 / 255.0),
        Color(red: 0x19 / 255.0, green: 0x9E / 255.0, blue: 0x70 / 255.0),
        Color(red: 0xC9 / 255.0, green: 0x85 / 255.0, blue: 0x00 / 255.0),
        Color(red: 0xD5 / 255.0, green: 0x51 / 255.0, blue: 0x81 / 255.0),
        Color(red: 0x00 / 255.0, green: 0x83 / 255.0, blue: 0x00 / 255.0),
        Color(red: 0x90 / 255.0, green: 0x85 / 255.0, blue: 0xE9 / 255.0),
    ]

    static func series(_ slot: Int, scheme: ColorScheme) -> Color {
        let table = scheme == .dark ? dark : light
        return slot < table.count ? table[slot] : other(scheme: scheme)
    }
    static func other(scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.45) : Color(white: 0.55)
    }
    static func free(scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.22) : Color(white: 0.90)
    }
}

/// Horizontal stacked bar of what occupies the disk, plus a legend with the
/// numbers spelled out (the legend doubles as the required visible labels).
struct StorageBreakdownView: View {
    let components: [StorageComponent]
    let diskStats: DiskStats
    @Environment(\.colorScheme) private var scheme

    private struct Slice: Identifiable {
        let id: String
        let name: String
        let bytes: Int64
        let color: Color
        let measured: Bool
    }

    private var slices: [Slice] {
        var out: [Slice] = []
        var accounted: Int64 = 0
        for (i, c) in components.enumerated() {
            accounted += c.bytes
            out.append(Slice(id: c.id, name: c.name, bytes: c.bytes,
                             color: VizPalette.series(i, scheme: scheme),
                             measured: c.measured))
        }
        let stillMeasuring = components.contains { !$0.measured }
        // "Other" is honest only once everything else is measured — before that
        // it would just be the unmeasured remainder shrinking in real time.
        let other = stillMeasuring ? 0 : max(0, diskStats.usedBytes - accounted)
        out.append(Slice(id: "other", name: "Other", bytes: other,
                         color: VizPalette.other(scheme: scheme), measured: !stillMeasuring))
        out.append(Slice(id: "free", name: "Free", bytes: diskStats.availableBytes,
                         color: VizPalette.free(scheme: scheme), measured: true))
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            bar
            legend
            if let note = otherNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 660)
    }

    /// "Other" is whatever the measured slices don't account for, and on a Mac
    /// that is mostly the operating system — plus, awkwardly, space that no
    /// longer exists as files. Saying so is better than leaving the biggest
    /// slice unexplained, which is exactly what macOS's own storage screen does.
    private var otherNote: String? {
        guard let other = slices.first(where: { $0.id == "other" }),
              other.measured, other.bytes > 0,
              diskStats.usedBytes > 0 else { return nil }
        let share = Double(other.bytes) / Double(diskStats.usedBytes)
        guard share > 0.15 else { return nil }
        return """
            "Other" is macOS itself plus anything the slices above don't cover — \
            system files, APFS snapshots, and clones that share their data with \
            the original. Sweep doesn't offer to clean it, because most of it \
            either can't be removed or wouldn't free anything if it were.
            """
    }

    private var bar: some View {
        GeometryReader { geo in
            let total = max(diskStats.totalBytes, 1)
            HStack(spacing: 2) {
                ForEach(slices.filter { $0.bytes > 0 }) { slice in
                    Rectangle()
                        .fill(slice.color)
                        .frame(width: max(2, geo.size.width * CGFloat(slice.bytes) / CGFloat(total)))
                        .help("\(slice.name): \(ByteText.string(slice.bytes))")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .frame(height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var legend: some View {
        // 200pt keeps "Downloads & Desktop  255,5 MB" on one line — a legend
        // that wraps mid-label reads as two separate entries.
        let columns = [GridItem(.adaptive(minimum: 200), alignment: .leading)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(slices) { slice in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(slice.color)
                        .frame(width: 10, height: 10)
                    Text(slice.name)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(slice.measured ? ByteText.string(slice.bytes) : "measuring…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var accessibilitySummary: String {
        slices.map { "\($0.name) \(ByteText.string($0.bytes))" }
            .joined(separator: ", ")
    }
}
