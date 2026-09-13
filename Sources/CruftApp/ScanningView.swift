import SwiftUI
import CruftCore

/// Determinate progress screen shown while scanning categories.
struct ScanningView: View {
    var model: AppModel
    let progress: ScanProgress

    private var fraction: Double {
        guard progress.total > 0 else { return 0 }
        return Double(progress.finished) / Double(progress.total)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(Theme.accent)
                .frame(maxWidth: 360)

            VStack(spacing: 6) {
                Text(progress.currentCategoryName.isEmpty ? "Finishing up…" : "Scanning \(progress.currentCategoryName)…")
                    .font(.headline)
                Text("Found \(ByteText.string(progress.bytesFoundSoFar)) so far")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
