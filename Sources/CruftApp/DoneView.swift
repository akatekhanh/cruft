import AppKit
import SwiftUI
import CruftCore

/// Calm summary shown after a clean completes.
struct DoneView: View {
    var model: AppModel
    let report: CleanReport

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            VStack(spacing: 6) {
                if report.externallyRemovedBytes > 0 {
                    Text("Cleaned \(ByteText.string(report.freedBytes)).")
                        .font(.title2.weight(.semibold))
                    let trashed = report.freedBytes - report.externallyRemovedBytes
                    Text(trashed > 0
                         ? "\(ByteText.string(trashed)) went to the Trash (restorable). \(ByteText.string(report.externallyRemovedBytes)) was removed permanently and cannot be restored."
                         : "Removed permanently — these items cannot be restored.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                } else {
                    Text("Moved \(ByteText.string(report.freedBytes)) to Trash.")
                        .font(.title2.weight(.semibold))
                    Text("You can restore anything from the Trash until you empty it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !report.failures.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A few items could not be moved:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(report.failures.prefix(5), id: \.item.id) { failure in
                        Text("\(failure.item.displayName): \(failure.message)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(12)
                .frame(maxWidth: 420, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.background.secondary)
                )
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Open Trash") {
                    NSWorkspace.shared.open(
                        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
                    )
                }
                .buttonStyle(.bordered)

                Button("Done") {
                    model.backToDashboard()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
