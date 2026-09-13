import SwiftUI
import CruftCore

/// First-launch, full-window "Who is this Mac for?" role picker.
struct OnboardingView: View {
    var model: AppModel

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 300), spacing: 20),
    ]

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("Who is this Mac for?")
                    .font(.largeTitle.bold())
                Text("Cruft tailors what it scans to how you use this Mac. You can change this later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(Catalog.roles) { role in
                        RoleCard(role: role) {
                            model.choose(role: role)
                        }
                    }
                }
                .padding(32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

private struct RoleCard: View {
    let role: RoleProfile
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: role.systemImage)
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                }
                Text(role.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(role.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .padding(20)
            .frame(minHeight: 180)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.background.secondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isHovering ? Theme.accent.opacity(0.6) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
