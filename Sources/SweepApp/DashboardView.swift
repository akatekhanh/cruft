import SwiftUI
import SweepCore

/// Pre-scan dashboard: disk gauge, role chip, and the big Scan button.
struct DashboardView: View {
    var model: AppModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 6) {
                Text("\(ByteText.string(model.diskStats.availableBytes)) free of \(ByteText.string(model.diskStats.totalBytes))")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text("Sweep only looks at what matters for your role — nothing scary, just tidy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: model.role.systemImage)
                    .foregroundStyle(Theme.accent)
                Text("\(model.role.name) — \(model.role.blurb)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.startScan()
            } label: {
                Text("Scan")
                    .font(.headline)
                    .padding(.horizontal, 24)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.accent)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

